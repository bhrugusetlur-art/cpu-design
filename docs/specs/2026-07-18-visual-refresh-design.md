# README Visual Refresh Design

## Goal

Make the README visuals immediately recognizable and easier to understand:

1. The animated FPGA demonstration should resemble a real Digilent Basys3
   board while remaining an honest simulation of trace data.
2. The second FPGA image should be unmistakably identified as a static control
   map rather than another animation.
3. The GDS hero should present the actual routed core as a polished portfolio
   image without altering or inventing layout geometry.

## Basys3 reference

The board drawing follows the visible arrangement of the physical Basys3:

- blue rectangular PCB with corner mounting holes;
- large connectors across the top edge and Pmod headers at the sides;
- four-digit seven-segment display left of center;
- five-button directional cluster right of center;
- FPGA and supporting chips in the upper middle;
- sixteen LEDs directly above sixteen slide switches along the bottom edge;
- restrained white silkscreen labels, including `BASYS 3` and `ARTIX-7`.

The drawing is an original simplified rendering. It does not copy the product
photo into the repository and does not claim to be board footage.

## Animated FPGA demonstration

### Output

- File: `docs/images/fpga-demo.gif`
- Canvas: 1200 × 675 pixels
- Source: `build/fpga-demo-trace.csv`
- Frame count: one frame for each meaningful PC, request, stall, write, or halt
  state change; expected range is 8–40 frames.
- Looping: continuous.

### Appearance

The canvas uses a dark neutral background with a compact title/status strip
above the board. The board itself is rendered in deep Basys3 blue with subtle
shadows, darker connector housings, metallic pins, white silkscreen, and red
seven-segment/LED illumination.

The visual hierarchy is:

1. Four-digit display showing `H` plus the 8-bit PC after HALT, or the PC while
   running.
2. Sixteen physical LED positions showing the selected debug view.
3. Sixteen slide switches, with the six switches used by the wrapper visibly
   selected to match the current simulated view.
4. Small status labels for cycle, instruction, request, write, stall, and halt.
5. A persistent `ANIMATED CPU TRACE` marker so a frozen preview frame is still
   identifiable as an animation.

Frame data remains trace-driven. The renderer must not invent CPU values.
Longer frame durations are used for stalls and final halt so those states can
be read easily.

## Static FPGA control map

### Output

- File: `docs/images/fpga-controls.svg`
- Responsive view box: `0 0 1400 800`
- Source of truth: `design/basys3_top.v`

The control map reuses the same realistic board geometry, but its LEDs and
display remain neutral. Callout lines identify:

- `btnC` reset;
- `btnR` single-step;
- `SW1:SW0` clock speed/single-step selection;
- `SW3:SW2` register selection;
- `SW5:SW4` debug-view selection;
- sixteen debug LEDs;
- four-digit PC/HALT display.

The image title and README caption both say `Static control map`. Nothing in
the file implies that it should animate.

## Animation clarity in the README

The FPGA section is split into two labeled subsections:

1. `Animated simulation` above the GIF, with a sentence telling readers to
   watch the PC, LEDs, and cycle count change.
2. `Static control map` above the SVG, with a sentence explaining that it maps
   physical controls and outputs.

The FPGA guide uses the same labels. If a file viewer displays only the first
GIF frame, the animation marker and cycle text still communicate what the
asset contains; GitHub renders the tracked multi-frame GIF normally.

## GDS portfolio hero

### Outputs and data flow

- Raw KLayout render: `build/final-gds-layout-raw.png` (generated, untracked).
- Styled README image: `docs/images/final-gds-layout.png` (tracked).
- Final canvas: 1600 × 1100 pixels.

KLayout renders the real `6_final.gds` with hierarchy expanded, the grid
hidden, and the core fitted without clipping. The raw view uses the core
boundary plus upper routing layers so the major power grid and signal routing
remain visible without lower-mask washout.

A separate Pillow styling step places that untouched raw layout render into a
dark portfolio card. It may add only presentation elements outside the layout
viewport:

- `SKY130 • ROUTED CORE` title;
- `RTL → GDS` subtitle;
- small verified metric chips for core size, utilization, timing target, and
  project-deck LVS result;
- an M3/M4/M5 color legend;
- a caption stating that the image is rendered from the actual final GDS.

### Bare-die presentation

The final presentation resembles an unpackaged silicon die rather than a
layout-viewer screenshot. The real routing image fills a square, front-facing
silicon surface with a narrow metallic bevel, soft drop shadow, subtle
specular reflection, and a dark wafer-style background. The title reads
`SKY130 • BARE CORE DIE` and the status badge reads `UNPACKAGED CORE BLOCK`.

The layer palette uses semiconductor-like gold, teal, and violet tones. The
metric panel remains beside the die and explicitly states the core size,
utilization, timing target, and project-deck LVS result.

No package legs, wire bonds, I/O pads, or padframe geometry are invented. The
die remains front-facing, and all bevel, shadow, reflection, title, legend,
and metric elements stay outside the GDS viewport. The style must not blur,
redraw, add, or remove layout geometry.

## Renderer structure

`tools/render_fpga_visuals.py` remains the single trace-to-FPGA asset tool. Its
board geometry is shared between the animated raster frames and the static SVG
so both images agree.

`tools/render_gds_layout.py` remains a KLayout-only batch script and produces
the clean raw geometry render. A new Pillow utility styles that raw render into
the tracked README hero. A Makefile target documents and runs both stages when
the final GDS and Docker image are available.

## Verification

### FPGA checks

The visual test regenerates both assets and requires:

- GIF format, 1200 × 675 dimensions, 8–40 frames, and practical file size;
- at least two distinct frame hashes, proving the animation is not a repeated
  still image;
- visible PC/LED changes between the first and last meaningful frames;
- Basys3-blue pixels, red illuminated pixels, and dark connector pixels;
- sixteen LED positions and sixteen switch positions in the SVG;
- static-map title plus all control labels;
- SVG view box `0 0 1400 800` and valid XML.

### GDS checks

The GDS image test requires:

- PNG format and 1600 × 1100 dimensions;
- nontrivial dark and colored pixel ranges;
- a square 800 × 800 detailed layout viewport rather than a flat illustration;
- a visible metallic bevel and dark wafer background outside the viewport;
- expected metric/title text regions with no clipping;
- practical repository file size.

The final verification also reruns `make test`, relative Markdown link checks,
the repository terminology/path audit, GitHub Mermaid parsing, and
`git diff --check`.

## Accuracy rules

- The FPGA animation is always labeled simulation-derived.
- The static diagram is never described as an animation.
- The GDS hero is always described as a verified core-block render, not a
  packaged or fabricated chip.
- Physical-board testing is not claimed without direct evidence.
- GDS metrics remain identical to the physical-design report.

## Out of scope

- Changing CPU, cache, MMU, TLB, FPGA-wrapper, or physical-layout behavior.
- Copying the supplied product photo into the public repository.
- Creating camera-like footage or claiming that the animation came from a
  powered board.
- Running a new physical-design flow or changing the final GDS.
