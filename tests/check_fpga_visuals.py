#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys
import xml.etree.ElementTree as ET

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
TRACE = ROOT / "build" / "fpga-demo-trace.csv"
GIF = ROOT / "docs" / "images" / "fpga-demo.gif"
SVG = ROOT / "docs" / "images" / "fpga-controls.svg"
RENDERER = ROOT / "tools" / "render_fpga_visuals.py"


subprocess.run(
    [
        sys.executable,
        str(RENDERER),
        "--trace",
        str(TRACE),
        "--gif",
        str(GIF),
        "--svg",
        str(SVG),
    ],
    cwd=ROOT,
    check=True,
)

with Image.open(GIF) as image:
    assert image.format == "GIF", image.format
    assert image.size == (1200, 675), image.size
    assert image.n_frames >= 8, image.n_frames
    assert image.n_frames <= 40, image.n_frames
    assert image.info.get("loop") == 0, image.info.get("loop")
    assert image.info.get("duration", 0) > 0, image.info.get("duration")
    frame_count = image.n_frames

    frame_hashes = set()
    for frame_index in range(image.n_frames):
        image.seek(frame_index)
        frame_hashes.add(hash(image.convert("RGB").tobytes()))
    assert len(frame_hashes) >= 4, len(frame_hashes)

    image.seek(0)
    first = image.convert("RGB")
    image.seek(image.n_frames - 1)
    last = image.convert("RGB")

    def count_pixels(rgb, predicate):
        pixels = (
            rgb.get_flattened_data()
            if hasattr(rgb, "get_flattened_data")
            else rgb.getdata()
        )
        return sum(1 for pixel in pixels if predicate(pixel))

    assert count_pixels(first, lambda pixel: pixel[2] > 80 and pixel[2] > pixel[0] * 1.4) > 80_000
    assert count_pixels(last, lambda pixel: pixel[0] > 170 and pixel[1] < 100) > 150
    assert first.tobytes() != last.tobytes()

assert GIF.stat().st_size < 5_000_000, GIF.stat().st_size

tree = ET.parse(SVG)
root = tree.getroot()
assert root.attrib.get("viewBox") == "0 0 1400 800", root.attrib
svg_text = " ".join(root.itertext())
assert len(root.findall(".//*[@data-role='led']")) == 16
assert len(root.findall(".//*[@data-role='switch']")) == 16
for label in (
    "STATIC CONTROL MAP",
    "btnC",
    "btnR",
    "SW1:SW0",
    "SW3:SW2",
    "SW5:SW4",
    "LED[15:0]",
    "PC / HALT display",
    "BASYS 3",
):
    assert label in svg_text, label

print(
    f"PASS: FPGA visuals contain {frame_count} distinct trace-driven frames, "
    f"a 1200x675 Basys3 canvas, and a complete static control map"
)
