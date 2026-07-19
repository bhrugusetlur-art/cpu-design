#!/usr/bin/env python3
"""KLayout batch script for rendering the final routed core."""

import os
from pathlib import Path

import pya


def required_environment(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"missing required environment variable: {name}")
    return value


input_path = Path(required_environment("GDS_INPUT"))
output_path = Path(required_environment("GDS_OUTPUT"))
width = int(os.environ.get("GDS_WIDTH", "1600"))
height = int(os.environ.get("GDS_HEIGHT", "1600"))

if not input_path.is_file():
    raise RuntimeError(f"GDS input does not exist: {input_path}")
if width < 256 or height < 256:
    raise RuntimeError("render dimensions must be at least 256x256")

output_path.parent.mkdir(parents=True, exist_ok=True)

view = pya.LayoutView(False, None, pya.LayoutView.LV_NoGrid)
view.load_layout(str(input_path), False)
view.add_missing_layers()

# Show the upper interconnect stack and core boundary.  Lower device and local
# routing layers are intentionally hidden: displaying every mask at once makes
# a routed digital core look like a bright block instead of revealing its
# power grid and major routes.
layer_colors = {
    67: 0xA0A8B8,  # local interconnect
    68: 0x31C3FF,  # metal 1
    69: 0xFF4FD8,  # metal 2
    70: 0xFFB43B,  # metal 3
    71: 0x4EE08A,  # metal 4
    72: 0x8C7CFF,  # metal 5
    235: 0xD7DEE9,  # core boundary
}
visible_datatypes = {16, 20, 44}

for layer in view.each_layer():
    stream_layer = layer.source_layer
    stream_datatype = layer.source_datatype
    layer.visible = (
        (stream_layer in range(70, 73) and stream_datatype in visible_datatypes)
        or (stream_layer == 235 and stream_datatype == 4)
    )
    if layer.visible:
        color = layer_colors[stream_layer]
        layer.fill_color = color
        layer.frame_color = color
        layer.transparent = False
        layer.fill_brightness = 0
        layer.frame_brightness = 0

view.max_hier()
view.zoom_fit()
view.save_image_with_options(str(output_path), width, height, 2, 2, 0)

if not output_path.is_file():
    raise RuntimeError(f"KLayout did not create the image: {output_path}")

print(f"Rendered {input_path} to {output_path} at {width}x{height}")
