#!/usr/bin/env python3
"""Render README FPGA visuals from a cycle-level CPU simulation trace."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


WIDTH = 1200
HEIGHT = 675
BOARD = (88, 142, 1112, 632)
PCB_BLUE = "#0b4f85"
PCB_EDGE = "#55a6d8"
SILK = "#dcebf4"
CONNECTOR = "#151b22"
LED_ON = "#ff334d"
LED_OFF = "#481923"

REQUIRED_COLUMNS = {
    "cycle",
    "pc",
    "halt",
    "stall",
    "req",
    "we",
    "addr",
    "zero",
    "page_fault",
    "fault_va",
    "r0",
    "r1",
    "r2",
    "r3",
    "instr",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--trace", type=Path, required=True)
    parser.add_argument("--gif", type=Path, required=True)
    parser.add_argument("--svg", type=Path, required=True)
    return parser.parse_args()


def load_trace(path: Path) -> list[dict[str, int]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        missing = REQUIRED_COLUMNS.difference(reader.fieldnames or [])
        if missing:
            raise ValueError(f"trace is missing columns: {', '.join(sorted(missing))}")

        rows: list[dict[str, int]] = []
        hex_columns = {"pc", "addr", "fault_va", "r0", "r1", "r2", "r3", "instr"}
        for raw in reader:
            rows.append(
                {
                    key: int(value, 16 if key in hex_columns else 10)
                    for key, value in raw.items()
                }
            )

    if not rows:
        raise ValueError("trace contains no CPU states")
    return rows


def meaningful_states(rows: list[dict[str, int]]) -> list[dict[str, int]]:
    selected = [rows[0]]
    keys = ("pc", "halt", "stall", "req", "we", "addr")
    for row in rows[1:]:
        previous = selected[-1]
        if any(row[key] != previous[key] for key in keys):
            selected.append(row)
    if selected[-1] is not rows[-1]:
        selected.append(rows[-1])
    return selected


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


def led_value(row: dict[str, int], memory_view: bool) -> int:
    heartbeat = row["cycle"] & 1
    if memory_view:
        return (
            (row["stall"] << 12)
            | (row["we"] << 11)
            | (row["req"] << 10)
            | (heartbeat << 9)
            | (row["halt"] << 8)
            | row["addr"]
        )
    return (heartbeat << 9) | (row["halt"] << 8) | row["pc"]


def switch_value(memory_view: bool) -> int:
    speed = 0b00
    register_select = 0b00
    debug_view = 0b10 if memory_view else 0b01
    return speed | (register_select << 2) | (debug_view << 4)


SEGMENTS = {
    "0": "abcdef",
    "1": "bc",
    "2": "abdeg",
    "3": "abcdg",
    "4": "bcfg",
    "5": "acdfg",
    "6": "acdefg",
    "7": "abc",
    "8": "abcdefg",
    "9": "abcdfg",
    "A": "abcefg",
    "B": "cdefg",
    "C": "adef",
    "D": "bcdeg",
    "E": "adefg",
    "F": "aefg",
    "H": "bcefg",
    " ": "",
}


def draw_digit(
    draw: ImageDraw.ImageDraw,
    x: int,
    y: int,
    value: str,
    scale: float = 1.0,
) -> None:
    active = SEGMENTS[value]
    on = LED_ON
    off = "#321a20"
    thickness = round(7 * scale)
    length = round(29 * scale)
    segments = {
        "a": (x + thickness, y, x + thickness + length, y + thickness),
        "g": (
            x + thickness,
            y + length + thickness,
            x + thickness + length,
            y + length + 2 * thickness,
        ),
        "d": (
            x + thickness,
            y + 2 * length + 2 * thickness,
            x + thickness + length,
            y + 2 * length + 3 * thickness,
        ),
        "f": (x, y + thickness, x + thickness, y + thickness + length),
        "b": (
            x + length + thickness,
            y + thickness,
            x + length + 2 * thickness,
            y + thickness + length,
        ),
        "e": (
            x,
            y + length + 2 * thickness,
            x + thickness,
            y + 2 * length + 2 * thickness,
        ),
        "c": (
            x + length + thickness,
            y + length + 2 * thickness,
            x + length + 2 * thickness,
            y + 2 * length + 2 * thickness,
        ),
    }
    for name, box in segments.items():
        draw.rounded_rectangle(
            box,
            radius=max(2, thickness // 3),
            fill=on if name in active else off,
        )


def phase_label(row: dict[str, int]) -> str:
    if row["halt"]:
        return "HALT • final architectural state verified"
    if row["stall"] and row["we"]:
        return "STORE • waiting on MMU / cache hierarchy"
    if row["stall"]:
        return "MEMORY • waiting on MMU / cache hierarchy"
    if row["req"]:
        return "MEMORY • request in flight"
    return "EXECUTING • instruction retired"


def draw_background(draw: ImageDraw.ImageDraw) -> None:
    for y in range(HEIGHT):
        ratio = y / (HEIGHT - 1)
        color = (
            8 + int(8 * ratio),
            13 + int(12 * ratio),
            24 + int(20 * ratio),
        )
        draw.line((0, y, WIDTH, y), fill=color)


def draw_mounting_holes(draw: ImageDraw.ImageDraw) -> None:
    for x, y in ((118, 172), (1082, 172), (118, 602), (1082, 602)):
        draw.ellipse(
            (x - 14, y - 14, x + 14, y + 14),
            fill="#071b2b",
            outline="#9ac5dd",
            width=3,
        )
        draw.ellipse((x - 6, y - 6, x + 6, y + 6), fill="#02070b")


def draw_top_connectors(draw: ImageDraw.ImageDraw) -> None:
    # Power, USB, VGA, USB host, and programming connector silhouettes.
    draw.rounded_rectangle(
        (183, 147, 230, 199), radius=5, fill=CONNECTOR, outline="#66747e", width=2
    )
    draw.rounded_rectangle(
        (260, 147, 334, 203), radius=5, fill="#d5dade", outline="#7a858d", width=2
    )
    draw.rounded_rectangle(
        (462, 143, 625, 220), radius=7, fill=CONNECTOR, outline="#9aa6af", width=3
    )
    for pin in range(3):
        draw.ellipse((477 + pin * 62, 153, 489 + pin * 62, 165), fill="#bfc5c9")
    draw.rounded_rectangle(
        (704, 149, 793, 210), radius=5, fill="#d8dde1", outline="#7d878e", width=3
    )
    draw.rectangle((718, 163, 779, 194), fill="#292f35")
    draw.rounded_rectangle(
        (841, 150, 897, 205), radius=4, fill=CONNECTOR, outline="#8b98a2", width=2
    )
    draw.ellipse((1005, 153, 1035, 183), fill="#b7282f", outline="#e7a2a5", width=2)


def draw_side_headers(draw: ImageDraw.ImageDraw) -> None:
    for x in (88, 1074):
        for y in (250, 363):
            draw.rounded_rectangle(
                (x, y, x + 40, y + 82),
                radius=5,
                fill=CONNECTOR,
                outline="#65717b",
                width=2,
            )
            for row in range(4):
                py = y + 12 + row * 18
                draw.rectangle((x + 9, py, x + 31, py + 5), fill="#d8af58")


def draw_fpga_and_chips(draw: ImageDraw.ImageDraw) -> None:
    draw.rounded_rectangle(
        (522, 246, 680, 390), radius=8, fill="#151b22", outline="#8aa6b7", width=3
    )
    for pin in range(9):
        px = 531 + pin * 17
        draw.rectangle((px, 238, px + 7, 245), fill="#aeb7bc")
        draw.rectangle((px, 391, px + 7, 398), fill="#aeb7bc")
    draw.text((601, 301), "XILINX", font=font(13, bold=True), fill="#a8bac6", anchor="mm")
    draw.text((601, 329), "ARTIX-7", font=font(20, bold=True), fill=SILK, anchor="mm")
    draw.text((601, 357), "XC7A35T", font=font(11), fill="#90a8b7", anchor="mm")

    for box in (
        (310, 245, 390, 318),
        (409, 258, 479, 335),
        (710, 244, 780, 312),
        (710, 332, 765, 386),
    ):
        draw.rounded_rectangle(box, radius=5, fill="#1a232b", outline="#7895a7", width=2)
        x0, y0, x1, y1 = box
        for pin in range(4):
            py = y0 + 9 + pin * max(9, (y1 - y0 - 18) // 3)
            draw.rectangle((x0 - 5, py, x0, py + 3), fill="#acb6bd")
            draw.rectangle((x1, py, x1 + 5, py + 3), fill="#acb6bd")


def draw_button_cluster(draw: ImageDraw.ImageDraw) -> None:
    for x, y, label in (
        (856, 303, "U"),
        (856, 389, "D"),
        (813, 346, "L"),
        (899, 346, "R"),
        (856, 346, "C"),
    ):
        draw.rounded_rectangle(
            (x - 19, y - 19, x + 19, y + 19),
            radius=6,
            fill="#171d23",
            outline="#b3c0c8",
            width=2,
        )
        draw.rectangle((x - 10, y - 10, x + 10, y + 10), fill="#252d34")
        draw.text((x, y), label, font=font(11, bold=True), fill=SILK, anchor="mm")


def draw_switch_bank(draw: ImageDraw.ImageDraw, bits: int) -> None:
    for position in range(16):
        bit = 15 - position
        x = 132 + position * 59
        active = (bits >> bit) & 1
        draw.text((x + 15, 544), str(bit), font=font(9), fill="#a7c7d9", anchor="mm")
        draw.rounded_rectangle(
            (x, 550, x + 30, 608),
            radius=4,
            fill="#10161b",
            outline="#75818a",
            width=2,
        )
        paddle_y = 557 if active else 580
        draw.rounded_rectangle(
            (x + 5, paddle_y, x + 25, paddle_y + 20),
            radius=3,
            fill="#3a444c",
            outline="#697781",
        )


def draw_led_bank(draw: ImageDraw.ImageDraw, led_bits: int) -> None:
    for position in range(16):
        bit = 15 - position
        x = 147 + position * 59
        active = (led_bits >> bit) & 1
        if active:
            draw.ellipse((x - 12, 510, x + 12, 534), fill="#7c1524")
        draw.ellipse(
            (x - 7, 515, x + 7, 529),
            fill=LED_ON if active else LED_OFF,
            outline="#ff9aaa" if active else "#7a3440",
            width=2,
        )


def draw_board_labels(draw: ImageDraw.ImageDraw) -> None:
    draw.text((159, 215), "DIGILENT", font=font(15, bold=True), fill=SILK)
    draw.text((925, 213), "BASYS 3", font=font(25, bold=True), fill=SILK)
    draw.text((601, 412), "FPGA", font=font(11), fill="#a8c8dc", anchor="mm")
    draw.text((856, 422), "USER BUTTONS", font=font(10), fill="#a8c8dc", anchor="mm")
    draw.text((600, 503), "LED[15:0]", font=font(11, bold=True), fill="#b9d7e7", anchor="mm")


def draw_display(draw: ImageDraw.ImageDraw, row: dict[str, int]) -> None:
    draw.rounded_rectangle(
        (244, 355, 486, 471), radius=7, fill="#11151a", outline="#7d8991", width=3
    )
    for index in range(4):
        x = 260 + index * 56
        draw.rounded_rectangle((x, 365, x + 49, 456), radius=4, fill="#1a181c")
    display = f"H {row['pc']:02X}" if row["halt"] else f"  {row['pc']:02X}"
    for index, character in enumerate(display):
        draw_digit(draw, 266 + index * 56, 373, character, 0.9)
    draw.text((365, 480), "PC / HALT DISPLAY", font=font(10, bold=True), fill="#b8d4e4", anchor="mm")


def draw_status_pill(
    draw: ImageDraw.ImageDraw,
    x: int,
    label: str,
    active: int,
) -> None:
    fill = "#b91f38" if active else "#182334"
    outline = "#ff6378" if active else "#31425b"
    draw.rounded_rectangle((x, 76, x + 92, 110), radius=17, fill=fill, outline=outline, width=2)
    draw.text((x + 46, 93), label, font=font(12, bold=True), fill="#ffffff" if active else "#8fa0b5", anchor="mm")


def render_frame(row: dict[str, int]) -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), "#080d18")
    draw = ImageDraw.Draw(image)
    draw_background(draw)

    draw.text((42, 25), "BASYS3 • 8-BIT CPU", font=font(27, bold=True), fill="#f6f8fb")
    draw.rounded_rectangle((389, 24, 650, 56), radius=16, fill="#14253a", outline="#2d789d", width=2)
    draw.text((519, 40), "ANIMATED CPU TRACE", font=font(13, bold=True), fill="#79d9ff", anchor="mm")
    draw.text((42, 72), phase_label(row), font=font(17, bold=True), fill="#dce8f3")
    draw.text(
        (42, 102),
        f"cycle {row['cycle']:02d}   instruction 0x{row['instr']:04X}   "
        f"R0 {row['r0']:02X}  R1 {row['r1']:02X}  R2 {row['r2']:02X}  R3 {row['r3']:02X}",
        font=font(14),
        fill="#8fa6bd",
    )
    for index, (label, active) in enumerate(
        (("REQ", row["req"]), ("WRITE", row["we"]), ("STALL", row["stall"]), ("HALT", row["halt"]))
    ):
        draw_status_pill(draw, 780 + index * 100, label, active)

    # Board shadow and PCB.
    draw.rounded_rectangle((76, 151, 1124, 645), radius=24, fill="#02060b")
    draw.rounded_rectangle(BOARD, radius=20, fill=PCB_BLUE, outline=PCB_EDGE, width=4)
    for y in range(171, 620, 34):
        draw.line((110, y, 1090, y), fill="#0c568d", width=1)

    memory_view = bool(row["stall"] or row["req"] or row["we"])
    draw_mounting_holes(draw)
    draw_top_connectors(draw)
    draw_side_headers(draw)
    draw_fpga_and_chips(draw)
    draw_button_cluster(draw)
    draw_display(draw, row)
    draw_led_bank(draw, led_value(row, memory_view))
    draw_switch_bank(draw, switch_value(memory_view))
    draw_board_labels(draw)

    draw.text(
        (1047, 604),
        "simulation-derived",
        font=font(10),
        fill="#9dc4da",
        anchor="rm",
    )
    return image


def write_gif(rows: list[dict[str, int]], output: Path) -> int:
    states = meaningful_states(rows)
    frames = [render_frame(row) for row in states]
    durations = [1800 if row["halt"] else 700 if row["stall"] else 420 for row in states]
    output.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(
        output,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
        disposal=2,
    )
    return len(frames)


def svg_text() -> str:
    led_marks = "\n".join(
        f'<circle data-role="led" cx="{260 + index * 57}" cy="542" r="8" class="led"/>'
        f'<text x="{260 + index * 57}" y="523" class="tiny">{15 - index}</text>'
        for index in range(16)
    )
    switch_marks = "\n".join(
        f'<g data-role="switch"><rect x="{245 + index * 57}" y="565" width="30" height="56" rx="4" class="switch"/>'
        f'<rect x="{251 + index * 57}" y="591" width="18" height="22" rx="3" class="paddle"/>'
        f'<text x="{260 + index * 57}" y="635" class="tiny">{15 - index}</text></g>'
        for index in range(16)
    )
    header_pins = "\n".join(
        f'<rect x="{205 + column * 10}" y="278" width="6" height="4" class="pin"/>'
        for column in range(3)
    )
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1400 800" role="img" aria-labelledby="title desc">
<title id="title">Static control map for the Basys3 8-bit CPU wrapper</title>
<desc id="desc">A realistic static Basys3 diagram labeling reset, single step, speed selection, register selection, debug selection, LEDs, and the PC and HALT display.</desc>
<defs>
  <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%"><feDropShadow dx="0" dy="12" stdDeviation="12" flood-color="#000814" flood-opacity="0.75"/></filter>
  <marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto"><path d="M0,0 L0,6 L9,3 z" fill="#64d7ff"/></marker>
</defs>
<style>
  .board {{ fill:#0b4f85; stroke:#55a6d8; stroke-width:4; }}
  .connector {{ fill:#151b22; stroke:#74838e; stroke-width:2; }}
  .chip {{ fill:#151b22; stroke:#7895a7; stroke-width:2; }}
  .pin {{ fill:#d8af58; }}
  .display {{ fill:#11151a; stroke:#87939b; stroke-width:3; }}
  .digit {{ fill:#321a20; stroke:#62313b; stroke-width:2; }}
  .led {{ fill:#481923; stroke:#9c5361; stroke-width:2; }}
  .switch {{ fill:#10161b; stroke:#75818a; stroke-width:2; }}
  .paddle {{ fill:#3a444c; }}
  .button {{ fill:#171d23; stroke:#b3c0c8; stroke-width:2; }}
  .silk {{ fill:#dcebf4; font:700 18px Arial,sans-serif; }}
  .title {{ fill:#f6f8fb; font:700 34px Arial,sans-serif; }}
  .subtitle {{ fill:#91a9c1; font:18px Arial,sans-serif; }}
  .callout {{ fill:none; stroke:#64d7ff; stroke-width:3; marker-end:url(#arrow); }}
  .calloutBox {{ fill:#101b2b; stroke:#2e789c; stroke-width:2; }}
  .calloutTitle {{ fill:#f6f8fb; font:700 17px Arial,sans-serif; text-anchor:middle; }}
  .calloutDetail {{ fill:#9ec2d8; font:14px Arial,sans-serif; text-anchor:middle; }}
  .tiny {{ fill:#a7c7d9; font:10px Arial,sans-serif; text-anchor:middle; }}
</style>
<rect width="1400" height="800" fill="#080d18"/>
<text x="70" y="58" class="title">STATIC CONTROL MAP</text>
<text x="70" y="90" class="subtitle">Basys3 wrapper inputs and debug outputs • static reference</text>

<rect x="174" y="144" width="1052" height="512" rx="24" fill="#02060b" filter="url(#shadow)"/>
<rect x="184" y="130" width="1032" height="512" rx="20" class="board"/>
<circle cx="214" cy="160" r="14" fill="#071b2b" stroke="#9ac5dd" stroke-width="3"/>
<circle cx="1186" cy="160" r="14" fill="#071b2b" stroke="#9ac5dd" stroke-width="3"/>
<circle cx="214" cy="612" r="14" fill="#071b2b" stroke="#9ac5dd" stroke-width="3"/>
<circle cx="1186" cy="612" r="14" fill="#071b2b" stroke="#9ac5dd" stroke-width="3"/>

<rect x="465" y="130" width="165" height="74" rx="7" class="connector"/>
<rect x="710" y="138" width="88" height="61" rx="5" fill="#d8dde1" stroke="#7d878e" stroke-width="3"/>
<rect x="842" y="139" width="58" height="56" rx="4" class="connector"/>
<circle cx="1050" cy="153" r="15" fill="#b7282f" stroke="#e7a2a5" stroke-width="2"/>
<rect x="184" y="252" width="42" height="82" rx="5" class="connector"/>
<rect x="184" y="365" width="42" height="82" rx="5" class="connector"/>
<rect x="1174" y="252" width="42" height="82" rx="5" class="connector"/>
<rect x="1174" y="365" width="42" height="82" rx="5" class="connector"/>
{header_pins}

<rect x="570" y="246" width="158" height="142" rx="8" class="chip"/>
<text x="649" y="310" class="silk" text-anchor="middle">ARTIX-7</text>
<text x="649" y="340" class="tiny">XC7A35T</text>
<rect x="362" y="252" width="78" height="72" rx="5" class="chip"/>
<rect x="460" y="264" width="70" height="76" rx="5" class="chip"/>
<rect x="750" y="250" width="72" height="68" rx="5" class="chip"/>
<text x="246" y="205" class="silk">DIGILENT</text>
<text x="1010" y="210" class="silk">BASYS 3</text>

<rect x="332" y="360" width="242" height="116" rx="7" class="display"/>
<rect x="347" y="372" width="48" height="88" rx="4" class="digit"/>
<rect x="401" y="372" width="48" height="88" rx="4" class="digit"/>
<rect x="455" y="372" width="48" height="88" rx="4" class="digit"/>
<rect x="509" y="372" width="48" height="88" rx="4" class="digit"/>
<text x="453" y="495" class="tiny">PC / HALT</text>

<g id="buttons">
  <rect x="900" y="300" width="40" height="40" rx="7" class="button"/><text x="920" y="325" class="tiny">U</text>
  <rect x="900" y="388" width="40" height="40" rx="7" class="button"/><text x="920" y="413" class="tiny">D</text>
  <rect x="856" y="344" width="40" height="40" rx="7" class="button"/><text x="876" y="369" class="tiny">L</text>
  <rect x="944" y="344" width="40" height="40" rx="7" class="button"/><text x="964" y="369" class="tiny">btnR</text>
  <rect x="900" y="344" width="40" height="40" rx="7" class="button"/><text x="920" y="369" class="tiny">btnC</text>
</g>

<text x="700" y="513" class="tiny">LED[15:0]</text>
{led_marks}
{switch_marks}

<rect x="34" y="238" width="180" height="74" rx="12" class="calloutBox"/>
<text x="124" y="266" class="calloutTitle">LED[15:0]</text>
<text x="124" y="291" class="calloutDetail">debug output</text>
<path d="M214 275 C245 300 230 470 260 542" class="callout"/>

<rect x="650" y="32" width="260" height="68" rx="12" class="calloutBox"/>
<text x="780" y="59" class="calloutTitle">PC / HALT display</text>
<text x="780" y="83" class="calloutDetail">H + 8-bit program counter</text>
<path d="M740 100 C650 155 520 260 453 350" class="callout"/>

<rect x="1050" y="45" width="250" height="72" rx="12" class="calloutBox"/>
<text x="1175" y="72" class="calloutTitle">btnC / btnR</text>
<text x="1175" y="97" class="calloutDetail">reset / single-step</text>
<path d="M1110 117 C1080 180 1020 260 965 350" class="callout"/>

<rect x="280" y="690" width="230" height="72" rx="12" class="calloutBox"/>
<text x="395" y="717" class="calloutTitle">SW5:SW4</text>
<text x="395" y="742" class="calloutDetail">debug-view selection</text>
<path d="M395 690 C540 650 760 638 845 612" class="callout"/>

<rect x="590" y="690" width="220" height="72" rx="12" class="calloutBox"/>
<text x="700" y="717" class="calloutTitle">SW3:SW2</text>
<text x="700" y="742" class="calloutDetail">register selection</text>
<path d="M700 690 C790 650 910 638 959 612" class="callout"/>

<rect x="890" y="690" width="230" height="72" rx="12" class="calloutBox"/>
<text x="1005" y="717" class="calloutTitle">SW1:SW0</text>
<text x="1005" y="742" class="calloutDetail">speed / single-step</text>
<path d="M1005 690 C1035 660 1060 636 1073 612" class="callout"/>
</svg>
'''


def write_svg(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(svg_text(), encoding="utf-8")


def main() -> None:
    args = parse_args()
    rows = load_trace(args.trace)
    frame_count = write_gif(rows, args.gif)
    write_svg(args.svg)
    print(f"Rendered {frame_count} FPGA frames to {args.gif} and controls to {args.svg}")


if __name__ == "__main__":
    main()
