#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

deck="openroad/sky130hd_lvs.lylvs"
if [[ ! -f "$deck" ]]; then
  echo "FAIL: missing project LVS deck: $deck" >&2
  exit 1
fi

for layer in LI MET1 MET2 MET3 MET4 MET5; do
  grep -Fq "connect(${layer}, ${layer}PIN)" "$deck" || {
    echo "FAIL: $deck does not connect ${layer} drawing geometry to ${layer}PIN" >&2
    exit 1
  }
  grep -Fq "connect(${layer}PIN, ${layer}TXT)" "$deck" || {
    echo "FAIL: $deck does not connect ${layer}PIN to ${layer}TXT" >&2
    exit 1
  }
done

grep -Fq 'netlist.make_top_level_pins' "$deck" || {
  echo "FAIL: $deck does not promote named top-level nets to pins" >&2
  exit 1
}

grep -Fq 'report_lvs($report_file)' "$deck" || {
  echo "FAIL: $deck does not write the requested LVS database" >&2
  exit 1
}

for circuit in \
  sky130_fd_sc_hd__a2111oi_2 \
  sky130_fd_sc_hd__a211oi_4 \
  sky130_fd_sc_hd__a21oi_2 \
  sky130_fd_sc_hd__ha_4; do
  grep -Fq "join_symmetric_nets(\"${circuit}\")" "$deck" || {
    echo "FAIL: $deck does not normalize split symmetric nets in ${circuit}" >&2
    exit 1
  }
done

if [[ $(grep -Fc 'join_symmetric_nets("sky130_fd_sc_hd__a211oi_4")' "$deck") -lt 2 ]]; then
  echo "FAIL: $deck needs two symmetry passes for the nested split branches in sky130_fd_sc_hd__a211oi_4" >&2
  exit 1
fi

grep -Fq 'conb.join_nets(conb.net_by_name("VGND"), conb.net_by_name("LO"))' "$deck" || {
  echo "FAIL: $deck does not normalize the CONB low output short" >&2
  exit 1
}

grep -Fq 'conb.join_nets(conb.net_by_name("VPWR"), conb.net_by_name("HI"))' "$deck" || {
  echo "FAIL: $deck does not normalize the CONB high output short" >&2
  exit 1
}

grep -Fq 'top.join_nets(vss, vnb)' "$deck" || {
  echo "FAIL: $deck does not reconnect the top-level substrate net through the inserted tap cells" >&2
  exit 1
}

echo "PASS: Sky130 LVS deck connects top pins and normalizes known Sky130 split-gate and constant cells"
