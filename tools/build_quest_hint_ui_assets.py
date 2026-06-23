#!/usr/bin/env python3
"""Extract the modular quest/hint UI kit from its generated component sheet."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/ui/quest_hint_v1/component_sheet_alpha.png"
OUTPUT = ROOT / "assets/ui/quest_hint_v1/components"

# The generated sheet is a strict 4 x 5 grid. Keeping the grid fixed makes every
# mirrored corner share the same source-cell scale before final normalization.
COLS = (0, 313, 627, 940, 1254)
ROWS = (0, 300, 570, 780, 995, 1254)

ASSETS = {
    "quest_corner_tl": ((0, 0), (48, 48)),
    "quest_corner_tr": ((1, 0), (48, 48)),
    "quest_corner_bl": ((2, 0), (48, 48)),
    "quest_corner_br": ((3, 0), (48, 48)),
    "hint_corner_tl": ((0, 1), (48, 48)),
    "hint_corner_tr": ((1, 1), (48, 48)),
    "hint_corner_bl": ((2, 1), (48, 48)),
    "hint_corner_br": ((3, 1), (48, 48)),
    "quest_edge_horizontal": ((0, 2), (72, 2)),
    "quest_edge_vertical": ((1, 2), (2, 48)),
    "hint_edge_horizontal": ((2, 2), (72, 2)),
    "hint_edge_vertical": ((3, 2), (2, 48)),
    "panel_fill": ((0, 3), (16, 16)),
    "divider": ((1, 3), (80, 2)),
    "progress_frame": ((2, 3), (112, 16)),
    "progress_fill": ((3, 3), (108, 10)),
    "icon_quest": ((0, 4), (28, 28)),
    "icon_hint": ((1, 4), (28, 28)),
    "icon_journal": ((2, 4), (28, 28)),
    "icon_collapse": ((3, 4), (28, 28)),
}

STRETCH_TO_BOUNDS = {
    "quest_edge_horizontal",
    "quest_edge_vertical",
    "hint_edge_horizontal",
    "hint_edge_vertical",
    "panel_fill",
    "divider",
    "progress_frame",
    "progress_fill",
}


def cell_bounds(column: int, row: int) -> tuple[int, int, int, int]:
    return COLS[column], ROWS[row], COLS[column + 1], ROWS[row + 1]


def trimmed_cell(sheet: Image.Image, column: int, row: int) -> Image.Image:
    cell = sheet.crop(cell_bounds(column, row))
    bounds = cell.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError(f"component cell {column},{row} is empty")
    return cell.crop(bounds)


def resize_contain(image: Image.Image, size: tuple[int, int], padding: int = 0) -> Image.Image:
    width, height = size
    available = (max(1, width - padding * 2), max(1, height - padding * 2))
    scale = min(available[0] / image.width, available[1] / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.NEAREST,
    )
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    output.alpha_composite(resized, ((width - resized.width) // 2, (height - resized.height) // 2))
    return output


def main() -> None:
    sheet = Image.open(SOURCE).convert("RGBA")
    if sheet.size != (1254, 1254):
        raise RuntimeError(f"unexpected component sheet size: {sheet.size}")
    OUTPUT.mkdir(parents=True, exist_ok=True)

    for name, (cell, size) in ASSETS.items():
        component = trimmed_cell(sheet, *cell)
        # Generated straight pieces include subtly shaded end caps. A one-pixel
        # center slice removes those caps and guarantees mathematically seamless
        # repetition at any panel length.
        if name.endswith("edge_horizontal") or name == "divider":
            center = component.width // 2
            component = component.crop((center, 0, center + 1, component.height))
        elif name.endswith("edge_vertical"):
            center = component.height // 2
            component = component.crop((0, center, component.width, center + 1))
        if name in STRETCH_TO_BOUNDS:
            output = component.resize(size, Image.Resampling.NEAREST)
        else:
            padding = 2 if name.startswith("icon_") else 0
            output = resize_contain(component, size, padding)
        output.save(OUTPUT / f"{name}.png")
        print(f"wrote {name}.png {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
