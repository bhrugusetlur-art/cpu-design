# README Redesign

## Goal

Turn the repository front page into a concise portfolio story that answers three questions in order:

1. What was built?
2. How was it built?
3. How was it tested?

The result must remain technically accurate, visually useful, and honest about what has and has not reached physical hardware.

## Audience

The primary audience is recruiters, instructors, hardware engineers, and curious builders seeing the project for the first time. Reproduction details remain available, but they do not interrupt the main story.

## README structure

The new README uses this order:

1. Title and a two-sentence project summary.
2. A hero image rendered from the final Sky130 GDS.
3. A compact “What I built” section covering the CPU, caches, virtual memory, assembler, FPGA wrapper, and physical core.
4. A Mermaid architecture diagram showing instruction fetch and the LOAD/STORE path through the TLB, MMU, L1, L2, and data memory.
5. A “How I built it” milestone sequence from individual modules through full integration, FPGA packaging, and ASIC hardening.
6. A “How I tested it” evidence table separating component, integration, FPGA, and physical-design verification.
7. An FPGA demonstration section containing a simulation-derived animation and a static control diagram.
8. An ASIC result section with final layout metrics, verification status, and current fabrication limitations.
9. Minimal build and test commands.
10. A short repository map and links to detailed supporting documents.
11. A clear “Where the project is now” section stating that the full core is verified and the smaller Tiny Tapeout edition has not yet been implemented.

Long command lists, raw program listings, detailed board controls, and deep physical-verification notes move into supporting documents.

## Visual assets

### Final GDS layout

- Output: `docs/images/final-gds-layout.png`
- Source: `openroad/work/results/sky130hd/cpu8/base/6_final.gds`
- The image is rendered from the real final layout, not recreated or approximated.
- It shows the complete core at useful overview scale with routed layers visible.
- The README caption identifies it as the verified Sky130 core layout.

### FPGA demonstration animation

- Output: `docs/images/fpga-demo.gif`
- The animation is generated from actual CPU simulation state changes.
- It presents a simplified Basys3 face with the seven-segment PC display, status LEDs, switches, and the current execution phase.
- It is labeled as a simulation of the board display so it cannot be mistaken for camera footage.
- The animation is optimized for GitHub display and kept small enough for normal repository use.

### FPGA controls

- Output: `docs/images/fpga-controls.svg`
- The diagram shows the controls and debug groups used by `basys3_top.v` without copying a vendor product image.
- Labels cover reset, run speed/single-step, register selection, debug-view selection, LEDs, and the PC display.

### Architecture

The architecture visual remains Mermaid source inside the README so it is searchable, maintainable, and rendered directly by GitHub.

## Supporting documents

- `docs/fpga.md`: board controls, debug views, demo programs, expected results, and Vivado workflow.
- `docs/testing.md`: regression categories, important test scenarios, and manual commands.
- `openroad/README.md`: detailed physical-design flow, metrics, verification evidence, and limitations.
- Existing design specifications and implementation plans move into `docs/specs/` and `docs/plans/` with neutral wording and updated links.

## Repository cleanup

- Delete the redundant root-level project-map copy and retain the maintained internal project map.
- Move legacy design and implementation documents into `docs/specs/` and `docs/plans/`.
- Preserve both existing virtual-memory documents and both currently untracked assembler documents.
- Remove workflow-assistant wording and preambles from public files.
- Remove references to the internal project map from every other tracked file.
- Remove generated local-analysis references from tracked ignore rules and documentation while keeping those generated files excluded locally.
- After cleanup, a repository-wide audit must find no prohibited workflow-assistant names or terminology outside the maintained internal project map.

## Accuracy rules

- Do not claim that the current FPGA wrapper was tested on a physical board unless the repository contains direct evidence.
- Distinguish simulation-derived FPGA visuals from physical-board footage.
- Describe the GDS as a verified core block, not a complete packaged chip.
- State that project-deck LVS is clean while qualified shuttle or foundry signoff is still required.
- State that ASIC-safe boot, memory initialization, I/O protection, and the shuttle wrapper remain unfinished.
- Do not describe the planned Tiny Tapeout CPU Lite target as implemented.

## Verification

Completion requires all of the following:

1. `make test` exits successfully.
2. `git diff --check` reports no whitespace errors.
3. Every local README link resolves to an existing tracked file.
4. The final GDS PNG opens correctly and visibly contains the routed core.
5. The FPGA GIF opens correctly, contains multiple frames, and stays within a practical repository size.
6. The FPGA SVG renders without clipped labels or overlapping controls.
7. A repository-wide text and path audit finds no prohibited workflow-assistant references outside the maintained internal project map.
8. The README renders as a clear portfolio page at normal GitHub width.

## Out of scope

- Changing CPU RTL, the ISA, cache behavior, virtual-memory behavior, or physical layout.
- Claiming new FPGA or silicon validation.
- Building the Tiny Tapeout CPU Lite implementation.
- Publishing or submitting the design to a fabrication shuttle.
