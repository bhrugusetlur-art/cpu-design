# CPU Design on Basys3

A small Verilog CPU project targeted at the Digilent Basys3 FPGA. The board top is `basys3_top.v`, which wraps `cpu_top.v` and shows CPU state on LEDs and the 7-segment display.

## Basys3 Controls

- `btnC`: reset
- `btnR`: single-step pulse when `SW1:SW0 = 11`
- `SW1:SW0`: CPU clock mode
  - `00`: 1 Hz
  - `01`: 2 Hz
  - `10`: 4 Hz
  - `11`: single-step with `btnR`
- `SW3:SW2`: register select when `SW5:SW4 = 00`
  - `00`: R0
  - `01`: R1
  - `10`: R2
  - `11`: R3
- `SW5:SW4`: LED debug view
  - `00`: register view
  - `01`: PC view
  - `10`: memory/cache request view
  - `11`: instruction/flags view

## LED Output

In register view (`SW5:SW4 = 00`):

- `LED[7:0]`: selected register value
- `LED[8]`: halt
- `LED[9]`: CPU clock heartbeat

In PC view (`SW5:SW4 = 01`):

- `LED[7:0]`: `pc_out`
- `LED[8]`: halt
- `LED[9]`: CPU clock heartbeat

In memory/cache request view (`SW5:SW4 = 10`):

- `LED[7:0]`: current CPU data-memory address
- `LED[8]`: halt
- `LED[9]`: CPU clock heartbeat
- `LED[10]`: cache request
- `LED[11]`: memory write enable
- `LED[12]`: memory stall

In instruction/flags view (`SW5:SW4 = 11`):

- `LED[15:8]`: current instruction high byte
- `LED[3]`: saved zero flag
- `LED[2]`: memory stall
- `LED[1]`: CPU clock heartbeat
- `LED[0]`: halt

Read `LED[7:0]` as binary. For example:

```text
0D = 0000 1101 -> LED3, LED2, and LED0 on
03 = 0000 0011 -> LED1 and LED0 on
FF = 1111 1111 -> LED7 through LED0 on
```

## FPGA Demo Programs

The active FPGA program is `program.mem`. To run another demo, copy one of the files from `programs/` into `program.mem`, then regenerate the bitstream. If Vivado does not pick up the changed memory contents, reset the synthesis/implementation runs and rebuild.

### Default: cache/store/load demo

File: `programs/cache_store_load.mem`

```text
100A
1403
2100
0800
8800
7E00
F000
```

Expected behavior:

- 7-segment PC sequence shows `00 -> 01 -> 02 -> 03 -> 04`, pauses at `04` for the STORE cold cache miss, then reaches `H06`.
- Final register values:
  - `SW3:SW2 = 00`: R0 = `0D`
  - `SW3:SW2 = 01`: R1 = `03`
  - `SW3:SW2 = 10`: R2 = `0D`
  - `SW3:SW2 = 11`: R3 = `0D`

### ALU operations demo

File: `programs/alu_ops.mem`

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

Expected final register values:

- `SW3:SW2 = 00`: R0 = `0C`
- `SW3:SW2 = 01`: R1 = `03`
- `SW3:SW2 = 10`: R2 = `03`
- `SW3:SW2 = 11`: R3 = `FF`

### Branch and saved-zero-flag demo

File: `programs/branch_jz.mem`

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

This verifies both `JZ` taken and `JZ` not taken using the saved zero flag from the previous ALU instruction.

Expected final register values:

- `SW3:SW2 = 00`: R0 = `02`
- `SW3:SW2 = 01`: R1 = `03`
- `SW3:SW2 = 10`: R2 = `02`
- `SW3:SW2 = 11`: R3 = `04`

Expected halt display: around `H0E`.

## Hardware-Verified Features

These features have been checked on the Basys3 FPGA:

- MOV immediate
- MOV register
- ADD
- SUB
- AND
- OR
- NOT
- LOAD
- STORE
- HALT
- JMP
- JZ taken
- JZ not taken
- cache miss stall behavior
- register debug LEDs
