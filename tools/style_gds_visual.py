#!/usr/bin/env python3
"""Frame an actual KLayout GDS render as the README's portfolio hero."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


WIDTH = 1600
HEIGHT = 1100
DIE_OUTER = (125, 165, 1025, 1065)
DIE_FACE = (150, 190, 1000, 1040)
LAYOUT_SIZE = (800, 800)
LAYOUT_ORIGIN = (175, 215)
METRICS_PANEL = (1065, 190, 1560, 1060)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    return parser.parse_args()


def font(size: int, bold: bool = False) -> ImageFont.ImageFont:
    candidates = [
        Path(
            "/System/Library/Fonts/Supplemental/Arial Bold.ttf"
            if bold
            else "/System/Library/Fonts/Supplemental/Arial.ttf"
        ),
        Path(
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
            if bold
            else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
        ),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def wafer_background(size: tuple[int, int]) -> Image.Image:
    width, height = size
    image = Image.new("RGB", size)
    draw = ImageDraw.Draw(image)
    for y in range(height):
        ratio = y / max(height - 1, 1)
        color = (
            7 + int(8 * ratio),
            12 + int(12 * ratio),
            23 + int(20 * ratio),
        )
        draw.line((0, y, width, y), fill=color)

    # A restrained wafer silhouette gives the die physical context without
    # pretending the core has a package, padframe, or bond wires.
    draw.ellipse(
        (-95, 115, 1105, 1315),
        fill="#121821",
        outline="#29323e",
        width=5,
    )
    draw.ellipse((-56, 154, 1066, 1276), outline="#1d2631", width=3)
    draw.arc((-95, 115, 1105, 1315), 205, 322, fill="#3a4551", width=3)
    return image


def draw_die_shadow(canvas: Image.Image) -> None:
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    x0, y0, x1, y1 = DIE_OUTER
    shadow_draw.rounded_rectangle(
        (x0 + 22, y0 + 28, x1 + 28, y1 + 34),
        radius=20,
        fill=(0, 0, 0, 205),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    canvas.paste(shadow, (0, 0), shadow)


def draw_die_frame(draw: ImageDraw.ImageDraw) -> None:
    x0, y0, x1, y1 = DIE_OUTER
    fx0, fy0, fx1, fy1 = DIE_FACE

    draw.rectangle(DIE_OUTER, fill="#6d7680", outline="#e4e9ed", width=2)
    draw.polygon(
        ((x0, y0), (x1, y0), (fx1, fy0), (fx0, fy0)),
        fill="#c9d1d7",
    )
    draw.polygon(
        ((x0, y0), (fx0, fy0), (fx0, fy1), (x0, y1)),
        fill="#929ca5",
    )
    draw.polygon(
        ((x0, y1), (fx0, fy1), (fx1, fy1), (x1, y1)),
        fill="#394149",
    )
    draw.polygon(
        ((x1, y0), (fx1, fy0), (fx1, fy1), (x1, y1)),
        fill="#2b333c",
    )
    draw.line((x0 + 4, y0 + 4, x1 - 4, y0 + 4), fill="#f6f8fa", width=2)
    draw.line((x0 + 4, y0 + 4, x0 + 4, y1 - 4), fill="#bbc5cc", width=2)
    draw.rectangle(DIE_FACE, fill="#070a0f", outline="#596573", width=2)

    # These highlights stay on the silicon border; the actual GDS viewport is
    # pasted afterward and remains completely untouched.
    draw.line((fx0 + 3, fy0 + 3, fx1 - 3, fy0 + 3), fill="#87939d", width=2)
    draw.line((fx0 + 3, fy0 + 3, fx0 + 3, fy1 - 3), fill="#5d6872", width=2)


def fit_layout(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    fitted = image.convert("RGB").copy()
    # KLayout's offscreen renderer leaves a narrow annotation border around
    # the fitted core. Crop only that border; the white core boundary remains.
    margin_x = max(1, round(fitted.width * 0.02))
    margin_y = max(1, round(fitted.height * 0.02))
    fitted = fitted.crop(
        (margin_x, margin_y, fitted.width - margin_x, fitted.height - margin_y)
    )
    fitted.thumbnail(size, Image.Resampling.LANCZOS)
    result = Image.new("RGB", size, "#03060a")
    result.paste(
        fitted,
        ((size[0] - fitted.width) // 2, (size[1] - fitted.height) // 2),
    )
    return result


def draw_metric_chip(
    draw: ImageDraw.ImageDraw,
    box: tuple[int, int, int, int],
    label: str,
    value: str,
    value_size: int = 20,
) -> None:
    draw.rounded_rectangle(
        box,
        radius=14,
        fill="#151f31",
        outline="#304466",
        width=2,
    )
    x0, y0, _, _ = box
    draw.text((x0 + 18, y0 + 14), label, font=font(14, bold=True), fill="#65d9ec")
    draw.text(
        (x0 + 18, y0 + 43),
        value,
        font=font(value_size, bold=True),
        fill="#f4f7fb",
    )


def draw_layer_legend(draw: ImageDraw.ImageDraw) -> None:
    draw.text((1100, 774), "ROUTING LAYERS", font=font(15, bold=True), fill="#8fa7c2")
    for index, (name, color, detail) in enumerate(
        (
            ("M3", "#ffb43b", "horizontal routes"),
            ("M4", "#4ee08a", "vertical grid"),
            ("M5", "#8c7cff", "top power grid"),
        )
    ):
        y = 814 + index * 54
        draw.rounded_rectangle((1100, y, 1142, y + 24), radius=6, fill=color)
        draw.text((1160, y - 1), name, font=font(18, bold=True), fill="#f4f7fb")
        draw.text((1202, y + 2), detail, font=font(13), fill="#8fa7c2")


def main() -> None:
    args = parse_args()
    if not args.input.is_file():
        raise FileNotFoundError(args.input)

    with Image.open(args.input) as source:
        if source.width < 512 or source.height < 512:
            raise ValueError("raw GDS render must be at least 512x512")
        layout = fit_layout(source, LAYOUT_SIZE)

    canvas = wafer_background((WIDTH, HEIGHT))
    draw = ImageDraw.Draw(canvas)

    draw.text((55, 38), "SKY130 • BARE CORE DIE", font=font(42, bold=True), fill="#f4f7fb")
    draw.text(
        (55, 99),
        "RTL → GDS  •  via-complete final layout",
        font=font(22),
        fill="#8fa7c2",
    )
    draw.rounded_rectangle(
        (1240, 46, 1545, 98),
        radius=26,
        fill="#10243a",
        outline="#2f9dc3",
        width=2,
    )
    draw.text(
        (1392, 72),
        "UNPACKAGED CORE BLOCK",
        font=font(14, bold=True),
        fill="#70def6",
        anchor="mm",
    )

    draw_die_shadow(canvas)
    draw = ImageDraw.Draw(canvas)
    draw_die_frame(draw)
    canvas.paste(layout, LAYOUT_ORIGIN)
    draw = ImageDraw.Draw(canvas)
    draw.rectangle(
        (*LAYOUT_ORIGIN, LAYOUT_ORIGIN[0] + LAYOUT_SIZE[0], LAYOUT_ORIGIN[1] + LAYOUT_SIZE[1]),
        outline="#aab3bb",
        width=2,
    )

    draw.rounded_rectangle(
        METRICS_PANEL,
        radius=24,
        fill="#0d1523",
        outline="#263956",
        width=3,
    )
    metrics = (
        ("CORE", "1094.220 µm square", 19),
        ("UTILIZATION", "~19%", 22),
        ("TIMING TARGET", "10 MHz", 22),
        ("PROJECT-DECK LVS", "146 pairs • 0 nonmatches", 17),
    )
    for index, (label, value, value_size) in enumerate(metrics):
        y = 230 + index * 128
        draw_metric_chip(
            draw,
            (1100, y, 1530, y + 96),
            label,
            value,
            value_size,
        )

    draw_layer_legend(draw)
    draw.text(
        (1100, 997),
        "Rendered from the actual\nvia-complete 6_final.gds",
        font=font(15),
        fill="#8fa7c2",
        spacing=5,
    )

    args.output.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(args.output, format="PNG", optimize=True)
    print(f"Styled {args.input} as {args.output} at {WIDTH}x{HEIGHT}")


if __name__ == "__main__":
    main()
