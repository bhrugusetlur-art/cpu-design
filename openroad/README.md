# OpenROAD Sky130 hardening

This directory configures an initial standard-cell hardening run of
`design/cpu_top.v` with OpenROAD Flow Scripts (ORFS) and the `sky130hd`
platform. It produces a routed **core-block GDSII**, not a complete packaged
chip or shuttle-ready padframe.

## Prerequisites

- A Linux environment (native Linux, WSL2, or Docker Desktop)
- GNU Make and Git
- A current clone of OpenROAD Flow Scripts

On Windows, install WSL2 with Ubuntu first. Administrator permission and a
reboot can be required when the WSL optional features are initially enabled.

## Run

From a Linux shell:

```bash
git clone --recursive \
  https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git \
  "$HOME/OpenROAD-flow-scripts"

cd /path/to/cpu-design

make --file="$HOME/OpenROAD-flow-scripts/flow/Makefile" \
  DESIGN_CONFIG="$(pwd)/openroad/config.mk"
```

When using the official ORFS Docker image, run the same `make` invocation
through ORFS's `flow/util/docker_shell` helper and ensure this repository is
mounted into the container.

Generated logs, reports, databases, netlists, and GDS files are written below
`openroad/work/`. The final layout is located at:

```text
openroad/work/results/sky130hd/cpu8/base/6_final.gds
```

`openroad/work/` is intentionally ignored by Git because it is several
gigabytes. Back it up separately if the generated databases, reports, and GDS
must be preserved; the tracked RTL/configuration can reproduce the flow but is
not a backup of the generated layout.

## 2026-07-17 result

ORFS completed synthesis, floorplan, placement, CTS, routing, extraction, and
GDS stream-out for the `cpu_top` core using the official
`openroad/orfs:latest` image.

- Final GDS: `openroad/work/results/sky130hd/cpu8/base/6_final.gds`
- GDS size: 34,672,628 bytes
- SHA-256: `EB8056AF757277F4828EB0E29479399363749B9FE188F15C5EBE53F8C93879CD`
- Die: 1,094.220 um x 1,094.220 um; final design utilization: about 19%
- Constraint: 10 MHz (100 ns); final worst setup slack: 90.29 ns
- Estimated minimum period: 9.71 ns (102.96 MHz)
- Final setup, hold, max-slew, and max-capacitance violations: 0
- OpenROAD detailed-route DRC and antenna violations: 0
- Standalone KLayout Sky130 DRC markers: 0
- VDD/VSS connectivity: connected; estimated power: 3.70 mW; worst reported
  IR drop: about 0.000015 V

The generated KLayout technology file initially contained a stale
`/workspace/.../klayout_tech.lef` path while the Docker helper mounted this
repository at `/work`. That caused the first GDS stream-out to omit 138,398
default-via references. Correcting the generated path to `/work/...`, rerunning
`do-gds-merged`, and copying `6_1_merged.gds` to `6_final.gds` produced the
via-complete GDS identified by the hash above. A future run must check
`6_1_merge.log` for `Invalid via name` warnings before accepting its GDS.

LVS is **not signed off**. The bundled Sky130 CDL first required generated-copy
normalization (`short` resistor values and CDL `/` instance separators). After
that, KLayout extracted the routed network but the bundled LVS deck still did
not promote the 82 GDS port labels to top-level circuit pins and reported
`ERROR : Netlists don't match`. This remains a fabrication blocker and needs a
validated shuttle/foundry LVS deck or a corrected top-level label/pin flow.

## Current limitations

- `cpu_top` is hardened as a core with debug ports; it has no I/O pad cells,
  package, ESD protection, or shuttle harness.
- `imem.v` uses `$readmemh("program.mem")`. The selected program is therefore
  fixed during synthesis and must be treated as a mask/standard-cell ROM for
  an ASIC, or replaced with a loadable memory architecture.
- `dmem.v` uses an `initial` block for the identity page table. That power-up
  behavior is not a reliable ASIC boot mechanism and must be replaced before
  tapeout.
- The inferred instruction memory, data memory, and cache arrays may be built
  from standard cells. Production hardening should evaluate compatible SRAM
  macros and adapt the memory interfaces where necessary.
- Final tapeout still requires a selected shuttle/foundry harness, padframe,
  foundry signoff decks, clean LVS, and packaging decisions.
