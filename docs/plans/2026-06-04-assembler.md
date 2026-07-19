# Assembler Implementation Plan

**Goal:** Build a two-pass C++ assembler that translates 8-bit CPU assembly source into a `$readmemh`-compatible `.mem` file.

**Architecture:** Single translation unit (`assembler.cpp`). Pass 1 walks all lines to build a label→address symbol table. Pass 2 encodes each instruction to a 16-bit word and writes 256 padded hex lines. A `Line` struct carries the parsed tokens between passes.

**Tech Stack:** C++17, STL only (`<map>`, `<vector>`, `<sstream>`, `<fstream>`). Build with `g++ -std=c++17`.

---

## File map

| File | Action | Purpose |
|---|---|---|
| `assembler.cpp` | Create | All assembler logic — helpers, lexer, pass1, pass2, main |
| `tests/test_basic.asm` | Create | MOV/ALU/HALT-only test program |
| `tests/test_basic_golden.mem` | Create | Expected output for test_basic.asm |
| `tests/test_memory.asm` | Create | LOAD/STORE test program |
| `tests/test_memory_golden.mem` | Create | Expected output for test_memory.asm |
| `tests/test_labels.asm` | Create | JMP/JZ with forward and backward labels |
| `tests/test_labels_golden.mem` | Create | Expected output for test_labels.asm |
| `tests/test_datapath.asm` | Create | Full program matching existing test_datapath.mem |
| `tests/run_tests.sh` | Create | Runs all integration tests, prints PASS/FAIL |
| `README.md` | Modify | Mark the C++ assembler complete and add its run command |

---

## Task 1: Skeleton + helpers

**Files:**
- Create: `assembler.cpp`

- [ ] **Step 1: Write the failing test**

  Create `tests/test_basic.asm`:
  ```asm
  ; simple ALU program
      MOV  R0, #10
      MOV  R1, #3
      ADD  R0, R1
      HALT
  ```

  Create `tests/test_basic_golden.mem` (256 lines — first 4 instructions, rest zeros):
  ```
  100a
  1403
  2100
  f000
  0000
  ```
  *(251 more `0000` lines — easiest to generate: `python3 -c "print('0000\n'*251, end='')" >> tests/test_basic_golden.mem`)*

  Verify the test infrastructure will fail before assembler exists:
  ```bash
  mkdir -p tests
  # create the files above
  g++ -std=c++17 -o assembler assembler.cpp
  ```
  Expected: **compile error** — `assembler.cpp` does not exist yet.

- [ ] **Step 2: Create the skeleton**

  Create `assembler.cpp`:
  ```cpp
  #include <iostream>
  #include <fstream>
  #include <sstream>
  #include <string>
  #include <map>
  #include <vector>
  #include <algorithm>
  #include <cstdint>
  #include <cctype>
  #include <stdexcept>

  // -------------------------------------------------------
  // Helpers
  // -------------------------------------------------------

  static std::string toUpper(std::string s) {
      std::transform(s.begin(), s.end(), s.begin(), ::toupper);
      return s;
  }

  static std::string trim(const std::string& s) {
      size_t a = s.find_first_not_of(" \t\r\n");
      if (a == std::string::npos) return "";
      size_t b = s.find_last_not_of(" \t\r\n");
      return s.substr(a, b - a + 1);
  }

  // Parse "R0"–"R3" → 0–3; push error and return -1 on failure
  static int parseReg(const std::string& tok, int lineno,
                      std::vector<std::string>& errors) {
      std::string up = toUpper(trim(tok));
      if (up == "R0") return 0;
      if (up == "R1") return 1;
      if (up == "R2") return 2;
      if (up == "R3") return 3;
      errors.push_back("error line " + std::to_string(lineno) +
                       ": unknown register '" + trim(tok) + "'");
      return -1;
  }

  // Parse decimal or 0x-hex immediate, range 0–255
  static int parseImm(const std::string& tok, int lineno,
                      std::vector<std::string>& errors) {
      std::string t = trim(tok);
      if (!t.empty() && t[0] == '#') t = t.substr(1);
      try {
          size_t pos;
          long val;
          if (t.size() > 2 && t[0] == '0' && (t[1] == 'x' || t[1] == 'X'))
              val = std::stol(t, &pos, 16);
          else
              val = std::stol(t, &pos, 10);
          if (pos != t.size()) throw std::invalid_argument("");
          if (val < 0 || val > 255) {
              errors.push_back("error line " + std::to_string(lineno) +
                               ": immediate " + trim(tok) + " out of range (0-255)");
              return -1;
          }
          return (int)val;
      } catch (...) {
          errors.push_back("error line " + std::to_string(lineno) +
                           ": invalid immediate '" + trim(tok) + "'");
          return -1;
      }
  }

  // Strip [ ] brackets and return the inner string
  static std::string stripBrackets(std::string s) {
      s = trim(s);
      if (!s.empty() && s.front() == '[') s = s.substr(1);
      if (!s.empty() && s.back()  == ']') s.pop_back();
      return trim(s);
  }

  int main(int argc, char* argv[]) {
      if (argc != 3) {
          std::cerr << "usage: assembler input.asm output.mem\n";
          return 1;
      }
      std::cerr << "not yet implemented\n";
      return 1;
  }
  ```

- [ ] **Step 3: Compile**
  ```bash
  g++ -std=c++17 -o assembler assembler.cpp
  ```
  Expected: **compiles with no errors**.

- [ ] **Step 4: Commit**
  ```bash
  git add assembler.cpp
  git commit -m "feat: assembler skeleton with helpers (parseReg, parseImm)"
  ```

---

## Task 2: Lexer

**Files:**
- Modify: `assembler.cpp` — add `Line` struct, `splitOperands`, `parseLine`, `lex`

- [ ] **Step 1: Write the failing test**

  ```bash
  ./assembler tests/test_basic.asm /tmp/out.mem
  ```
  Expected output: `not yet implemented` (because lexer is not wired up yet — current skeleton exits with that message).

- [ ] **Step 2: Add the Line struct and lexer functions**

  Insert after the `stripBrackets` function, before `main`:

  ```cpp
  // -------------------------------------------------------
  // Data types
  // -------------------------------------------------------

  struct Line {
      int lineno = 0;
      std::string label;      // empty if no label on this line
      std::string mnemonic;   // empty for blank/comment-only lines
      std::vector<std::string> operands;
  };

  using SymTable = std::map<std::string, uint8_t>;

  // -------------------------------------------------------
  // Lexer
  // -------------------------------------------------------

  static std::vector<std::string> splitOperands(const std::string& s) {
      std::vector<std::string> result;
      std::stringstream ss(s);
      std::string tok;
      while (std::getline(ss, tok, ','))
          result.push_back(trim(tok));
      return result;
  }

  // Parse one raw source line into a Line struct.
  // Strips ; comments, extracts label (if any), tokenises mnemonic + operands.
  static Line parseLine(const std::string& raw, int lineno) {
      Line line;
      line.lineno = lineno;

      // Strip comment
      std::string s = raw;
      size_t semi = s.find(';');
      if (semi != std::string::npos) s = s.substr(0, semi);
      s = trim(s);
      if (s.empty()) return line;

      // Extract label: anything before the first ':'
      size_t colon = s.find(':');
      if (colon != std::string::npos) {
          line.label = trim(s.substr(0, colon));
          s = trim(s.substr(colon + 1));
          if (s.empty()) return line;
      }

      // First whitespace-delimited token is the mnemonic
      size_t space = s.find_first_of(" \t");
      if (space == std::string::npos) {
          line.mnemonic = toUpper(s);
          return line;
      }
      line.mnemonic = toUpper(s.substr(0, space));
      std::string rest = trim(s.substr(space));
      if (!rest.empty())
          line.operands = splitOperands(rest);
      return line;
  }

  static std::vector<Line> lex(std::istream& in) {
      std::vector<Line> lines;
      std::string raw;
      int lineno = 0;
      while (std::getline(in, raw))
          lines.push_back(parseLine(raw, ++lineno));
      return lines;
  }
  ```

- [ ] **Step 3: Compile**
  ```bash
  g++ -std=c++17 -o assembler assembler.cpp
  ```
  Expected: compiles cleanly.

- [ ] **Step 4: Commit**
  ```bash
  git add assembler.cpp
  git commit -m "feat: assembler lexer (parseLine, lex)"
  ```

---

## Task 3: Pass 1 — symbol table

**Files:**
- Modify: `assembler.cpp` — add `pass1`

- [ ] **Step 1: Write the failing test**

  Create `tests/test_labels.asm`:
  ```asm
      MOV  R0, #5     ; addr 0
  loop:
      NOT  R0         ; addr 1
      JZ   done       ; addr 2
      JMP  loop       ; addr 3
  done:
      HALT            ; addr 4
  ```

  Create `tests/test_labels_golden.mem` (256 lines):
  ```
  1005
  6000
  a004
  9001
  f000
  ```
  *(251 more `0000` lines)*

  Running the assembler now should still exit with "not yet implemented":
  ```bash
  ./assembler tests/test_labels.asm /tmp/out.mem && echo SHOULD_NOT_REACH
  ```
  Expected: exits 1 with `not yet implemented`.

- [ ] **Step 2: Add pass1**

  Insert after the `lex` function, before `main`:

  ```cpp
  // -------------------------------------------------------
  // Pass 1: build symbol table
  // -------------------------------------------------------

  static SymTable pass1(const std::vector<Line>& lines,
                        std::vector<std::string>& errors) {
      SymTable sym;
      uint8_t pc = 0;
      for (const auto& l : lines) {
          if (!l.label.empty()) {
              if (sym.count(l.label))
                  errors.push_back("error line " + std::to_string(l.lineno) +
                                   ": duplicate label '" + l.label + "'");
              else
                  sym[l.label] = pc;
          }
          if (!l.mnemonic.empty()) ++pc;
      }
      return sym;
  }
  ```

- [ ] **Step 3: Compile**
  ```bash
  g++ -std=c++17 -o assembler assembler.cpp
  ```
  Expected: compiles cleanly.

- [ ] **Step 4: Commit**
  ```bash
  git add assembler.cpp
  git commit -m "feat: assembler pass1 symbol table"
  ```

---

## Task 4: Pass 2 — encode instructions + output

**Files:**
- Modify: `assembler.cpp` — add `encode`, `pass2`, `writeMemFile`; wire up `main`

- [ ] **Step 1: Write the failing test**

  The test_basic.asm test from Task 1 should still fail:
  ```bash
  ./assembler tests/test_basic.asm /tmp/out.mem
  ```
  Expected: exits 1 with `not yet implemented`.

- [ ] **Step 2: Add encode, pass2, writeMemFile**

  Insert after `pass1`, before `main`:

  ```cpp
  // -------------------------------------------------------
  // Pass 2: encode instructions
  // -------------------------------------------------------

  static uint16_t encode(const Line& l, const SymTable& sym,
                         std::vector<std::string>& errors) {
      const std::string& mn  = l.mnemonic;
      const auto&        ops = l.operands;
      int lineno = l.lineno;

      // Helpers that parse from the operand list with bounds checking
      auto reg = [&](int idx) -> int {
          if (idx >= (int)ops.size()) {
              errors.push_back("error line " + std::to_string(lineno) + ": missing operand");
              return 0;
          }
          int v = parseReg(ops[idx], lineno, errors);
          return v < 0 ? 0 : v;
      };

      auto imm = [&](int idx) -> int {
          if (idx >= (int)ops.size()) {
              errors.push_back("error line " + std::to_string(lineno) + ": missing operand");
              return 0;
          }
          int v = parseImm(ops[idx], lineno, errors);
          return v < 0 ? 0 : v;
      };

      // Parse address operand: label name or numeric immediate
      auto addr = [&](int idx) -> int {
          if (idx >= (int)ops.size()) {
              errors.push_back("error line " + std::to_string(lineno) + ": missing operand");
              return 0;
          }
          std::string t = trim(ops[idx]);
          // Numeric if it starts with a digit or '0x'
          bool isNum = !t.empty() &&
                       (std::isdigit((unsigned char)t[0]) ||
                        (t.size() > 2 && t[0] == '0' && (t[1] == 'x' || t[1] == 'X')));
          if (isNum) {
              int v = parseImm(t, lineno, errors);
              return v < 0 ? 0 : v;
          }
          auto it = sym.find(t);
          if (it == sym.end()) {
              errors.push_back("error line " + std::to_string(lineno) +
                               ": undefined label '" + t + "'");
              return 0;
          }
          return it->second;
      };

      auto regBracketed = [&](int idx) -> int {
          if (idx >= (int)ops.size()) {
              errors.push_back("error line " + std::to_string(lineno) + ": missing operand");
              return 0;
          }
          int v = parseReg(stripBrackets(ops[idx]), lineno, errors);
          return v < 0 ? 0 : v;
      };

      uint16_t w = 0;

      if (mn == "MOV") {
          int rd = reg(0);
          if (ops.size() >= 2 && !trim(ops[1]).empty() && trim(ops[1])[0] == '#') {
              // MOV Rd, #imm — opcode 0001
              w = (uint16_t)((0x1 << 12) | (rd << 10) | (imm(1) & 0xFF));
          } else {
              // MOV Rd, Rs — opcode 0000
              w = (uint16_t)((0x0 << 12) | (rd << 10) | (reg(1) << 8));
          }
      } else if (mn == "ADD" || mn == "SUB" || mn == "AND" || mn == "OR") {
          static const std::map<std::string, uint8_t> aluOp = {
              {"ADD", 0x2}, {"SUB", 0x3}, {"AND", 0x4}, {"OR", 0x5}
          };
          w = (uint16_t)((aluOp.at(mn) << 12) | (reg(0) << 10) | (reg(1) << 8));
      } else if (mn == "NOT") {
          w = (uint16_t)((0x6 << 12) | (reg(0) << 10));
      } else if (mn == "LOAD") {
          // LOAD Rd, [Rs]
          w = (uint16_t)((0x7 << 12) | (reg(0) << 10) | (regBracketed(1) << 8));
      } else if (mn == "STORE") {
          // STORE Rs, [Rd]  — note: Rd is address (bits[11:10]), Rs is data (bits[9:8])
          w = (uint16_t)((0x8 << 12) | (regBracketed(1) << 10) | (reg(0) << 8));
      } else if (mn == "JMP") {
          w = (uint16_t)((0x9 << 12) | (addr(0) & 0xFF));
      } else if (mn == "JZ") {
          w = (uint16_t)((0xA << 12) | (addr(0) & 0xFF));
      } else if (mn == "HALT") {
          w = (uint16_t)(0xF << 12);
      } else {
          errors.push_back("error line " + std::to_string(lineno) +
                           ": unknown mnemonic '" + mn + "'");
      }
      return w;
  }

  static std::vector<uint16_t> pass2(const std::vector<Line>& lines,
                                     const SymTable& sym,
                                     std::vector<std::string>& errors) {
      std::vector<uint16_t> words;
      for (const auto& l : lines) {
          if (l.mnemonic.empty()) continue;
          words.push_back(encode(l, sym, errors));
      }
      while (words.size() < 256) words.push_back(0x0000);
      return words;
  }

  static void writeMemFile(const std::vector<uint16_t>& words, std::ostream& out) {
      char buf[5];
      for (uint16_t w : words) {
          snprintf(buf, sizeof(buf), "%04x", w);
          out << buf << "\n";
      }
  }
  ```

- [ ] **Step 3: Wire up main**

  Replace the current `main` with:

  ```cpp
  int main(int argc, char* argv[]) {
      if (argc != 3) {
          std::cerr << "usage: assembler input.asm output.mem\n";
          return 1;
      }
      std::ifstream in(argv[1]);
      if (!in) {
          std::cerr << "error: cannot open '" << argv[1] << "'\n";
          return 1;
      }
      std::vector<std::string> errors;
      auto lines = lex(in);
      auto sym   = pass1(lines, errors);
      auto words = pass2(lines, sym, errors);
      if (!errors.empty()) {
          for (const auto& e : errors) std::cerr << e << "\n";
          return 1;
      }
      std::ofstream out(argv[2]);
      if (!out) {
          std::cerr << "error: cannot open '" << argv[2] << "'\n";
          return 1;
      }
      writeMemFile(words, out);
      return 0;
  }
  ```

- [ ] **Step 4: Compile**
  ```bash
  g++ -std=c++17 -o assembler assembler.cpp
  ```
  Expected: compiles cleanly.

- [ ] **Step 5: Run the basic test**
  ```bash
  ./assembler tests/test_basic.asm /tmp/out.mem && diff /tmp/out.mem tests/test_basic_golden.mem
  ```
  Expected: **no diff output** (files match).

- [ ] **Step 6: Run the labels test**
  ```bash
  ./assembler tests/test_labels.asm /tmp/out.mem && diff /tmp/out.mem tests/test_labels_golden.mem
  ```
  Expected: **no diff output**.

- [ ] **Step 7: Commit**
  ```bash
  git add assembler.cpp
  git commit -m "feat: assembler pass2 encode + output"
  ```

---

## Task 5: LOAD/STORE + memory test

**Files:**
- Create: `tests/test_memory.asm`, `tests/test_memory_golden.mem`

> Note: LOAD/STORE encoding is already implemented in Task 4's `encode`. This task adds the dedicated test.

- [ ] **Step 1: Create test_memory.asm**
  ```asm
  ; STORE R0 at address held in R1, then LOAD it back into R2
      MOV   R0, #0x0D    ; addr 0 — R0 = 13
      MOV   R1, #0x0D    ; addr 1 — R1 = 13 (address)
      STORE R0, [R1]     ; addr 2 — mem[13] = 13
      LOAD  R2, [R1]     ; addr 3 — R2 = mem[13]
      HALT               ; addr 4
  ```

- [ ] **Step 2: Compute and create test_memory_golden.mem**

  Encodings:
  - `MOV R0, #0x0D` = opcode 0001, Rd=R0=00, imm=0x0D → `0x100D`
  - `MOV R1, #0x0D` = opcode 0001, Rd=R1=01, imm=0x0D → `0x140D`
  - `STORE R0, [R1]` = opcode 1000, Rd=R1=01 (addr), Rs=R0=00 (data) → `0x8400`
  - `LOAD R2, [R1]`  = opcode 0111, Rd=R2=10, Rs=R1=01 → `0x7900`
  - `HALT` → `0xF000`

  Create `tests/test_memory_golden.mem`:
  ```
  100d
  140d
  8400
  7900
  f000
  ```
  *(251 more `0000` lines)*

- [ ] **Step 3: Run the test**
  ```bash
  ./assembler tests/test_memory.asm /tmp/out.mem && diff /tmp/out.mem tests/test_memory_golden.mem
  ```
  Expected: **no diff output**.

- [ ] **Step 4: Commit**
  ```bash
  git add tests/
  git commit -m "test: add LOAD/STORE and labels integration tests"
  ```

---

## Task 6: Full integration test + test script + documentation

**Files:**
- Create: `tests/test_datapath.asm`, `tests/run_tests.sh`
- Modify: `README.md`

- [ ] **Step 1: Create tests/test_datapath.asm**

  This must produce output identical to the existing `test_datapath.mem`:
  ```asm
  ; Full program matching test_datapath.mem
      MOV   R0, #0x0A    ; addr 0 — R0 = 10
      MOV   R1, #0x03    ; addr 1 — R1 = 3
      ADD   R0, R1       ; addr 2 — R0 = 13
      MOV   R2, R0       ; addr 3 — R2 = 13
      STORE R0, [R2]     ; addr 4 — mem[0x0D] = 0x0D
      LOAD  R3, [R2]     ; addr 5 — R3 = mem[0x0D]
      HALT               ; addr 6
  ```

- [ ] **Step 2: Run assembler against test_datapath.asm and diff against existing test_datapath.mem**

  The golden file already exists — but it only has 7 lines. The assembler pads to 256. Generate a padded golden:
  ```bash
  # Generate padded golden from the existing 7-line file
  python3 -c "
  lines = open('test_datapath.mem').read().splitlines()
  lines += ['0000'] * (256 - len(lines))
  print('\n'.join(lines))
  " > tests/test_datapath_golden.mem

  ./assembler tests/test_datapath.asm /tmp/out.mem && diff /tmp/out.mem tests/test_datapath_golden.mem
  ```
  Expected: **no diff output**.

- [ ] **Step 3: Create tests/run_tests.sh**

  ```bash
  #!/usr/bin/env bash
  set -e
  cd "$(dirname "$0")/.."

  g++ -std=c++17 -o assembler assembler.cpp

  pass=0; fail=0

  run_test() {
      local name=$1 asm=$2 golden=$3
      ./assembler "$asm" /tmp/asm_out.mem 2>/tmp/asm_err.txt
      if diff -q /tmp/asm_out.mem "$golden" >/dev/null 2>&1; then
          echo "  PASS  $name"
          pass=$((pass+1))
      else
          echo "  FAIL  $name"
          diff /tmp/asm_out.mem "$golden" | head -5
          fail=$((fail+1))
      fi
  }

  run_test "basic (MOV/ALU/HALT)"   tests/test_basic.asm      tests/test_basic_golden.mem
  run_test "memory (LOAD/STORE)"    tests/test_memory.asm     tests/test_memory_golden.mem
  run_test "labels (JMP/JZ)"        tests/test_labels.asm     tests/test_labels_golden.mem
  run_test "datapath reference"     tests/test_datapath.asm   tests/test_datapath_golden.mem

  # Error-case tests
  echo "; bad register" > /tmp/bad_reg.asm
  echo "MOV R5, #1" >> /tmp/bad_reg.asm
  if ./assembler /tmp/bad_reg.asm /tmp/ignored.mem 2>&1 | grep -q "unknown register"; then
      echo "  PASS  error: unknown register"
      pass=$((pass+1))
  else
      echo "  FAIL  error: unknown register"
      fail=$((fail+1))
  fi

  echo "MOV R0, #300" > /tmp/bad_imm.asm
  if ./assembler /tmp/bad_imm.asm /tmp/ignored.mem 2>&1 | grep -q "out of range"; then
      echo "  PASS  error: immediate out of range"
      pass=$((pass+1))
  else
      echo "  FAIL  error: immediate out of range"
      fail=$((fail+1))
  fi

  echo "JMP nowhere" > /tmp/bad_label.asm
  if ./assembler /tmp/bad_label.asm /tmp/ignored.mem 2>&1 | grep -q "undefined label"; then
      echo "  PASS  error: undefined label"
      pass=$((pass+1))
  else
      echo "  FAIL  error: undefined label"
      fail=$((fail+1))
  fi

  echo ""
  echo "$pass passed, $fail failed."
  [ "$fail" -eq 0 ]
  ```

  Make executable:
  ```bash
  chmod +x tests/run_tests.sh
  ```

- [ ] **Step 4: Run the full test suite**
  ```bash
  bash tests/run_tests.sh
  ```
  Expected:
  ```
    PASS  basic (MOV/ALU/HALT)
    PASS  memory (LOAD/STORE)
    PASS  labels (JMP/JZ)
    PASS  datapath reference
    PASS  error: unknown register
    PASS  error: immediate out of range
    PASS  error: undefined label

  7 passed, 0 failed.
  ```

- [ ] **Step 5: Update the project documentation**

  In the Build Progress table, change:
  ```
  | 12 | `assembler.py` | ⬜ todo | Python assembler for the ISA |
  ```
  to:
  ```
  | 12 | `assembler.cpp` | ✅ done | 7/7 pass |
  ```

  In the File Reference table, add:
  ```
  | `assembler.cpp` | Two-pass assembler: labels, comments, all 12 instructions → `.mem` |
  | `tests/run_tests.sh` | Assembler test suite (4 integration + 3 error-case tests) |
  ```

  Add to "How to run any testbench":
  ```bash
  # Assembler
  g++ -std=c++17 -o assembler assembler.cpp
  ./assembler input.asm output.mem
  bash tests/run_tests.sh   # run all assembler tests
  ```

- [ ] **Step 6: Final commit**
  ```bash
  git add assembler.cpp tests/ README.md
  git commit -m "feat: two-pass C++ assembler with full ISA support and test suite"
  ```
