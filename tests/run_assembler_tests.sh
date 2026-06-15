#!/usr/bin/env bash
set -euo pipefail

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

g++ -std=c++17 -o "$tmpdir/assembler" assembler.cpp

check_program() {
  local name="$1"
  local asm_file="$tmpdir/$name.asm"
  local mem_file="$tmpdir/$name.mem"
  local expected_file="$tmpdir/$name.expected"

  "$tmpdir/assembler" "$asm_file" "$mem_file"

  local line_count
  line_count="$(wc -l < "$mem_file" | tr -d ' ')"
  if [[ "$line_count" != "256" ]]; then
    echo "$name: expected 256 output lines, got $line_count" >&2
    exit 1
  fi

  head -n "$(wc -l < "$expected_file" | tr -d ' ')" "$mem_file" | diff -u "$expected_file" -

  local expected_lines
  expected_lines="$(wc -l < "$expected_file" | tr -d ' ')"
  if tail -n "+$((expected_lines + 1))" "$mem_file" | grep -v '^0000$' >/dev/null; then
    echo "$name: expected remaining output lines to be 0000" >&2
    exit 1
  fi
}

cat > "$tmpdir/sample.asm" <<'EOF'
; test program
    MOV   R0, #0x0A
    MOV   R1, #0x03
    ADD   R0, R1
    MOV   R2, R0
    STORE R0, [R2]
    LOAD  R3, [R2]
    HALT
EOF

cat > "$tmpdir/sample.expected" <<'EOF'
100a
1403
2100
0800
8800
7e00
f000
EOF

cat > "$tmpdir/labels.asm" <<'EOF'
    MOV  R0, #5
loop:
    NOT  R0
    JZ   done
    JMP  loop
done:
    HALT
EOF

cat > "$tmpdir/labels.expected" <<'EOF'
1005
6000
a004
9001
f000
EOF

check_program sample
check_program labels

cat > "$tmpdir/errors.asm" <<'EOF'
loop:
loop:
    MOV R5, #300
    JMP missing
    MOVI R0, R1
EOF

if "$tmpdir/assembler" "$tmpdir/errors.asm" "$tmpdir/errors.mem" >"$tmpdir/errors.out" 2>"$tmpdir/errors.err"; then
  echo "errors: assembler unexpectedly succeeded" >&2
  exit 1
fi

grep -q "error line 2: duplicate label 'loop'" "$tmpdir/errors.err"
grep -q "error line 3: unknown register 'R5'" "$tmpdir/errors.err"
grep -q "error line 3: immediate 300 out of range (0-255)" "$tmpdir/errors.err"
grep -q "error line 4: undefined label 'missing'" "$tmpdir/errors.err"
grep -q "error line 5: unknown mnemonic 'MOVI'" "$tmpdir/errors.err"

echo "PASS"
