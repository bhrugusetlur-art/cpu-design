# Virtual Memory v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a four-entry TLB and cache-mediated MMU for virtual LOAD/STORE addresses, preserving existing CPU behavior through an identity-mapped boot page table.

**Architecture:** `datapath` continues to produce virtual data requests. A new `mmu` owns the request handshake, looks up a new fully associative `tlb`, walks PTEs through the existing physical cache hierarchy on misses, and either replays the translated access or freezes on a page fault. `dmem` supplies an FPGA/simulation identity-map image at configuration time.

**Tech Stack:** Verilog-2012, Icarus Verilog (`iverilog -g2012`, `vvp`), Basys3 FPGA wrapper.

---

## File structure

| File | Responsibility |
|---|---|
| `design/tlb.v` | Four-entry associative VPN→PPN lookup, round-robin fill, synchronous flush. |
| `sim/tlb_tb.v` | Isolated TLB regression. |
| `design/dmem.v` | Preserve the RAM protocol and initialize PTE bytes `0xF0–0xFF` to identity mappings. |
| `sim/dmem_tb.v` | Add checks for the boot PTE image without changing existing RAM tests. |
| `design/mmu.v` | Capture virtual transactions, walk PTEs through the cache, replay physical requests, fault, and flush after a PTE STORE. |
| `sim/mmu_tb.v` | MMU FSM regression driven by a deterministic cache-side responder. |
| `design/cpu_top.v` | Replace `req_pending` with datapath → MMU → cache wiring and export fault debug signals. |
| `design/basys3_top.v` | Display fault state and faulting VA in the final debug view. |
| `sim/cpu_vm_tb.v` | Full CPU/cache/dmem regression for remap, PTE-store flush, and fault freeze. |
| `sim/vm_program.mem` | Program consumed by `cpu_vm_tb.v`. |
| `README.md`, `AGENTS.md` | Update debug-view and VM module/test instructions after implementation. |

### Task 1: TLB module and isolated regression

**Files:**
- Create: `design/tlb.v`
- Create: `sim/tlb_tb.v`

- [ ] **Step 1: Write the failing TLB regression**

Create `sim/tlb_tb.v` with the TLB interface below. Test reset miss, fill-and-hit, deterministic round-robin replacement after five fills, and flush:

```verilog
tlb dut (
    .clk(clk), .rst(rst),
    .lookup_vpn(lookup_vpn), .hit(hit), .hit_ppn(hit_ppn),
    .fill(fill), .fill_vpn(fill_vpn), .fill_ppn(fill_ppn),
    .flush(flush)
);

// Fill VPN 0..3 with PPN 8..11, then VPN 4 with PPN 12.
// Assert VPN 0 misses after the fifth fill while VPN 4 hits PPN 12.
// Assert every VPN misses after a one-clock flush pulse.
```

Use a `fill_entry` task that drives `fill=1` on a negedge, waits one posedge, then drives `fill=0`; use a `check_lookup` task that sets `lookup_vpn`, waits `#1`, and compares both `hit` and `hit_ppn`. End with `$fatal(1)` if `fail_cnt != 0`.

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
iverilog -g2012 -o /tmp/tlb_sim sim/tlb_tb.v design/tlb.v && vvp /tmp/tlb_sim
```

Expected: compilation fails because `design/tlb.v` does not exist.

- [ ] **Step 3: Implement `design/tlb.v`**

Implement this exact port contract and storage shape:

```verilog
module tlb (
    input  wire       clk, rst,
    input  wire [3:0] lookup_vpn,
    output wire       hit,
    output wire [3:0] hit_ppn,
    input  wire       fill,
    input  wire [3:0] fill_vpn, fill_ppn,
    input  wire       flush
);
    reg       valid [0:3];
    reg [3:0] vpn   [0:3];
    reg [3:0] ppn   [0:3];
    reg [1:0] replace_way;

    wire hit0 = valid[0] && vpn[0] == lookup_vpn;
    wire hit1 = valid[1] && vpn[1] == lookup_vpn;
    wire hit2 = valid[2] && vpn[2] == lookup_vpn;
    wire hit3 = valid[3] && vpn[3] == lookup_vpn;
    assign hit = hit0 | hit1 | hit2 | hit3;
    assign hit_ppn = hit0 ? ppn[0] : hit1 ? ppn[1] :
                     hit2 ? ppn[2] : hit3 ? ppn[3] : 4'h0;
```

On reset, clear `valid[]` and set `replace_way` to zero. On `flush`, clear only `valid[]` and leave `replace_way` unchanged. Otherwise, on `fill`, write `valid[replace_way]`, `vpn[replace_way]`, and `ppn[replace_way]`, then increment `replace_way` modulo four.

- [ ] **Step 4: Run the isolated TLB regression**

Run:

```bash
iverilog -g2012 -o /tmp/tlb_sim sim/tlb_tb.v design/tlb.v && vvp /tmp/tlb_sim
```

Expected: all reset, lookup, eviction, and flush checks pass.

- [ ] **Step 5: Commit the TLB slice**

```bash
git add design/tlb.v sim/tlb_tb.v
git commit -m "feat: add four-entry TLB"
```

### Task 2: Identity page-table boot image

**Files:**
- Modify: `design/dmem.v:16-30`
- Modify: `sim/dmem_tb.v:55-65`

- [ ] **Step 1: Add failing PTE boot-image assertions**

At the start of `dmem_tb`'s `initial` block, after initializing inputs and waiting one clock, add direct RAM checks:

```verilog
if (dut.mem[8'hF0] !== 8'h80 ||
    dut.mem[8'hF5] !== 8'h85 ||
    dut.mem[8'hFF] !== 8'h8F) begin
    $display("  FAIL: identity PTE boot image missing");
    fail_cnt = fail_cnt + 1;
end else begin
    $display("  PASS: identity PTE boot image");
    pass_cnt = pass_cnt + 1;
end
```

- [ ] **Step 2: Run the RAM test to verify it fails**

Run:

```bash
iverilog -g2012 -o /tmp/dmem_sim sim/dmem_tb.v design/dmem.v && vvp /tmp/dmem_sim
```

Expected: the new boot-image assertion fails because the PTE array is uninitialized.

- [ ] **Step 3: Initialize only the PTE range in `dmem.v`**

Add an `integer init_i;` and this FPGA/simulation initialization block before the existing sequential RAM process:

```verilog
initial begin
    for (init_i = 0; init_i < 16; init_i = init_i + 1)
        mem[8'hF0 + init_i] = 8'h80 | init_i[7:0];
end
```

Do not add a reset port and do not clear ordinary RAM bytes. The table must survive CPU reset so a program can overwrite PTEs.

- [ ] **Step 4: Run the RAM regression**

Run:

```bash
iverilog -g2012 -o /tmp/dmem_sim sim/dmem_tb.v design/dmem.v && vvp /tmp/dmem_sim
```

Expected: the new boot-image assertion and all four pre-existing RAM checks pass.

- [ ] **Step 5: Commit the boot-image slice**

```bash
git add design/dmem.v sim/dmem_tb.v
git commit -m "feat: initialize virtual memory page table"
```

### Task 3: MMU FSM and unit regression

**Files:**
- Create: `design/mmu.v`
- Create: `sim/mmu_tb.v`
- Depends on: `design/tlb.v`

- [ ] **Step 1: Write the failing MMU regression**

Create an MMU testbench with this port wiring:

```verilog
mmu dut (
    .clk(clk), .rst(rst),
    .cpu_addr(cpu_addr), .cpu_wdata(cpu_wdata), .cpu_we(cpu_we), .cpu_req(cpu_req),
    .cpu_rdata(cpu_rdata), .stall(stall),
    .cache_addr(cache_addr), .cache_wdata(cache_wdata),
    .cache_we(cache_we), .cache_req(cache_req),
    .cache_rdata(cache_rdata), .cache_stall(cache_stall),
    .page_fault(page_fault), .fault_va(fault_va)
);
```

Implement a test-local cache responder: on `cache_req`, capture the request, raise `cache_stall` for two clocks, then return `page_table[captured_addr - 8'hF0]` for PTE reads and `physical_mem[captured_addr]` for other reads. On a write in `0xF0–0xFF`, update `page_table[captured_addr - 8'hF0]`; otherwise update `physical_mem[captured_addr]`. Seed `page_table[2] = 8'h83`, `page_table[4] = 8'h00`, and `page_table[15] = 8'h8F`.

Write checks for all of these transactions:

```verilog
// First LOAD VA 0x21: walk reads PA 0xF2, then replay reads PA 0x31.
// Second LOAD VA 0x22: no PTE walk; only replay reads PA 0x32.
// STORE VA 0xF2: resolves to PA 0xF2 and flushes all TLB entries.
// Next LOAD VA 0x21: walks again after the flush.
// LOAD VA 0x40: PTE 0xF4 is invalid; page_fault=1, fault_va=0x40, stall remains 1.
```

Count cache requests and assert the first load uses two, the hit uses one, and the post-PTE-store load uses two. Confirm no cache request occurs after the fault.

- [ ] **Step 2: Run the MMU test to verify it fails**

Run:

```bash
iverilog -g2012 -o /tmp/mmu_sim sim/mmu_tb.v design/mmu.v design/tlb.v && vvp /tmp/mmu_sim
```

Expected: compilation fails because `design/mmu.v` does not exist.

- [ ] **Step 3: Implement the MMU state machine**

Use this exact interface and state set:

```verilog
module mmu (
    input wire clk, rst,
    input wire [7:0] cpu_addr, cpu_wdata,
    input wire cpu_we, cpu_req,
    output wire [7:0] cpu_rdata,
    output reg stall,
    output reg [7:0] cache_addr, cache_wdata,
    output reg cache_we, cache_req,
    input wire [7:0] cache_rdata,
    input wire cache_stall,
    output reg page_fault,
    output reg [7:0] fault_va
);
localparam IDLE = 3'd0, WALK_ISSUE = 3'd1, WALK_WAIT = 3'd2,
           ACCESS_ISSUE = 3'd3, ACCESS_WAIT = 3'd4, FAULT = 3'd5;
```

Capture `saved_va`, `saved_wdata`, and `saved_we` in IDLE. Instantiate `tlb` with `lookup_vpn = cpu_addr[7:4]`; a hit stores `{hit_ppn, cpu_addr[3:0]}` as `saved_pa` and transitions to `ACCESS_ISSUE`, while a miss transitions to `WALK_ISSUE`. In WALK, drive one `cache_req` read at `8'hF0 + saved_va[7:4]`; when it completes, use `cache_rdata[7]` for validity and `cache_rdata[3:0]` for the PPN. A valid PTE fills the TLB and transitions to `ACCESS_ISSUE`; an invalid PTE latches `fault_va = saved_va` and transitions to FAULT.

Drive exactly one replay request in ACCESS with `cache_addr = saved_pa`, `cache_wdata = saved_wdata`, and `cache_we = saved_we`. Use this stall policy so datapath never completes a walk response as a LOAD:

```verilog
always @(*) begin
    stall = 1'b1;
    case (state)
        IDLE:        stall = cpu_req;
        ACCESS_WAIT: stall = cache_stall;
        default:     stall = 1'b1;
    endcase
end
assign cpu_rdata = cache_rdata;
```

Assert the TLB `flush` combinationally for the completion cycle of an ACCESS write whose `saved_pa[7:4] == 4'hF`. This ensures the TLB clears on the next clock before a later request can reuse the old translation. In FAULT, never issue `cache_req`, keep `page_fault` asserted, and hold `fault_va` until reset.

- [ ] **Step 4: Run the MMU regression**

Run:

```bash
iverilog -g2012 -o /tmp/mmu_sim sim/mmu_tb.v design/mmu.v design/tlb.v && vvp /tmp/mmu_sim
```

Expected: walk/replay, hit, PTE-store flush, and fault tests all pass.

- [ ] **Step 5: Commit the MMU slice**

```bash
git add design/mmu.v sim/mmu_tb.v
git commit -m "feat: add cache-mediated MMU"
```

### Task 4: Integrate the MMU and fault debug path

**Files:**
- Modify: `design/cpu_top.v:20-89`
- Modify: `design/basys3_top.v:59-112`
- Modify: `README.md:20-45`
- Create: `sim/cpu_vm_tb.v`

- [ ] **Step 1: Add a failing top-level MMU-wiring harness**

Create the initial `sim/cpu_vm_tb.v` harness with the new top-level debug ports:

```verilog
module cpu_vm_tb;
    reg clk = 0, rst = 1;
    wire halt, debug_page_fault;
    wire [7:0] pc_out, debug_fault_va;
    wire [7:0] debug_r0, debug_r1, debug_r2, debug_r3;
    wire debug_zero_flag, debug_cpu_req, debug_cpu_we, debug_stall;
    wire [15:0] debug_instr;
    wire [7:0] debug_cpu_addr;

    cpu_top #(.MEM_FILE("sim/vm_program.mem")) dut (
        .clk(clk), .rst(rst), .halt(halt), .pc_out(pc_out),
        .debug_r0(debug_r0), .debug_r1(debug_r1), .debug_r2(debug_r2), .debug_r3(debug_r3),
        .debug_zero_flag(debug_zero_flag), .debug_instr(debug_instr),
        .debug_cpu_addr(debug_cpu_addr), .debug_cpu_req(debug_cpu_req),
        .debug_cpu_we(debug_cpu_we), .debug_stall(debug_stall),
        .debug_page_fault(debug_page_fault), .debug_fault_va(debug_fault_va)
    );
    always #5 clk = ~clk;
endmodule
```

Compile it before rewiring:

```bash
iverilog -g2012 -o /tmp/vm_wiring_sim sim/cpu_vm_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v
```

Expected: compilation fails because `cpu_top` does not yet expose `debug_page_fault` and `debug_fault_va`.

- [ ] **Step 2: Replace `req_pending` wiring in `cpu_top.v`**

Remove the `req_pending`, `cache_req`, and `mem_stall` block. Keep the datapath interface unchanged, but connect it to the MMU and connect the MMU cache-side port to `cache_hierarchy`:

```verilog
wire [7:0] mmu_addr, mmu_wdata, mmu_rdata;
wire mmu_we, mmu_req, mmu_stall;

mmu vm (
    .clk(clk), .rst(rst),
    .cpu_addr(dp_cpu_addr), .cpu_wdata(dp_cpu_wdata),
    .cpu_we(dp_cpu_we), .cpu_req(dp_cpu_req),
    .cpu_rdata(dp_cpu_rdata), .stall(mmu_stall),
    .cache_addr(mmu_addr), .cache_wdata(mmu_wdata),
    .cache_we(mmu_we), .cache_req(mmu_req),
    .cache_rdata(mmu_rdata), .cache_stall(dp_stall),
    .page_fault(debug_page_fault), .fault_va(debug_fault_va)
);
```

Wire `cache_hierarchy.cpu_*` to `mmu_*`, wire its `cpu_rdata` to `mmu_rdata`, and pass `mmu_stall` to `datapath.stall`. Export `debug_page_fault` and `debug_fault_va` as new `cpu_top` outputs. Keep `debug_cpu_addr` as the datapath virtual address and set `debug_cpu_req = mmu_req`, `debug_cpu_we = mmu_we`, and `debug_stall = mmu_stall`.

- [ ] **Step 3: Add the Basys3 fault display and README description**

Add wires for the new core outputs. Replace `SW5:SW4 = 11` LED packing with:

```verilog
default: led_value = {debug_fault_va, 3'b000, debug_page_fault,
                      debug_zero_flag, debug_stall, cpu_clk, halt};
```

Update `README.md` so this view documents `LED[15:8] = debug_fault_va` and `LED[4] = debug_page_fault`; retain descriptions for the zero flag, stall, heartbeat, and halt bits.

- [ ] **Step 4: Run existing top-level regressions**

Run:

```bash
iverilog -g2012 -o /tmp/top_sim sim/cpu_top_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp /tmp/top_sim
iverilog -g2012 -o /tmp/programs_sim sim/cpu_programs_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp /tmp/programs_sim
```

Expected: both retain their existing architectural-state checks. Only increase their timeout constants if fresh output proves 500 cycles is insufficient.

- [ ] **Step 5: Commit integration and debug wiring**

```bash
git add design/cpu_top.v design/basys3_top.v README.md sim/cpu_vm_tb.v
git commit -m "feat: wire virtual memory into CPU top"
```

### Task 5: Full CPU virtual-memory program regression and documentation

**Files:**
- Create: `sim/vm_program.mem`
- Modify: `sim/cpu_vm_tb.v`
- Modify: `AGENTS.md`

- [ ] **Step 1: Complete the VM program and integration test**

Create `sim/vm_program.mem` with this program:

```text
1083
14f2
8400
1821
1c5a
8b00
7200
1000
14f4
8400
1840
7e00
```

It writes valid PTE `0x83` to VA/PA `0xF2`, stores and loads `0x5A` at remapped VA `0x21` → PA `0x31`, invalidates PTE `0xF4`, then faults on VA `0x40`.

Replace the wiring-only `sim/cpu_vm_tb.v` body with a regression using `cpu_top #(.MEM_FILE("sim/vm_program.mem"))`. Run for at most 1200 cycles or until `debug_page_fault`; then assert:

```verilog
check8(debug_page_fault, 1'b1, "page fault asserted");
check8(debug_fault_va, 8'h40, "faulting virtual address");
check8(dut.dp.rf_inst.regs[0], 8'h00, "PTE invalidation value");
check8(dut.dp.rf_inst.regs[3], 8'h5A, "faulting LOAD did not write R3");
check8(dut.cache.l1.data[4][1], 8'h5A, "remapped PA 0x31 cached data");
```

After observing the fault, wait five more clock edges and assert the same PC, fault VA, and R3 value remain unchanged.

- [ ] **Step 2: Run the VM regression to verify it fails**

Run:

```bash
iverilog -g2012 -o /tmp/vm_sim sim/cpu_vm_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp /tmp/vm_sim
```

Expected: failure until Tasks 1–4 are complete; then use the failure details to correct the VM test or integration rather than weakening its architectural checks.

- [ ] **Step 3: Run the complete hardware regression suite**

Run each existing unit test plus the new TLB, MMU, and VM tests:

```bash
iverilog -g2012 -o /tmp/l1_sim sim/l1_cache_tb.v design/l1_cache.v && vvp /tmp/l1_sim
iverilog -g2012 -o /tmp/l2_sim sim/l2_cache_tb.v design/l2_cache.v && vvp /tmp/l2_sim
iverilog -g2012 -o /tmp/hier_sim sim/cache_hierarchy_tb.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v && vvp /tmp/hier_sim
iverilog -g2012 -o /tmp/alu_sim sim/alu_tb.v design/alu.v && vvp /tmp/alu_sim
iverilog -g2012 -o /tmp/rf_sim sim/reg_file_tb.v design/reg_file.v && vvp /tmp/rf_sim
iverilog -g2012 -o /tmp/imem_sim sim/imem_tb.v design/imem.v && vvp /tmp/imem_sim
iverilog -g2012 -o /tmp/dmem_sim sim/dmem_tb.v design/dmem.v && vvp /tmp/dmem_sim
iverilog -g2012 -o /tmp/ctrl_sim sim/control_tb.v design/control.v && vvp /tmp/ctrl_sim
iverilog -g2012 -o /tmp/pc_sim sim/pc_tb.v design/pc.v && vvp /tmp/pc_sim
iverilog -g2012 -o /tmp/dp_sim sim/datapath_tb.v design/datapath.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp /tmp/dp_sim
iverilog -g2012 -o /tmp/tlb_sim sim/tlb_tb.v design/tlb.v && vvp /tmp/tlb_sim
iverilog -g2012 -o /tmp/mmu_sim sim/mmu_tb.v design/mmu.v design/tlb.v && vvp /tmp/mmu_sim
iverilog -g2012 -o /tmp/top_sim sim/cpu_top_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp /tmp/top_sim
iverilog -g2012 -o /tmp/programs_sim sim/cpu_programs_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp /tmp/programs_sim
iverilog -g2012 -o /tmp/vm_sim sim/cpu_vm_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp /tmp/vm_sim
bash tests/run_assembler_tests.sh
```

Expected: every command exits zero. Use `/tmp` outputs so generated simulators do not dirty the worktree.

- [ ] **Step 4: Update durable project context**

Update `AGENTS.md` after the verified implementation:

```markdown
| 14 | `tlb.v` | ✅ done | `tlb_tb.v` passes |
| 15 | `mmu.v` | ✅ done | `mmu_tb.v` passes |
```

Add `tlb.v`, `tlb_tb.v`, `mmu.v`, `mmu_tb.v`, `cpu_vm_tb.v`, and `vm_program.mem` to File Reference. Replace the VM “design approved” wording with the verified address format, PTE-store flush rule, FPGA boot-image limitation, and exact VM test command.

- [ ] **Step 5: Commit the VM regression and documentation**

```bash
git add sim/vm_program.mem sim/cpu_vm_tb.v AGENTS.md
git commit -m "test: cover virtual memory remap and faults"
```
