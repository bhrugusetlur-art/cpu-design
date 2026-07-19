# README Visual Refresh Implementation Plan

> Execute task-by-task with test-first changes and review checkpoints.

**Goal:** Replace the abstract FPGA visuals with a trace-driven Basys3 likeness,
make the static control map unambiguous, and turn the real routed GDS into a
clean portfolio hero.

**Architecture:** `tools/render_fpga_visuals.py` continues to own both FPGA
assets and shares one board coordinate system between the GIF and SVG. KLayout
produces an unstyled raw routing image in `build/`; a new Pillow utility places
that unchanged geometry inside the tracked GDS portfolio frame.

**Tech stack:** Python 3, Pillow, SVG, KLayout 0.30.7, Docker, Make, Markdown,
Icarus Verilog, Git.

## Global constraints

- Work directly on `main`; do not create a feature branch.
- Keep all CPU, cache, MMU, TLB, FPGA-wrapper, and GDS behavior unchanged.
- Do not copy the supplied Basys3 photo into the repository.
- Keep every FPGA state trace-driven and label it as simulation-derived.
- Keep the second FPGA asset explicitly static.
- Preserve the real GDS geometry; presentation additions stay outside its
  viewport.
- Keep `docs/specs/2026-07-18-readme-redesign.md` until the user approves the
  final repository state.

---

### Task 1: Specify the realistic FPGA assets with failing tests

**Files:**

- Modify: `tests/check_fpga_visuals.py`

**Interfaces:**

- Consumes: `docs/images/fpga-demo.gif` and
  `docs/images/fpga-controls.svg`.
- Produces: executable requirements for the renderer in Task 2.

- [ ] **Step 1: Change the expected GIF and SVG dimensions**

Replace the current dimension assertions with:

```python
assert image.size == (1200, 675), image.size
assert root.attrib.get("viewBox") == "0 0 1400 800", root.attrib
```

- [ ] **Step 2: Require genuinely different GIF frames**

Add frame hashing while the GIF is open:

```python
frame_hashes = set()
for frame_index in range(image.n_frames):
    image.seek(frame_index)
    frame_hashes.add(hash(image.convert("RGB").tobytes()))
assert len(frame_hashes) >= 4, len(frame_hashes)
```

- [ ] **Step 3: Require the Basys3 palette**

Count representative pixels in the first and last frames:

```python
def count_pixels(rgb, predicate):
    return sum(1 for pixel in rgb.getdata() if predicate(pixel))

image.seek(0)
first = image.convert("RGB")
image.seek(image.n_frames - 1)
last = image.convert("RGB")
assert count_pixels(first, lambda p: p[2] > 80 and p[2] > p[0] * 1.4) > 80_000
assert count_pixels(last, lambda p: p[0] > 170 and p[1] < 100) > 150
assert first.tobytes() != last.tobytes()
```

- [ ] **Step 4: Require static-map structure and labels**

Add XML checks:

```python
namespace = {"svg": "http://www.w3.org/2000/svg"}
assert len(root.findall(".//*[@data-role='led']")) == 16
assert len(root.findall(".//*[@data-role='switch']")) == 16
for label in (
    "STATIC CONTROL MAP", "btnC", "btnR", "SW1:SW0", "SW3:SW2",
    "SW5:SW4", "LED[15:0]", "PC / HALT display", "BASYS 3",
):
    assert label in svg_text, label
```

- [ ] **Step 5: Run the test and verify red state**

Run:

```bash
python3 -m pip install -r requirements-visuals.txt
make PYTHON=python3 fpga-demo-trace
python3 tests/check_fpga_visuals.py
```

Expected: failure because the old GIF is 960 × 540 and the old SVG view box is
1200 × 520.

---

### Task 2: Render a recognizable Basys3 board

**Files:**

- Modify: `tools/render_fpga_visuals.py`
- Modify: `tests/check_fpga_visuals.py`

**Interfaces:**

- Consumes: `build/fpga-demo-trace.csv` with the existing validated schema.
- Produces: `docs/images/fpga-demo.gif` at 1200 × 675 and
  `docs/images/fpga-controls.svg` with view box `0 0 1400 800`.

- [ ] **Step 1: Establish shared board coordinates and colors**

Replace the raster dimensions and add constants:

```python
WIDTH = 1200
HEIGHT = 675
BOARD = (95, 150, 1105, 625)
PCB_BLUE = "#0b4f85"
PCB_EDGE = "#55a6d8"
SILK = "#dcebf4"
CONNECTOR = "#151b22"
LED_ON = "#ff334d"
LED_OFF = "#4b1822"
```

- [ ] **Step 2: Add focused raster drawing helpers**

Implement these signatures so the physical regions remain isolated:

```python
def draw_mounting_holes(draw: ImageDraw.ImageDraw) -> None:
    for x, y in ((122, 176), (1078, 176), (122, 598), (1078, 598)):
        draw.ellipse((x - 14, y - 14, x + 14, y + 14), fill="#071b2b", outline="#9ac5dd", width=3)

def draw_top_connectors(draw: ImageDraw.ImageDraw) -> None:
    draw.rounded_rectangle((455, 153, 615, 220), radius=7, fill=CONNECTOR, outline="#8b98a2", width=3)
    draw.rounded_rectangle((684, 160, 770, 218), radius=5, fill="#d9dde0", outline="#78828a", width=3)
    draw.rounded_rectangle((812, 160, 867, 207), radius=4, fill=CONNECTOR, outline="#8b98a2", width=2)
    draw.ellipse((1002, 163, 1032, 193), fill="#b7282f", outline="#e7a2a5", width=2)

def draw_side_headers(draw: ImageDraw.ImageDraw) -> None:
    for x in (96, 1070):
        for y in (255, 365):
            draw.rounded_rectangle((x, y, x + 38, y + 78), radius=5, fill=CONNECTOR, outline="#65717b", width=2)
            for pin in range(4):
                py = y + 13 + pin * 17
                draw.rectangle((x + 10, py, x + 28, py + 4), fill="#d8af58")

def draw_fpga_and_chips(draw: ImageDraw.ImageDraw) -> None:
    draw.rounded_rectangle((530, 252, 680, 392), radius=8, fill="#151b22", outline="#8aa6b7", width=3)
    draw.text((605, 306), "ARTIX-7", font=font(17, bold=True), fill=SILK, anchor="mm")
    for box in ((330, 245, 405, 315), (420, 255, 485, 330), (700, 242, 762, 310)):
        draw.rounded_rectangle(box, radius=5, fill="#1a232b", outline="#7895a7", width=2)

def draw_button_cluster(draw: ImageDraw.ImageDraw) -> None:
    for x, y, label in ((846, 306, "U"), (846, 382, "D"), (808, 344, "L"), (884, 344, "R"), (846, 344, "C")):
        draw.rounded_rectangle((x - 18, y - 18, x + 18, y + 18), radius=6, fill="#171d23", outline="#aebbc4", width=2)
        draw.text((x, y), label, font=font(12, bold=True), fill=SILK, anchor="mm")

def draw_switch_bank(draw: ImageDraw.ImageDraw, bits: int) -> None:
    for index in range(16):
        x = 138 + index * 57
        active = (bits >> index) & 1
        draw.rounded_rectangle((x, 550, x + 30, 606), radius=4, fill="#11171c", outline="#75818a", width=2)
        paddle_y = 557 if active else 577
        draw.rounded_rectangle((x + 5, paddle_y, x + 25, paddle_y + 20), radius=3, fill="#2e3840")

def draw_led_bank(draw: ImageDraw.ImageDraw, led_bits: int) -> None:
    for index in range(16):
        x = 153 + index * 57
        active = (led_bits >> index) & 1
        draw.ellipse((x - 8, 520, x + 8, 536), fill=LED_ON if active else LED_OFF, outline="#ff8798" if active else "#7a3440", width=2)

def draw_board_labels(draw: ImageDraw.ImageDraw) -> None:
    draw.text((198, 205), "BASYS 3", font=font(28, bold=True), fill=SILK)
    draw.text((930, 230), "DIGILENT", font=font(15, bold=True), fill=SILK)
    draw.text((605, 410), "FPGA", font=font(12), fill="#a8c8dc", anchor="mm")
```

The helpers draw four mounting holes, VGA/USB/power connector silhouettes,
four side headers, a central Artix-7 package, five buttons, sixteen switches,
sixteen LEDs, and white silkscreen text.

- [ ] **Step 3: Correct the seven-segment map and place the display**

Fix the zero segment typo and keep all segment maps explicit:

```python
SEGMENTS["0"] = "abcdef"
```

Place the display at the left-center of the PCB and draw four digits. Running
frames show two blank digits plus the hexadecimal PC; halt frames show `H`, a
blank, and the hexadecimal PC.

- [ ] **Step 4: Drive switches and LEDs from the trace**

Use the existing `led_value` function. Add:

```python
def switch_value(row: dict[str, int], memory_view: bool) -> int:
    speed = 0b00
    register_select = 0b00
    debug_view = 0b10 if memory_view else 0b01
    return speed | (register_select << 2) | (debug_view << 4)
```

Render all sixteen physical switches, even though only `SW5:SW0` are connected
by `basys3_top.v`.

- [ ] **Step 5: Add a readable animation/status strip**

Above the board, draw:

```text
BASYS3 • 8-BIT CPU
ANIMATED CPU TRACE • simulation-derived
cycle NN • instruction 0xNNNN • EXECUTING / MEMORY WAIT / HALT
REQ  WRITE  STALL  HALT
```

Status pills illuminate only from the corresponding trace bits.

- [ ] **Step 6: Rebuild the static SVG using the same layout**

Generate a 1400 × 800 SVG with:

- the same blue board proportions and physical component ordering;
- `data-role="led"` on each of 16 LED circles;
- `data-role="switch"` on each of 16 switch groups;
- callout lines that terminate outside the board rather than crossing labels;
- title `STATIC CONTROL MAP` and subtitle `Basys3 wrapper inputs and debug outputs`.

- [ ] **Step 7: Regenerate assets and verify green state**

Run:

```bash
make PYTHON=python3 visual-checks
```

Expected: 14 unique trace-driven frames, 1200 × 675 GIF, valid 1400 × 800
static SVG, and all palette/structure assertions pass.

- [ ] **Step 8: Visually inspect both outputs**

Open both files and confirm that the display, five buttons, LED row, switch
row, top connectors, side headers, and callout labels are legible and not
clipped.

---

### Task 3: Build the polished actual-GDS hero

**Files:**

- Modify: `tests/check_gds_image.py`
- Modify: `tools/render_gds_layout.py`
- Create: `tools/style_gds_visual.py`
- Modify: `Makefile`
- Modify: `docs/testing.md`

**Interfaces:**

- Consumes: `openroad/work/results/sky130hd/cpu8/base/6_final.gds`.
- Intermediate: `build/final-gds-layout-raw.png`, a clean KLayout render.
- Produces: `docs/images/final-gds-layout.png`, a 1600 × 1100 styled image.

- [ ] **Step 1: Write the failing GDS hero assertions**

Change the dimension check and add region checks:

```python
assert layout.size == (1600, 1100), layout.size
header = rgb.crop((0, 0, 1600, 190))
viewport = rgb.crop((55, 205, 1125, 1045))
legend = rgb.crop((1160, 250, 1560, 920))
assert sum(ImageStat.Stat(header).mean) / 3 < 80
assert max(channel[1] - channel[0] for channel in ImageStat.Stat(viewport).extrema) > 120
assert sum(ImageStat.Stat(legend).mean) / 3 > 18
```

- [ ] **Step 2: Run the GDS check and verify red state**

Run:

```bash
python3 tests/check_gds_image.py
```

Expected: failure because the existing image is 1600 × 1600.

- [ ] **Step 3: Remove the KLayout grid and render raw geometry**

Construct the view with the no-grid option:

```python
view = pya.LayoutView(False, None, pya.LayoutView.LV_NoGrid)
```

Keep only boundary and upper M3/M4/M5 routing layers. Use a dark-compatible
palette, expand hierarchy, fit the core, and write the requested raw output.

- [ ] **Step 4: Create the Pillow styling utility**

Implement:

```python
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()

def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        Path("/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf"),
        Path("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf" if bold else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()

def rounded_gradient(size: tuple[int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        ratio = y / max(height - 1, 1)
        color = (8 + int(8 * ratio), 13 + int(11 * ratio), 24 + int(18 * ratio))
        draw.line((0, y, width, y), fill=color)
    return image

def fit_layout(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    fitted = image.convert("RGB").copy()
    fitted.thumbnail(size, Image.Resampling.LANCZOS)
    result = Image.new("RGB", size, "#05080d")
    result.paste(fitted, ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2))
    return result

def draw_metric_chip(draw: ImageDraw.ImageDraw, box, label: str, value: str) -> None:
    draw.rounded_rectangle(box, radius=14, fill="#151f31", outline="#304466", width=2)
    x0, y0, _, _ = box
    draw.text((x0 + 18, y0 + 14), label, font=font(14, bold=True), fill="#6ee7f2")
    draw.text((x0 + 18, y0 + 42), value, font=font(20, bold=True), fill="#f4f7fb")

def main() -> None:
    args = parse_args()
    if not args.input.is_file():
        raise FileNotFoundError(args.input)
    with Image.open(args.input) as source:
        if source.width < 512 or source.height < 512:
            raise ValueError("raw GDS render must be at least 512x512")
        layout = fit_layout(source, (1030, 810))

    canvas = rounded_gradient((1600, 1100))
    draw = ImageDraw.Draw(canvas)
    draw.text((55, 45), "SKY130 • ROUTED CORE", font=font(42, bold=True), fill="#f4f7fb")
    draw.text((55, 105), "RTL → GDS  •  via-complete final layout", font=font(22), fill="#8fa7c2")
    draw.rounded_rectangle((40, 190, 1140, 1060), radius=24, fill="#05080d", outline="#263956", width=3)
    canvas.paste(layout, (75, 220))
    draw.rounded_rectangle((1170, 190, 1560, 1060), radius=24, fill="#0d1523", outline="#263956", width=3)
    metrics = (
        ("CORE", "1094.220 µm square"), ("UTIL", "~19%"),
        ("TARGET", "10 MHz"), ("LVS", "146 pairs • 0 nonmatches"),
    )
    for index, (label, value) in enumerate(metrics):
        y = 230 + index * 128
        draw_metric_chip(draw, (1200, y, 1530, y + 96), label, value)
    draw.text((1200, 770), "ROUTING LAYERS", font=font(15, bold=True), fill="#8fa7c2")
    for index, (name, color) in enumerate((("M3", "#ffb43b"), ("M4", "#4ee08a"), ("M5", "#8c7cff"))):
        y = 815 + index * 56
        draw.rounded_rectangle((1200, y, 1240, y + 24), radius=6, fill=color)
        draw.text((1260, y), name, font=font(18, bold=True), fill="#f4f7fb")
    draw.text((1200, 1000), "Rendered from the actual\nvia-complete 6_final.gds", font=font(16), fill="#8fa7c2", spacing=6)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, format="PNG", optimize=True)
```

`main()` validates the raw image, creates a 1600 × 1100 RGB canvas, pastes the
actual GDS geometry into `(55, 205, 1125, 1045)`, and draws only outside that
viewport. The right column contains M3/M4/M5 swatches and these exact metrics:

```text
CORE      1094.220 µm square
UTIL      ~19%
TARGET    10 MHz
LVS       146 pairs • 0 nonmatches
```

The footer reads `Rendered from the actual via-complete 6_final.gds`.

- [ ] **Step 5: Add a reproducible Make target**

Add variables and target:

```make
GDS_INPUT ?= openroad/work/results/sky130hd/cpu8/base/6_final.gds
GDS_RAW := $(BUILD_DIR)/final-gds-layout-raw.png
GDS_IMAGE := docs/images/final-gds-layout.png

gds-readme-asset: check-visual-deps
	docker run --rm --platform linux/amd64 \
		-e GDS_INPUT=/project/$(GDS_INPUT) \
		-e GDS_OUTPUT=/project/$(GDS_RAW) \
		-e GDS_WIDTH=1200 -e GDS_HEIGHT=1200 \
		-v "$(CURDIR):/project" -w /project \
		openroad/orfs:latest klayout -b -r /project/tools/render_gds_layout.py
	$(PYTHON) tools/style_gds_visual.py --input $(GDS_RAW) --output $(GDS_IMAGE)
```

- [ ] **Step 6: Render and validate the GDS hero**

Run:

```bash
make PYTHON=python3 gds-readme-asset
python3 tests/check_gds_image.py
```

Expected: a 1600 × 1100 image passes tonal, region, detail, and size checks.

- [ ] **Step 7: Visually inspect the final hero**

Confirm the complete core is visible, the raw geometry has not been cropped or
blurred, the grid is absent, the legend matches M3/M4/M5 colors, and every
metric is legible.

---

### Task 4: Clarify the README and FPGA guide

**Files:**

- Modify: `README.md`
- Modify: `docs/fpga.md`
- Modify: `docs/testing.md`

**Interfaces:**

- Consumes: the regenerated GIF, SVG, and GDS PNG.
- Produces: unambiguous visual captions and reproduction instructions.

- [ ] **Step 1: Label the animated asset**

Immediately before the GIF in both README files, add:

```markdown
### Animated simulation

Watch the hexadecimal PC, red LEDs, cycle count, and memory-status indicators
change as the verified program executes.
```

- [ ] **Step 2: Label the static asset**

Immediately before the SVG in both README files, add:

```markdown
### Static control map

This diagram does not animate; it identifies the physical controls and debug
outputs used by the FPGA wrapper.
```

- [ ] **Step 3: Update the GDS caption**

Describe the image as a styled presentation of the real via-complete final GDS
and retain the core-block/not-packaged-chip limitation.

- [ ] **Step 4: Update regeneration instructions and file references**

Document `make gds-readme-asset`, the new styling tool, the raw build image,
the new dimensions, and the distinction between animated/static FPGA assets.

- [ ] **Step 5: Validate Markdown and terminology**

Run the relative-link checker, GitHub Markdown endpoint check, repository
terminology/path audit, and `git diff --check`.

Expected: all links resolve, Mermaid is accepted, the public-file terminology
and path audit is clean, and no whitespace errors are reported.

---

### Task 5: Complete regression and visual review

**Files:**

- Modify only if verification reveals a defect.

- [ ] **Step 1: Run the complete functional regression**

Run:

```bash
make test
```

Expected: all 15 Verilog suites, assembler, LVS-deck, Basys3 elaboration,
trace, and visual-setup checks pass.

- [ ] **Step 2: Regenerate and test all README visuals**

Run:

```bash
make PYTHON=python3 visual-checks
make PYTHON=python3 gds-readme-asset
python3 tests/check_gds_image.py
```

Expected: all asset checks pass and the GIF contains distinct frames.

- [ ] **Step 3: Inspect final repository state**

Open the GIF, SVG, and PNG; verify README rendering through GitHub's Markdown
endpoint; rerun link, terminology/path, and whitespace checks; then inspect
`git diff --stat` and `git status --short` for unintended files.

- [ ] **Step 4: Present the result for user approval**

Show the final FPGA animation and GDS hero. Keep
`docs/specs/2026-07-18-readme-redesign.md` until the user explicitly approves
this final repository state.

- [ ] **Step 5: After approval, finish directly on main**

Delete the original README redesign specification, update the maintained
internal project map, rerun the complete verification commands, commit all
intended files, and push `main` directly to `origin`.
