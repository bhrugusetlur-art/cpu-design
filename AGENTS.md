# 8-bit CPU with Cache Hierarchy

> **Maintenance:** whenever files are created or modified, update this file — mark completed modules in the build progress table, add new files to the file reference section, and update any specs that changed. Keep this file accurate so it stays a correct map of the project.

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
| 3 | `cache_hierarchy.v` | ✅ done | 5/5 pass |
| 4 | `alu.v` | ✅ done | 15/15 pass |
| 5 | `reg_file.v` | ✅ done | 6/6 pass |
| 6 | `imem.v` | ✅ done | 5/5 pass |
| 7 | `dmem.v` | ✅ done | 5/5 pass |
| 8 | `control.v` | ✅ done | 12/12 pass |
| 9 | `pc.v` | ✅ done | 11/11 pass |
| 10 | `datapath.v` | ✅ done | 5/5 pass |
| 11 | `cpu_top.v` | ✅ done | 5/5 pass |
| 12 | `assembler.cpp` | ✅ done | Assembler tests pass |
| 13 | `basys3_top.v` | ✅ done | Compile check passes |
| 14 | `tlb.v` | ✅ done | `tlb_tb.v` passes |
| 15 | `mmu.v` | ✅ done | `mmu_tb.v` passes |
| 16 | VM integration | ✅ done | `cpu_vm_tb.v` passes |
| 17 | Sky130 ORFS core hardening | ✅ core GDS verified | ORFS/STA/route DRC/KLayout DRC and project-deck electrical LVS clean |

---

## Virtual Memory v1 (implemented and verified)

- LOAD/STORE data addresses are virtual; instruction fetch stays physical (Harvard).
- 16-byte pages: `VA[7:4]` = VPN, `VA[3:0]` = offset; a valid translation yields `{PTE[3:0], offset}`.
- One-level PTE table at physical `0xF0–0xFF` (PTE for VPN `n` at `0xF0+n`); `PTE[7]` = valid, `PTE[3:0]` = PPN, `PTE[6:4]` ignored by the MMU.
- `mmu.v` owns the L1 request handshake (replaced `cpu_top`'s old `req_pending` logic). FSM: IDLE → WALK_ISSUE/WALK_WAIT (PTE read through L1→L2→dmem) → ACCESS_ISSUE/ACCESS_WAIT (translated replay) → FAULT. Every data access costs ~1 cycle more than the old direct path; TLB hits skip the walk.
- **PTE-store flush rule:** a completed STORE whose *physical* address lands in `0xF0–0xFF` flushes all four TLB entries, so software PTE rewrites take effect on the next access.
- Invalid PTE: MMU latches `fault_va`, asserts `page_fault`, and stalls the CPU until reset. `cpu_top` exports `debug_page_fault`/`debug_fault_va`; Basys3 view `SW5:SW4=11` shows the fault VA on `LED[15:8]` and the fault flag on `LED[4]`.
- **Boot-image limitation:** `dmem.v` initializes `0xF0–0xFF` to an identity map (`0x80|n`) in an `initial` block — applied at FPGA configuration / simulation start, NOT restored by reset. A tapeout revision needs an explicit boot ROM or loader.
- VM regression: `iverilog -g2012 -o vm_sim sim/cpu_vm_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp vm_sim`
- Full design: `docs/superpowers/specs/2026-07-09-virtual-memory-design.md`.

---

## File Reference

| File | Description |
|---|---|
| `l1_cache.v` | Direct-mapped write-back L1 cache; `l2_pend` guards one outstanding L2 request per byte |
| `l1_cache_tb.v` | L1 testbench (cold miss, hit, write-back, eviction) |
| `l2_cache.v` | 4-way set-associative write-back L2 cache with LRU |
| `l2_cache_tb.v` | L2 testbench (cold miss, hit, write hit, LRU eviction) |
| `cache_hierarchy.v` | Wires L1 → L2 → memory, stall propagation via L1 |
| `cache_hierarchy_tb.v` | Hierarchy testbench (cold, L1 hit, L2 hit, full writeback chain, fill byte order) |
| `alu.v` | Combinational ALU: ADD, SUB, AND, OR, NOT with Z/C flags |
| `alu_tb.v` | ALU testbench (all 5 ops, overflow, zero, carry/borrow cases) |
| `reg_file.v` | 4×8-bit register file, 2 read ports, 1 write port |
| `reg_file_tb.v` | Register file testbench (reset, write/read, dual-port, wr_en guard, read-during-write) |
| `imem.v` | Instruction ROM: 256×16-bit, async read, loaded from `.mem` file via `$readmemh` |
| `imem_tb.v` | imem testbench (5 address read-back checks) |
| `test_imem.mem` | 5-instruction hex file used by imem testbench |
| `program.mem` | Placeholder program ROM (single HALT); replace with assembled program |
| `dmem.v` | Synchronous data RAM: 256×8-bit, 1-cycle read latency, ready handshake; boots identity PTE map at `0xF0–0xFF` |
| `dmem_tb.v` | dmem testbench (PTE boot image, write/read, multi-address, isolation, idle ready=0) |
| `control.v` | Combinational decoder: opcode → alu_op, wb_sel, reg_wr_en, mem_req/we, jump, branch, halt |
| `control_tb.v` | control testbench (all 12 opcodes, rd_addr/rs1_addr/imm slice checks) |
| `pc.v` | Program counter: increment, JMP, JZ (with zero_flag), stall hold, halt freeze |
| `pc_tb.v` | pc testbench (reset, increment, JMP, JZ taken/skipped, stall, halt) |
| `datapath.v` | Wires pc, imem, control, reg_file, alu; write-back mux; cache interface ports |
| `datapath_tb.v` | datapath testbench (MOV/ADD/STORE/LOAD/HALT program, 0-latency memory stub) |
| `test_datapath.mem` | 7-instruction test program: MOV×3, ADD, STORE, LOAD, HALT |
| `cpu_top.v` | Top-level: wires datapath → mmu → cache_hierarchy → dmem; exports fault debug outputs |
| `cpu_top_tb.v` | cpu_top testbench: real cache+dmem, 5 checks (halt, R0–R3, L1 dirty line) |
| `tlb.v` | 4-entry fully associative VPN→PPN TLB: combinational lookup, round-robin fill, synchronous flush |
| `tlb_tb.v` | TLB testbench (reset, fill/hit, round-robin eviction, flush) |
| `mmu.v` | MMU: TLB lookup, cache-mediated PTE walk, translated replay, PTE-store TLB flush, fault freeze |
| `mmu_tb.v` | MMU testbench with 2-cycle cache responder (walk+replay, hit, PTE-store flush, remap, fault) |
| `cpu_vm_tb.v` | Full-CPU VM regression: stale-TLB flush proof, remapped store/load, fault freeze |
| `vm_program.mem` | 14-instruction VM test program consumed by `cpu_vm_tb.v` |
| `dbg_cputop.v` | Debug harness for tracing `cpu_top` execution and cache request timing |
| `basys3_top.v` | Basys3 FPGA wrapper for `cpu_top`: 100 MHz clock divider, debounced reset, single-step mode, LEDs, and 4-digit seven-segment PC display |
| `assembler.cpp` | Two-pass C++ assembler for the ISA; supports labels, decimal/hex immediates, register operands, and `.mem` output padded to 256 words |
| `tests/run_assembler_tests.sh` | Assembler regression tests for encoding, labels, output padding, and error reporting |
| `tests/run_lvs_deck_tests.sh` | Structural regression for the project Sky130 LVS deck: pin-purpose connectivity, report output, split-cell normalization, constant-cell shorts, and tap-cell substrate restoration |
| `Makefile` | Builds all 15 Verilog simulations into `build/`; `make test` runs every testbench plus assembler and LVS-deck regressions |
| `docs/specs/2026-07-18-readme-redesign.md` | Approved portfolio-first README redesign: content order, real GDS and simulation-derived FPGA visuals, documentation cleanup, accuracy rules, and verification requirements |
| `docs/superpowers/specs/2026-07-09-virtual-memory-design.md` | Approved VM v1 design: TLB, cache-mediated page walk, PTE format, PTE-store flush, boot image, and tests |
| `docs/superpowers/plans/2026-07-09-virtual-memory.md` | TDD implementation sequence for VM v1, from TLB through CPU-level fault regression |
| `graphify-out/` | Git-ignored generated project knowledge graph: interactive HTML, audit report, GraphRAG JSON, extraction cache, and incremental-update metadata |
| `openroad/config.mk` | ORFS Sky130 HD configuration for hardening `cpu_top` as a core block; 15% initial utilization and 20% slew/cap repair margins; generated files go under `openroad/work/` |
| `openroad/constraint.sdc` | Initial ASIC timing constraints: 10 MHz core clock, async-reset false path, 5 ns output delay |
| `openroad/sky130hd_lvs.lylvs` | Project KLayout LVS deck: connects ORFS pin-purpose geometry, normalizes Sky130 split/constant cells, restores tap-cell substrate connectivity, and writes an LVS database |
| `openroad/README.md` | ORFS setup/run instructions, final GDS hash/metrics, stream-out fix, verification status, backup guidance, and tapeout limitations |

---

## ASIC/OpenROAD status

- Physical-design target: ORFS `sky130hd`, top module `cpu_top`, 10 MHz clock, 15% initial core utilization.
- Windows WSL 2.7.3, a dedicated Ubuntu 22.04 distribution, Docker 29.1.3, and the official `openroad/orfs:latest` image were installed on 2026-07-17.
- ORFS synthesis passes: 12,778 Sky130 HD cells, 178,941.619 um^2 cell area, including 3,824 sequential cells. All inferred memories map to standard cells.
- The first physical run at 35% initial utilization was congested. The final 15%/20%-repair-margin run completed RTL-to-GDS with about 19% final utilization, 90.29 ns setup slack at 10 MHz, and zero setup/hold/slew/cap, detailed-route DRC, antenna, and standalone KLayout DRC violations.
- Via-complete final GDS: `openroad/work/results/sky130hd/cpu8/base/6_final.gds`, 34,672,628 bytes, SHA-256 `EB8056AF757277F4828EB0E29479399363749B9FE188F15C5EBE53F8C93879CD`.
- Stream-out required correcting the generated `klayout.lyt` LEF path from `/workspace/...` to the actual Docker mount `/work/...`; the stale path omitted 138,398 default-via references. Always reject a merge log containing `Invalid via name` warnings.
- Project-deck KLayout 0.30.7 electrical LVS is clean against the via-complete final GDS: all 146 circuit pairs match with zero nonmatches. The deck connects ORFS datatype-16 pin geometry to routed metal/text, models the device-less `conb_1` and tap-cell connectivity, and normalizes four verified split-symmetric Sky130 cell variants. A direct GDS audit found all 82 labels on pin geometry; `halt` and `VSS` intentionally collapse to one electrical pin through `conb_1`, yielding 81 unique top-level electrical pins.
- Clean project-deck LVS is not foundry signoff. The selected shuttle/foundry must rerun its qualified decks before fabrication.
- This run hardens a core block only. `basys3_top.v` and `Basys3_CPU.xdc` are FPGA-only and are excluded.
- The active `program.mem` is consumed by `imem.v` during synthesis, making that program part of the resulting hardware implementation unless the instruction memory architecture is replaced.
- The `dmem.v` identity-PTE `initial` block is still a known tapeout blocker; add an explicit boot ROM/loader before fabrication.
- The inferred memories and cache arrays currently have no foundry SRAM macro mappings and may synthesize into standard cells.
- `openroad/work/` is Git-ignored and must be backed up separately to retain generated databases, reports, images, and GDS files.

---

## How to run any testbench
```bash
# Run the complete regression suite from the repository root:
make test

# Pattern: iverilog -g2012 -o <sim> sim/<tb>.v design/<dut>.v [dependencies] && vvp <sim>
# Full-CPU deps (used by top/programs/vm below):
#   design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v
#   design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v
#   design/control.v design/reg_file.v design/alu.v

iverilog -g2012 -o l1_sim   sim/l1_cache_tb.v design/l1_cache.v && vvp l1_sim
iverilog -g2012 -o l2_sim   sim/l2_cache_tb.v design/l2_cache.v && vvp l2_sim
iverilog -g2012 -o hier_sim sim/cache_hierarchy_tb.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v && vvp hier_sim
iverilog -g2012 -o alu_sim  sim/alu_tb.v design/alu.v && vvp alu_sim
iverilog -g2012 -o rf_sim   sim/reg_file_tb.v design/reg_file.v && vvp rf_sim
iverilog -g2012 -o imem_sim sim/imem_tb.v design/imem.v && vvp imem_sim
iverilog -g2012 -o dmem_sim sim/dmem_tb.v design/dmem.v && vvp dmem_sim
iverilog -g2012 -o ctrl_sim sim/control_tb.v design/control.v && vvp ctrl_sim
iverilog -g2012 -o pc_sim   sim/pc_tb.v design/pc.v && vvp pc_sim
iverilog -g2012 -o tlb_sim  sim/tlb_tb.v design/tlb.v && vvp tlb_sim
iverilog -g2012 -o mmu_sim  sim/mmu_tb.v design/mmu.v design/tlb.v && vvp mmu_sim
iverilog -g2012 -o dp_sim   sim/datapath_tb.v design/datapath.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp dp_sim
iverilog -g2012 -o top_sim  sim/cpu_top_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp top_sim
iverilog -g2012 -o programs_sim sim/cpu_programs_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp programs_sim
iverilog -g2012 -o vm_sim   sim/cpu_vm_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v && vvp vm_sim
bash tests/run_assembler_tests.sh
```
