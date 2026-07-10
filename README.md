# 8-bit CPU with Caches and Virtual Memory

An 8-bit CPU built from scratch in Verilog, running on a Digilent Basys3 FPGA.
It executes a 12-instruction ISA through a two-level write-back cache
hierarchy, and every data access is translated through a TLB + MMU with
software-writable page tables — small enough to read in an afternoon,
complete enough to page-fault. Every module was built test-first in
simulation (Icarus Verilog), then verified on the board. Long-term goal:
tape out a physical chip.

## The Design

| Property | Value |
|---|---|
| Data width | 8-bit |
| Instructions | 16-bit wide; 12-instruction ISA (MOV, ADD, SUB, AND, OR, NOT, LOAD, STORE, JMP, JZ, HALT) |
| Registers | R0–R3, PC, zero + carry flags |
| Memory model | Harvard: 256×16 instruction ROM, 256×8 data RAM |
| L1 cache | 8 lines, direct-mapped, 4-byte blocks, write-back |
| L2 cache | 8 sets × 4 ways, LRU, 4-byte blocks, write-back |
| Virtual memory | 16-byte pages, 4-entry TLB, hardware page-table walker, page faults |

**Execution path.** The datapath fetches, decodes, and executes one
instruction at a time. LOAD/STORE addresses are *virtual*: they flow through
the MMU, which looks up a 4-entry TLB and, on a miss, walks the page table
through the caches (L1 → L2 → data RAM) before replaying the access at the
physical address. Instruction fetch stays physical (Harvard).

**Virtual memory.** `VA[7:4]` selects one of 16 pages, `VA[3:0]` the byte
within it. The page table lives at physical `0xF0–0xFF`, one byte per page:
bit 7 = valid, bits 3:0 = physical page number. Page tables are ordinary
memory — a STORE into `0xF0–0xFF` flushes the TLB, so software remaps take
effect on the very next access. Touching a page with an invalid PTE latches
the faulting address, raises `page_fault`, and freezes the CPU until reset.
At FPGA configuration the table boots as an identity map, so programs that
ignore virtual memory run unchanged.

## What Was Built

| Group | Files |
|---|---|
| CPU core | `pc.v`, `imem.v`, `control.v`, `reg_file.v`, `alu.v`, `datapath.v` |
| Memory system | `l1_cache.v`, `l2_cache.v`, `cache_hierarchy.v`, `dmem.v` |
| Virtual memory | `tlb.v`, `mmu.v` |
| Integration | `cpu_top.v` (CPU + MMU + caches + RAM), `basys3_top.v` (board wrapper: clocking, debounce, single-step, LED/7-seg debug) |
| Tooling | `assembler.cpp` — two-pass assembler producing `.mem` images |

Repository layout:

- `design/`: synthesizable Verilog and the Basys3 XDC constraints file
- `sim/`: one testbench per module plus full-CPU regressions and their memory files
- `programs/`: named demo programs that can be copied into `program.mem`
- `tests/`: assembler test script
- `program.mem`: the active FPGA instruction image used by `basys3_top.v`

## How It Was Tested

Development was test-first: each module got a failing testbench, then the
implementation, from the ALU all the way up to full-CPU regressions — 16
suites in total, all passing. The two most interesting ones:

- `sim/cpu_programs_tb.v` runs the three demo programs on the real
  CPU + caches and checks final PC/register values.
- `sim/cpu_vm_tb.v` proves virtual memory end-to-end: it preloads a TLB
  entry, rewrites the PTE (which must flush the stale entry), stores and
  loads through the remapped page, then deliberately page-faults and checks
  the CPU froze with the right fault address.

Icarus Verilog pattern (full per-module command list in `AGENTS.md`):

```bash
iverilog -g2012 -o vm_sim sim/cpu_vm_tb.v design/cpu_top.v design/mmu.v design/tlb.v \
  design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v \
  design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v \
  design/alu.v && vvp vm_sim
```

Vivado simulator flow (Windows):

```text
xvlog -sv sim/cpu_programs_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v
xelab -debug typical cpu_programs_tb -s cpu_programs_sim
xsim cpu_programs_sim -runall
```

(Substitute `sim/cpu_vm_tb.v` and `cpu_vm_tb` to run the virtual memory
regression the same way.)

## Verification Status

Everything below passes in simulation **and** has been verified on the
Basys3 board:

| Area | Hardware-verified |
|---|---|
| All 12 ISA instructions (incl. JZ taken/not taken) | ✅ |
| Cache miss stall behavior | ✅ |
| Register / PC / memory-request debug views | ✅ |
| **Virtual memory: TLB remap, PTE-store flush, page-fault freeze + fault view** | ✅ |

## Running It on the Board

### Controls

- `btnC`: reset
- `btnR`: single-step pulse when `SW1:SW0 = 11`
- `SW1:SW0`: CPU clock — `00` 1 Hz, `01` 2 Hz, `10` 4 Hz, `11` single-step
- `SW3:SW2`: register select (register view only)
- `SW5:SW4`: LED debug view (below)

### LED views

| `SW5:SW4` | View | LEDs |
|---|---|---|
| `00` | Register | `LED[7:0]` = register picked by `SW3:SW2`, `LED[8]` halt, `LED[9]` heartbeat |
| `01` | PC | `LED[7:0]` = PC, `LED[8]` halt, `LED[9]` heartbeat |
| `10` | Memory/cache | `LED[7:0]` = data address, `LED[10]` request, `LED[11]` write, `LED[12]` stall, `LED[8]` halt, `LED[9]` heartbeat |
| `11` | Page fault | `LED[15:8]` = faulting VA, `LED[4]` page fault, `LED[3]` zero flag, `LED[2]` stall, `LED[1]` heartbeat, `LED[0]` halt |

Read `LED[7:0]` as binary, e.g. `0D = 0000 1101` → LED3, LED2, LED0 on.

### Demo programs

The active program is `program.mem` (currently the virtual memory demo). To
switch demos, copy one of the files below into `program.mem` and rebuild the
bitstream (reset the synthesis/implementation runs if Vivado doesn't pick up
the change).

#### Cache/store/load — `programs/cache_store_load.mem`

```text
100A
1403
2100
0800
8800
7E00
F000
```

- 7-segment PC shows `00 → 01 → 02 → 03 → 04`, pauses at `04` for the STORE
  cold miss, then halts at `H06`.
- Final registers: R0 = `0D`, R1 = `03`, R2 = `0D`, R3 = `0D`.

#### ALU operations — `programs/alu_ops.mem`

```text
100F
1403
3100
0800
4900
5900
6C00
F000
```

- Final registers: R0 = `0C`, R1 = `03`, R2 = `03`, R3 = `FF`.

#### Branch and saved zero flag — `programs/branch_jz.mem`

```text
1001
1401
3100
A006
18EE
900E
1802
1005
1403
3100
A00D
1C04
900E
1CEE
F000
```

- Exercises `JZ` taken and not taken using the saved zero flag; halts around `H0E`.
- Final registers: R0 = `02`, R1 = `03`, R2 = `02`, R3 = `04`.

#### Virtual memory remap and page fault — `sim/vm_program.mem`

```text
1821
1c11
8b00
1083
14f2
8400
1c5a
8b00
7200
1000
14f4
8400
1840
7e00
```

The program stores through VA `0x21` under the boot identity map, rewrites
PTE[2] so VPN 2 maps to physical page 3 (the PTE store flushes the TLB),
stores/loads through the remapped VA `0x21` → PA `0x31`, invalidates PTE[4],
and finally loads from VA `0x40` — which page-faults on purpose.

Expected behavior (hardware-verified):

- The PC display pauses at each LOAD/STORE for the page walk, then freezes
  at `0D` forever (no `H` — the CPU is faulted, not halted). Reset restarts it.
- In fault view (`SW5:SW4 = 11`): `LED[15:8] = 0100 0000` (the faulting
  VA `0x40`, LED14 on) and `LED[4]` on (page fault).
- Final registers: R0 = `00`, R1 = `F4`, R2 = `40`, R3 = `5A`
  (R3 proves the faulting LOAD never wrote back).

Note: PTE writes survive reset (the page table is initialized at FPGA
configuration, not reset), so this demo rewrites its own PTEs at startup and
behaves the same on every run.
