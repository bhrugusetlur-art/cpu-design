# Testing and verification

The design is checked from small combinational blocks through complete CPU
programs. The standard regression runs 15 Verilog suites, a Basys3 wrapper
compile check, plus assembler and physical-verification-deck checks:

```bash
make test
```

## Coverage map

| Level | Evidence |
|---|---|
| CPU building blocks | ALU operations and flags, register-file timing, decoder outputs, PC branches/stalls/halt, instruction ROM, and data RAM |
| Cache hierarchy | L1 and L2 cold misses, hits, dirty write-back, LRU replacement, byte ordering, and the full L1 → L2 → memory path |
| CPU integration | MOV/ADD/STORE/LOAD/HALT with the real cache hierarchy and three complete demo programs |
| Virtual memory | TLB fill/hit/eviction/flush, cache-mediated page walks, translated replay, stale-entry invalidation, remapping, page fault, and frozen fault state |
| FPGA wrapper | Elaboration of `basys3_top` with the complete CPU hierarchy |
| Tooling | Assembler encodings, labels, padding, and invalid-input errors |
| Physical flow | Structural checks for the project Sky130 LVS deck; complete GDS metrics and LVS evidence are documented separately |
| README evidence | The FPGA trace is checked for requests, stalls, halt, and final state; generated GIF, SVG, and GDS PNG are checked for valid content and practical dimensions |

Two end-to-end regressions carry most of the architectural proof:

- `sim/cpu_programs_tb.v` runs the cache, ALU, and branch programs on three
  complete CPU instances and checks every final PC/register result.
- `sim/cpu_vm_tb.v` proves that rewriting a PTE flushes a stale TLB entry,
  redirects a later access to the new physical page, and freezes the CPU with
  the correct address after an invalid translation.

## Run one Verilog suite

The Makefile target names match the testbench names without `_tb.v`:

```bash
make build/alu
vvp build/alu

make build/cpu_vm
vvp build/cpu_vm
```

For a direct full-CPU invocation:

```bash
iverilog -g2012 -o build/vm_sim \
  sim/cpu_vm_tb.v \
  design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v \
  design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v \
  design/dmem.v design/pc.v design/imem.v design/control.v \
  design/reg_file.v design/alu.v
vvp build/vm_sim
```

The simulations write VCD waveforms that can be opened in GTKWave or another
VCD viewer.

## Vivado simulator

The same complete demo-program testbench can be run from a Vivado command
prompt:

```text
xvlog -sv sim/cpu_programs_tb.v design/cpu_top.v design/mmu.v design/tlb.v design/datapath.v design/cache_hierarchy.v design/l1_cache.v design/l2_cache.v design/dmem.v design/pc.v design/imem.v design/control.v design/reg_file.v design/alu.v
xelab -debug typical cpu_programs_tb -s cpu_programs_sim
xsim cpu_programs_sim -runall
```

## Documentation evidence

Regenerate and validate the simulation-derived FPGA assets:

```bash
python3 -m pip install -r requirements-visuals.txt
make fpga-readme-assets
make visual-checks
```

The bare-die GDS hero is regenerated from the ignored physical-design result
with the tracked KLayout and Pillow stages. The styling step keeps the real
routing viewport unchanged and adds only the die edge, wafer background,
metrics, and legend around it:

```bash
make gds-readme-asset
python3 tests/check_gds_image.py
```

See [FPGA guide](fpga.md) for board controls and [OpenROAD hardening](../openroad/README.md)
for physical-design commands, timing/area metrics, and the scope of the DRC and
LVS results.
