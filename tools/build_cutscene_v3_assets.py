#!/usr/bin/env python3
"""Build the modular cutscene UI textures from the generated component sheet."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/ui/cutscene_v3/component_sheet.png"
OUTPUT = ROOT / "assets/ui/cutscene_v3/components"

# Each box encloses one independently generated object on the source sheet.
COMPONENTS = {
    "corner_tl": ((144, 58, 391, 289), (52, 48)),
    "corner_tr": ((863, 58, 1110, 289), (52, 48)),
    "corner_bl": ((144, 371, 391, 603), (52, 48)),
    "corner_br": ((863, 371, 1110, 603), (52, 48)),
    # Repeating edges intentionally have no padding along their tile axis.
    "edge_horizontal": ((112, 782, 802, 816), (96, 5)),
    "edge_vertical": ((1021, 691, 1044, 902), (5, 48)),
    "name_cap_left": ((99, 992, 219, 1165), (28, 40)),
    "name_cap_right": ((451, 992, 572, 1165), (28, 40)),
    "border_gem": ((670, 1047, 867, 1124), (42, 16)),
    "continue_crystal": ((1012, 991, 1097, 1171), (20, 42)),
}


def main() -> None:
    sheet = Image.open(SOURCE).convert("RGBA")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, (box, size) in COMPONENTS.items():
        component = sheet.crop(box)
        component.thumbnail(size, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", size, (0, 0, 0, 0))
        offset = ((size[0] - component.width) // 2, (size[1] - component.height) // 2)
        canvas.alpha_composite(component, offset)
        canvas.save(OUTPUT / f"{name}.png", optimize=True)


if __name__ == "__main__":
    main()
