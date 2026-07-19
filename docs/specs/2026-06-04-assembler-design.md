# Assembler Design — 8-bit CPU ISA

**Date:** 2026-06-04
**Language:** C++17
**File:** `assembler.cpp`

---

## Goal

Translate human-readable assembly source into a `.mem` file (256 × 4-hex-digit words) that Icarus Verilog's `$readmemh` can load into `imem`.

---

## Architecture

Single file, three logical components executed in sequence:

1. **Lexer** — strips `;` comments, splits each non-blank line into tokens (mnemonic + operands)
2. **Pass 1** — walks tokenised lines, increments a PC counter per instruction, records every `label:` → address in a `std::map<std::string, uint8_t>`
3. **Pass 2** — re-walks tokenised lines, encodes each instruction to a `uint16_t` using the symbol table, writes the result to the output file

---

## CLI

```
./assembler input.asm output.mem
```

- Missing or extra arguments → usage message + exit 1
- Build: `g++ -std=c++17 -o assembler assembler.cpp`

---

## Input Syntax

```asm
; full-line comment
    MOV  R0, #42        ; inline comment
    MOV  R1, #8
    STORE R0, [R1]
loop:
    LOAD  R2, [R1]
    JZ    done
    JMP   loop
done:
    HALT
```

Rules:
- **Comments:** `;` to end of line, stripped before parsing
- **Labels:** `identifier:` — may appear alone on a line or immediately before an instruction on the same line; label names are case-sensitive
- **Registers:** `R0`–`R3`, case-insensitive
- **Immediates:** decimal (`42`) or hex (`0x2A` / `0x2a`), range 0–255
- **Memory operands:** `[Rs]` for LOAD and STORE
- **Jump operands:** label name or bare address (decimal or hex)
- **Mnemonics:** case-insensitive
- **Blank lines:** ignored

---

## Instruction Encoding

16-bit word: `[15:12] opcode | [11:10] Rd | [9:8] Rs | [7:0] imm/addr`

| Mnemonic | Opcode | Rd | Rs | imm/addr |
|---|---|---|---|---|
| `MOV Rd, Rs` | `0000` | Rd | Rs | `0x00` |
| `MOV Rd, #imm` | `0001` | Rd | `00` | imm |
| `ADD Rd, Rs` | `0010` | Rd | Rs | `0x00` |
| `SUB Rd, Rs` | `0011` | Rd | Rs | `0x00` |
| `AND Rd, Rs` | `0100` | Rd | Rs | `0x00` |
| `OR Rd, Rs` | `0101` | Rd | Rs | `0x00` |
| `NOT Rd` | `0110` | Rd | `00` | `0x00` |
| `LOAD Rd, [Rs]` | `0111` | Rd | Rs | `0x00` |
| `STORE Rs, [Rd]` | `1000` | Rd | Rs | `0x00` |
| `JMP addr/label` | `1001` | `00` | `00` | addr |
| `JZ addr/label` | `1010` | `00` | `00` | addr |
| `HALT` | `1111` | `00` | `00` | `0x00` |

Register encoding: R0=`00`, R1=`01`, R2=`10`, R3=`11`

---

## Output Format

256 lines, one 4-digit lowercase hex word per line. Instructions fill addresses 0–N; remaining addresses are padded with `0000` (encodes as a no-op / safe default).

```
002a
1408
8400
7900
f000
0000
...
```

---

## Error Handling

Errors print to stderr with line number, assembler exits 1. Multiple errors may be reported before exiting (collect all, then exit).

```
error line 3: undefined label 'looop'
error line 7: immediate 300 out of range (0-255)
error line 9: unknown register 'R5'
error line 12: unknown mnemonic 'MOVI'
error line 15: program exceeds 256 instructions
```

---

## File Layout

```
assembler.cpp     — single translation unit, no external dependencies
```

Internal structure (top to bottom):
- Constants / opcode map (`std::map<std::string, uint8_t>`)
- `parseLine()` — tokenise one source line, strip comments, extract label if present
- `parseReg()` — parse `R0`–`R3`, return 0–3 or report error
- `parseImm()` — parse decimal/hex immediate, range-check
- `pass1()` — build symbol table
- `pass2()` — encode and write output
- `main()` — open files, call pass1 then pass2, report errors
