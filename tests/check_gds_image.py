#!/usr/bin/env python3
from pathlib import Path

from PIL import Image, ImageStat


ROOT = Path(__file__).resolve().parents[1]
IMAGE = ROOT / "docs" / "images" / "final-gds-layout.png"


with Image.open(IMAGE) as layout:
    assert layout.format == "PNG", layout.format
    assert layout.size == (1600, 1100), layout.size
    rgb = layout.convert("RGB")
    statistics = ImageStat.Stat(rgb)
    extrema = statistics.extrema
    assert all(high - low > 40 for low, high in extrema), extrema
    assert sum(statistics.mean) / 3 < 120, statistics.mean

    header = rgb.crop((0, 0, 1600, 190))
    viewport = rgb.crop((175, 215, 975, 1015))
    top_bevel = rgb.crop((125, 165, 1025, 215))
    wafer = rgb.crop((20, 220, 115, 1000))
    legend = rgb.crop((1060, 190, 1570, 1060))
    assert sum(ImageStat.Stat(header).mean) / 3 < 80
    viewport_extrema = ImageStat.Stat(viewport).extrema
    assert max(high - low for low, high in viewport_extrema) > 120
    assert sum(ImageStat.Stat(top_bevel).mean) / 3 > 45
    assert sum(ImageStat.Stat(wafer).mean) / 3 < 45
    assert sum(ImageStat.Stat(legend).mean) / 3 > 18

size = IMAGE.stat().st_size
assert 100_000 < size < 10_000_000, size

print(
    "PASS: final GDS hero presents the real layout as a detailed "
    f"1600x1100 bare-die PNG ({size:,} bytes)"
)
