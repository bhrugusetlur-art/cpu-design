# README Revamp Implementation Plan

**Goal:** Replace the current dense README with a portfolio-first project story, add verified visual assets, preserve useful technical detail in supporting documents, and leave the tracked repository free of private workflow references outside the maintained internal project map.

**Architecture:** The README becomes the concise entry point. Detailed FPGA and test instructions move to focused documents, while the OpenROAD document remains the physical-design reference. Visuals are produced from the real GDS and real simulation state rather than approximated project data.

**Tech stack:** Markdown, Mermaid, Verilog, Icarus Verilog, Python with Pillow, KLayout, SVG, Git.

## Global constraints

- Keep the full CPU RTL, ISA, caches, virtual memory, and physical layout unchanged.
- Do not claim physical-board testing without direct evidence.
- Label the FPGA animation as simulation-derived.
- Describe the GDS as a verified core block, not a complete packaged chip.
- Remove the temporary redesign specification after the user approves the final repository state.
- Work directly on `main`; do not create a feature branch.

---

### Task 1: Neutralize the documentation structure

**Files:**

- Delete: redundant tracked root project-map copy
- Move: legacy virtual-memory design document to `docs/specs/2026-07-09-virtual-memory-design.md`
- Move: legacy virtual-memory implementation plan to `docs/plans/2026-07-09-virtual-memory.md`
- Move: untracked assembler design document to `docs/specs/2026-06-04-assembler-design.md`
- Move: untracked assembler implementation plan to `docs/plans/2026-06-04-assembler.md`
- Modify: `.gitignore`
- Modify: moved design and plan documents
- Modify: maintained internal project map

- [x] Move all useful specifications and plans into the neutral directories without losing content.
- [x] Remove workflow-specific preambles and replace obsolete internal-map references with neutral prose.
- [x] Delete the redundant root project-map copy.
- [x] Remove generated local-analysis entries from the tracked ignore file and place required local-only exclusions in `.git/info/exclude`.
- [x] Remove ignored local workflow directories and generated analysis output from the working copy.
- [x] Update every moved-document link in tracked files.
- [x] Run the repository text/path audit and confirm only the maintained internal project map is exempt.
- [x] Run `git diff --check` and expect no output.

### Task 2: Produce an actual FPGA execution trace

**Files:**

- Create: `sim/fpga_demo_trace_tb.v`
- Modify: `Makefile`
- Modify: maintained internal project map

**Interface:**

- The testbench instantiates `cpu_top` with `sim/test_datapath.mem`.
- It writes `build/fpga-demo-trace.csv` with cycle, PC, halt, stall, request, write, address, flags, fault state, and R0–R3.
- It exits unsuccessfully if the CPU does not halt or if the final architectural state differs from the existing integration regression.

- [x] Add the trace testbench with a timeout and final-state assertions.
- [x] Add a Makefile target that builds and runs the trace testbench.
- [x] Run the target and verify the CSV contains reset, normal execution, cache-stall, and halt states.
- [x] Compare the final trace row with the existing `cpu_top` regression expectations.

### Task 3: Generate the FPGA visuals

**Files:**

- Create: `tools/render_fpga_visuals.py`
- Create: `docs/images/fpga-demo.gif`
- Create: `docs/images/fpga-controls.svg`
- Modify: `Makefile`
- Modify: maintained internal project map

**Interface:**

- Input: `build/fpga-demo-trace.csv`
- Outputs: an animated GIF and a static SVG.
- The animation displays the PC, halt marker, LED state, selected debug view, current instruction phase, and whether the CPU is stalled.
- The static diagram labels reset, speed/single-step selection, register selection, debug selection, LEDs, and seven-segment PC display.

- [x] Implement trace parsing with validation for required columns and nonempty rows.
- [x] Render a compact board-style frame for each meaningful state change, preserving longer display time for cache stalls and halt.
- [x] Render the static SVG with a responsive view box and unclipped labels.
- [x] Add a Makefile target for both assets.
- [x] Run the renderer and verify the GIF has multiple frames and a practical file size.
- [x] Open both assets and visually check labels, LEDs, digits, and narrow-width readability.

### Task 4: Render the final GDS layout

**Files:**

- Create: `tools/render_gds_layout.py`
- Create: `docs/images/final-gds-layout.png`
- Modify: maintained internal project map

**Interface:**

- Input: `openroad/work/results/sky130hd/cpu8/base/6_final.gds`
- Output: a high-resolution PNG overview of the actual routed core.
- The renderer loads the top cell, expands hierarchy, fits the layout, and preserves visible routing-layer contrast.

- [x] Implement a KLayout batch-rendering script with explicit input, output, width, and height parameters.
- [x] Run it against the final GDS using the installed OpenROAD container.
- [x] Confirm the PNG dimensions, nontrivial color content, and file size.
- [x] Open the PNG and visually verify that the complete routed core is visible and not clipped.

### Task 5: Move detailed instructions out of the README

**Files:**

- Create: `docs/fpga.md`
- Create: `docs/testing.md`
- Modify: `openroad/README.md`
- Modify: maintained internal project map

- [x] Move board controls, LED views, demo programs, expected states, and Vivado commands into `docs/fpga.md`.
- [x] Move regression categories, important end-to-end scenarios, and manual Icarus commands into `docs/testing.md`.
- [x] Keep physical-design commands, evidence, and limitations in `openroad/README.md` while updating moved-document links.
- [x] Verify supporting documents do not duplicate the README introduction or each other.

### Task 6: Rewrite the README as a portfolio story

**Files:**

- Replace: `README.md`
- Modify: maintained internal project map

- [x] Write the two-sentence project summary and show the final GDS image near the top.
- [x] Add a compact “What I built” section with CPU, cache, virtual-memory, FPGA, assembler, and ASIC outcomes.
- [x] Add the Mermaid architecture diagram with separate instruction-fetch and data-access paths.
- [x] Add the milestone-based “How I built it” narrative.
- [x] Add the evidence-based “How I tested it” table without unsupported physical-board claims.
- [x] Add the FPGA animation and control diagram with simulation labeling.
- [x] Add verified ASIC metrics and the current limitations.
- [x] Add only the minimal `make test`, assembler, FPGA, and OpenROAD entry commands.
- [x] Add the concise repository map and supporting-document links.
- [x] End with the current state: verified full core, no fabricated chip, and Tiny Tapeout CPU Lite not yet implemented.

### Task 7: Verify the complete repository

**Files:**

- Modify only if verification reveals defects.

- [x] Run `make test` and require exit code 0.
- [x] Run the FPGA trace target and require exit code 0.
- [x] Regenerate all visual assets from their real inputs.
- [x] Validate that every relative Markdown link and image path resolves.
- [x] Validate PNG dimensions and content, GIF frame count and size, and SVG XML structure.
- [x] Run the repository text/path audit, excluding only the maintained internal project map and `.git` history.
- [x] Run `git diff --check` and require no output.
- [x] Inspect the README at GitHub-like width and correct any confusing ordering, broken diagrams, or oversized visuals.
- [x] Update the maintained internal project map so its build status, file reference, documentation paths, and asset descriptions match the final tree.
- [x] Present the finished repository state for user approval while retaining the temporary redesign specification.

### Task 8: Final approval cleanup

**Files:**

- Delete after explicit user approval: temporary README redesign specification
- Modify after deletion: maintained internal project map

- [x] Wait for explicit approval of the finished repository state.
- [x] Delete the approved redesign specification.
- [x] Remove its file-reference entry from the maintained internal project map.
- [x] Rerun the repository audit, link validation, `git diff --check`, and `make test`.
- [x] Commit and push the approved final state directly to `main`.
