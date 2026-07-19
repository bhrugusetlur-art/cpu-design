# Basys3 FPGA guide

The repository includes a synthesizable Basys3 wrapper with selectable clock
speeds, single-step execution, register and memory debug views, and a
four-digit program-counter display. The CPU is covered by simulation, and the
complete wrapper has an automated compile check. The animated board view below
is generated from a verified simulation trace, not camera footage from a
board.

## Animated simulation

Watch the hexadecimal PC, red LEDs, cycle count, and memory-status indicators
change as the verified program executes.

![Simulation-derived Basys3 display](images/fpga-demo.gif)

## What can be done on each computer

- macOS can edit the RTL, assemble programs, run the complete Icarus Verilog
  regression, and regenerate the simulation-derived visuals.
- Creating and loading a Basys3 bitstream requires AMD Vivado and a physical
  board. A Windows or supported Linux computer is the practical place to do
  that final step.

## Controls and displays

### Static control map

This diagram does not animate; it identifies the physical controls and debug
outputs used by the FPGA wrapper.

![Basys3 controls](images/fpga-controls.svg)

| Control | Function |
|---|---|
| `btnC` | Reset the CPU |
| `btnR` | Advance one CPU clock while single-step mode is selected |
| `SW1:SW0` | CPU clock: `00` = 1 Hz, `01` = 2 Hz, `10` = 4 Hz, `11` = single-step |
| `SW3:SW2` | Select R0, R1, R2, or R3 in register view |
| `SW5:SW4` | Select register, PC, memory/cache, or page-fault view |
| Seven-segment display | Shows the 8-bit PC in hexadecimal; the left digit shows `H` after HALT |

### LED debug views

| `SW5:SW4` | View | LED meaning |
|---|---|---|
| `00` | Register | `LED[7:0]` = selected register, `LED[8]` = halt, `LED[9]` = CPU clock |
| `01` | PC | `LED[7:0]` = PC, `LED[8]` = halt, `LED[9]` = CPU clock |
| `10` | Memory/cache | `LED[7:0]` = address, `LED[10]` = request, `LED[11]` = write, `LED[12]` = stall |
| `11` | Page fault | `LED[15:8]` = faulting virtual address, `LED[4]` = fault, `LED[3]` = zero, `LED[2]` = stall, `LED[0]` = halt |

## Demo programs

`program.mem` is the program embedded by `basys3_top.v`. Replace it before
building the bitstream when you want a different demonstration:

```bash
cp programs/cache_store_load.mem program.mem
```

| Program | Demonstrates | Expected final state |
|---|---|---|
| `programs/cache_store_load.mem` | ADD, a cold STORE miss, LOAD, and write-back cache state | PC `06`; R0 `0D`, R1 `03`, R2 `0D`, R3 `0D` |
| `programs/alu_ops.mem` | Arithmetic and logic operations | PC `07`; R0 `0C`, R1 `03`, R2 `03`, R3 `FF` |
| `programs/branch_jz.mem` | `JZ` taken and not taken | PC `0E`; R0 `02`, R1 `03`, R2 `02`, R3 `04` |
| `sim/vm_program.mem` | Page walk, TLB flush after a PTE rewrite, remapping, and deliberate fault | Fault at PC `0D`, VA `40`; R3 remains `5A` |

The active `program.mem` contains the virtual-memory demo. Its last access is
intentionally invalid, so the CPU freezes in the fault state instead of
reaching HALT. The page table is initialized when the FPGA is configured, not
when reset is pressed; the program rewrites the PTEs it changes on every run.

## Vivado bitstream workflow

1. Create an RTL project for the Basys3 part `xc7a35tcpg236-1`.
2. Add every Verilog file under `design/`, add `program.mem` as a memory
   initialization file, and add `design/Basys3_CPU.xdc` as the constraints
   file.
3. Set `basys3_top` as the synthesis top.
4. Run synthesis, implementation, and Generate Bitstream.
5. Connect the board, open Hardware Manager, program the device, then start at
   1 Hz or single-step mode so the state changes are easy to inspect.

If the program file changes after a previous build, reset the synthesis and
implementation runs before generating a new bitstream so the new ROM contents
are included.

The matching simulation commands and expected regression coverage are in
[Testing](testing.md).
