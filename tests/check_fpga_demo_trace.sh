#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

trace="build/fpga-demo-trace.csv"
run_output=$(make fpga-demo-trace 2>&1)
printf '%s\n' "$run_output"

if grep -Fq "WARNING:" <<<"$run_output"; then
  echo "FAIL: FPGA trace run emitted a warning" >&2
  exit 1
fi

[[ -s "$trace" ]] || {
  echo "FAIL: missing FPGA demo trace: $trace" >&2
  exit 1
}

expected_header="cycle,pc,halt,stall,req,we,addr,zero,page_fault,fault_va,r0,r1,r2,r3,instr"
actual_header=$(head -n 1 "$trace")
[[ "$actual_header" == "$expected_header" ]] || {
  echo "FAIL: unexpected FPGA trace header: $actual_header" >&2
  exit 1
}

awk -F, '
  NR == 1 { next }
  $4 == 1 { saw_stall = 1 }
  $5 == 1 { saw_request = 1 }
  $3 == 1 { saw_halt = 1 }
  END {
    if (!saw_stall) {
      print "FAIL: trace never records a cache/MMU stall" > "/dev/stderr"
      exit 1
    }
    if (!saw_request) {
      print "FAIL: trace never records a memory request" > "/dev/stderr"
      exit 1
    }
    if (!saw_halt) {
      print "FAIL: trace never records HALT" > "/dev/stderr"
      exit 1
    }
  }
' "$trace"

awk -F, '
  NR > 1 { last = $0 }
  END {
    split(last, f, ",")
    if (f[2] != "06" || f[3] != "1" ||
        f[11] != "0d" || f[12] != "03" ||
        f[13] != "0d" || f[14] != "0d") {
      print "FAIL: unexpected final FPGA trace row: " last > "/dev/stderr"
      exit 1
    }
  }
' "$trace"

echo "PASS: FPGA demo trace records stalls, requests, halt, and the expected final CPU state"
