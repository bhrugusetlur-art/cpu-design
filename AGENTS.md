# 8-bit CPU with Cache Hierarchy

> **For Codex:** After every session where files are created or modified, update this file — mark completed modules in the build progress table, add new files to the file reference section, and update any specs that changed. Keep this file accurate so future sessions have correct context.

## Goal
Build a fully working 8-bit CPU in Verilog, simulate and test every module, then **physically print/tape out the chip**. After the CPU and cache are complete, add virtual memory (TLB + MMU).

## Toolchain
- **Simulator:** Icarus Verilog — compile with `iverilog -g2012`, run with `vvp`
- **Waveforms:** WaveTrace (VSCode extension, 8-signal limit on free tier) or GTKWave
- **Target:** Physical chip fabrication (tapeout)

---

## Architecture

| Property | Value |
|---|---|
| Data width | 8-bit |
| Instruction width | 16-bit |
| Registers | R0–R3, PC, flags (Zero, Carry) |
| Memory model | Harvard (separate instruction + data memory) |

---

## ISA (12 instructions)

| Mnemonic | Opcode | Notes |
|---|---|---|
| MOV Rd, Rs | 0000 | register-to-register copy |
| MOV Rd, #imm | 0001 | load 8-bit immediate |
| ADD Rd, Rs | 0010 | Rd = Rd + Rs |
| SUB Rd, Rs | 0011 | Rd = Rd - Rs |
| AND Rd, Rs | 0100 | Rd = Rd & Rs |
| OR Rd, Rs | 0101 | Rd = Rd \| Rs |
| NOT Rd | 0110 | Rd = ~Rd |
| LOAD Rd, [Rs] | 0111 | Rd = mem[Rs] |
| STORE Rs, [Rd] | 1000 | mem[Rd] = Rs |
| JMP addr | 1001 | unconditional jump |
| JZ addr | 1010 | jump if Zero flag set |
| HALT | 1111 | stop execution |

ALU op select uses `instr[2:0]` directly (ADD=010, SUB=011, AND=100, OR=101, NOT=110), so `control.v` can pass instruction bits straight to the ALU without translation.

---

## Cache Hierarchy

### L1 Cache (`l1_cache.v`)
| Property | Value |
|---|---|
| Lines | 8 |
| Mapping | Direct-mapped |
| Block size | 4 bytes |
| Write policy | Write-back |
| Replacement | N/A (direct-mapped) |

### L2 Cache (`l2_cache.v`)
| Property | Value |
|---|---|
| Sets | 8 |
| Ways | 4 (set-associative) |
| Total lines | 32 |
| Block size | 4 bytes |
| Write policy | Write-back |
| Replacement | LRU (2-bit age counter per way: 0=LRU, 3=MRU) |

### Address Breakdown (8-bit, same for both caches)
```
[7:5] tag    (3 bits)
[4:2] index  (3 bits → 8 lines/sets)
[1:0] offset (2 bits → 4 bytes/block)
```

### Inter-module interfaces
- **L1 CPU side:** `cpu_addr/wdata/we/req` in, `cpu_rdata/stall` out
- **L1 L2 side / L2 CPU side:** `l2_addr/wdata/we/re` out of L1, `l2_rdata/ready` in — these names match L2's `cpu_*` ports so `cache_hierarchy.v` wires them directly
- **L2 memory side:** `mem_addr/wdata/we/re` out, `mem_rdata/ready` in

---

## ALU

Combinational, no clock. `op[2:0]` matches ISA opcode bits directly.

| op | Operation | Carry flag |
|---|---|---|
| 010 | ADD | 1 if unsigned overflow |
| 011 | SUB | 1 if no borrow (a ≥ b) |
| 100 | AND | 0 |
| 101 | OR | 0 |
| 110 | NOT | 0 |

Zero flag: continuous assign `zero = (result == 8'h00)`.

SUB uses 2's complement: `diff = a + ~b + 1`.

---

## Register File

- 4 × 8-bit registers (R0–R3)
- **2 asynchronous read ports** (`rs1`, `rs2`) — combinational `assign`, no clock needed
- **1 synchronous write port** (`rd`) — fires on rising clock edge when `wr_en=1`
- Read-during-write returns the **old** value (write visible next cycle)
- Port naming: `rs` = register source, `rd` = register destination

---

## Build Progress

| # | File | Status | Tests |
|---|---|---|---|
| 1 | `l1_cache.v` | ✅ done | 4/4 pass |
| 2 | `l2_cache.v` | ✅ done | 4/4 pass |
| 3 | `cache_hierarchy.v` | ✅ done | 4/4 pass |
| 4 | `alu.v` | ✅ done | 15/15 pass |
| 5 | `reg_file.v` | ✅ done | 6/6 pass |
| 6 | `imem.v` | ✅ done | 5/5 pass |
| 7 | `dmem.v` | ✅ done | 4/4 pass |
| 8 | `control.v` | ✅ done | 12/12 pass |
| 9 | `pc.v` | ✅ done | 11/11 pass |
| 10 | `datapath.v` | ✅ done | 5/5 pass |
| 11 | `cpu_top.v` | ✅ done | 5/5 pass |
| 12 | `assembler.cpp` | ✅ done | Assembler tests pass |
| 13 | `basys3_top.v` | ✅ done | Compile check passes |
| 14 | `tlb.v` | 📝 design approved | Tests planned |
| 15 | `mmu.v` | 📝 design approved | Tests planned |

---

## Virtual Memory v1 (design approved; implementation pending)

- Translate LOAD/STORE data addresses only; instruction fetch remains physical.
- 16-byte pages: `VA[7:4]` is VPN and `VA[3:0]` is the offset.
- The one-level PTE table occupies physical `0xF0–0xFF`; `PTE[7]` is valid and `PTE[3:0]` is PPN.
- `mmu.v` owns the cache request handshake, uses `tlb.v` for translation, walks PTEs through L1/L2 on a miss, and freezes the CPU on an invalid PTE.
- A completed physical STORE to `0xF0–0xFF` flushes the TLB to keep writable PTEs coherent.
- FPGA/simulation boot uses an identity-mapped PTE image; a tapeout revision needs an explicit boot ROM or loader.
- Full design: `docs/superpowers/specs/2026-07-09-virtual-memory-design.md`.

---

## File Reference

| File | Description |
|---|---|
| `l1_cache.v` | Direct-mapped write-back L1 cache |
| `l1_cache_tb.v` | L1 testbench (cold miss, hit, write-back, eviction) |
| `l2_cache.v` | 4-way set-associative write-back L2 cache with LRU |
| `l2_cache_tb.v` | L2 testbench (cold miss, hit, write hit, LRU eviction) |
| `cache_hierarchy.v` | Wires L1 → L2 → memory, stall propagation via L1 |
| `cache_hierarchy_tb.v` | Hierarchy testbench (cold, L1 hit, L2 hit, full writeback chain) |
| `alu.v` | Combinational ALU: ADD, SUB, AND, OR, NOT with Z/C flags |
| `alu_tb.v` | ALU testbench (all 5 ops, overflow, zero, carry/borrow cases) |
| `reg_file.v` | 4×8-bit register file, 2 read ports, 1 write port |
| `reg_file_tb.v` | Register file testbench (reset, write/read, dual-port, wr_en guard, read-during-write) |
| `imem.v` | Instruction ROM: 256×16-bit, async read, loaded from `.mem` file via `$readmemh` |
| `imem_tb.v` | imem testbench (5 address read-back checks) |
| `test_imem.mem` | 5-instruction hex file used by imem testbench |
| `program.mem` | Placeholder program ROM (single HALT); replace with assembled program |
| `dmem.v` | Synchronous data RAM: 256×8-bit, 1-cycle read latency, ready handshake for cache wiring |
| `dmem_tb.v` | dmem testbench (write/read, multi-address, isolation, idle ready=0) |
| `control.v` | Combinational decoder: opcode → alu_op, wb_sel, reg_wr_en, mem_req/we, jump, branch, halt |
| `control_tb.v` | control testbench (all 12 opcodes, rd_addr/rs1_addr/imm slice checks) |
| `pc.v` | Program counter: increment, JMP, JZ (with zero_flag), stall hold, halt freeze |
| `pc_tb.v` | pc testbench (reset, increment, JMP, JZ taken/skipped, stall, halt) |
| `datapath.v` | Wires pc, imem, control, reg_file, alu; write-back mux; cache interface ports |
| `datapath_tb.v` | datapath testbench (MOV/ADD/STORE/LOAD/HALT program, 0-latency memory stub) |
| `test_datapath.mem` | 7-instruction test program: MOV×3, ADD, STORE, LOAD, HALT |
| `cpu_top.v` | Top-level: wires datapath → cache_hierarchy → dmem; req_pending + mem_stall handshake fixes registered-stall timing |
| `cpu_top_tb.v` | cpu_top testbench: real cache+dmem, 5 checks (halt, R0–R3, L1 dirty line) |
| `dbg_cputop.v` | Debug harness for tracing `cpu_top` execution and cache request timing |
| `basys3_top.v` | Basys3 FPGA wrapper for `cpu_top`: 100 MHz clock divider, debounced reset, single-step mode, LEDs, and 4-digit seven-segment PC display |
| `assembler.cpp` | Two-pass C++ assembler for the ISA; supports labels, decimal/hex immediates, register operands, and `.mem` output padded to 256 words |
| `tests/run_assembler_tests.sh` | Assembler regression tests for encoding, labels, output padding, and error reporting |
| `docs/superpowers/specs/2026-07-09-virtual-memory-design.md` | Approved VM v1 design: TLB, cache-mediated page walk, PTE format, PTE-store flush, boot image, and tests |

---

## How to run any testbench
```bash
# Pattern: iverilog -g2012 -o <sim> <tb>.v <dut>.v [dependencies] && vvp <sim>

iverilog -g2012 -o l1_sim   l1_cache_tb.v l1_cache.v && vvp l1_sim
iverilog -g2012 -o l2_sim   l2_cache_tb.v l2_cache.v && vvp l2_sim
iverilog -g2012 -o hier_sim cache_hierarchy_tb.v cache_hierarchy.v l1_cache.v l2_cache.v && vvp hier_sim
iverilog -g2012 -o alu_sim  alu_tb.v alu.v && vvp alu_sim
iverilog -g2012 -o rf_sim   reg_file_tb.v reg_file.v && vvp rf_sim
iverilog -g2012 -o imem_sim imem_tb.v imem.v && vvp imem_sim
iverilog -g2012 -o dmem_sim dmem_tb.v dmem.v && vvp dmem_sim
iverilog -g2012 -o ctrl_sim control_tb.v control.v && vvp ctrl_sim
iverilog -g2012 -o pc_sim   pc_tb.v pc.v && vvp pc_sim
iverilog -g2012 -o dp_sim   datapath_tb.v datapath.v pc.v imem.v control.v reg_file.v alu.v && vvp dp_sim
iverilog -g2012 -o top_sim  cpu_top_tb.v cpu_top.v datapath.v cache_hierarchy.v l1_cache.v l2_cache.v dmem.v pc.v imem.v control.v reg_file.v alu.v && vvp top_sim
bash tests/run_assembler_tests.sh
```
