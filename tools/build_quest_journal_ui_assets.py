#!/usr/bin/env python3
"""Extract and normalize the generated, theme-neutral Quest Journal UI kit."""

from pathlib import Path

from PIL import Image, ImageOps


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/ui/quest_journal_v1/component_sheet_alpha.png"
OUTPUT = ROOT / "assets/ui/quest_journal_v1/components"

# Explicit source boxes avoid neighboring generated components that cross nominal
# grid boundaries. All values are in the original 1254 x 1254 sheet.
BOXES = {
    "corner_source": (66, 56, 233, 217),
    "edge_horizontal": (41, 379, 344, 409),
    "edge_vertical": (507, 291, 535, 505),
    "panel_fill": (667, 304, 853, 490),
    "divider": (940, 379, 1200, 419),
    "tab_normal": (31, 581, 294, 706),
    "tab_selected": (330, 581, 593, 706),
    "row_normal": (630, 583, 940, 703),
    "row_selected": (940, 799, 1220, 922),
    "icon_main": (115, 790, 280, 943),
    "icon_side": (390, 790, 555, 943),
    "icon_hidden": (667, 790, 833, 943),
    "icon_completed": (943, 790, 1108, 943),
    "icon_journal": (115, 1022, 280, 1177),
    "icon_hint": (390, 1022, 554, 1177),
    "icon_xp": (667, 1022, 831, 1176),
    "icon_unknown": (943, 1022, 1106, 1177),
}


def alpha_trim(image: Image.Image) -> Image.Image:
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError("empty source crop")
    return image.crop(bounds)


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


def save(image: Image.Image, name: str, size: tuple[int, int], contain: bool = False) -> None:
    output = resize_contain(image, size, 2 if contain else 0) if contain else image.resize(size, Image.Resampling.NEAREST)
    output.save(OUTPUT / f"{name}.png")
    print(f"wrote {name}.png {size[0]}x{size[1]}")


def main() -> None:
    sheet = Image.open(SOURCE).convert("RGBA")
    if sheet.size != (1254, 1254):
        raise RuntimeError(f"unexpected component sheet size: {sheet.size}")
    OUTPUT.mkdir(parents=True, exist_ok=True)

    corner = alpha_trim(sheet.crop(BOXES["corner_source"]))
    save(corner, "corner_tl", (48, 48), contain=True)
    save(ImageOps.mirror(corner), "corner_tr", (48, 48), contain=True)
    save(ImageOps.flip(corner), "corner_bl", (48, 48), contain=True)
    save(ImageOps.flip(ImageOps.mirror(corner)), "corner_br", (48, 48), contain=True)

    horizontal = alpha_trim(sheet.crop(BOXES["edge_horizontal"]))
    center_x = horizontal.width // 2
    save(horizontal.crop((center_x, 0, center_x + 1, horizontal.height)), "edge_horizontal", (72, 2))
    vertical = alpha_trim(sheet.crop(BOXES["edge_vertical"]))
    center_y = vertical.height // 2
    save(vertical.crop((0, center_y, vertical.width, center_y + 1)), "edge_vertical", (2, 48))
    save(alpha_trim(sheet.crop(BOXES["panel_fill"])), "panel_fill", (16, 16))
    save(alpha_trim(sheet.crop(BOXES["divider"])), "divider", (120, 6))

    save(alpha_trim(sheet.crop(BOXES["tab_normal"])), "tab_normal", (120, 32))
    save(alpha_trim(sheet.crop(BOXES["tab_selected"])), "tab_selected", (120, 32))
    save(alpha_trim(sheet.crop(BOXES["row_normal"])), "row_normal", (144, 42))
    save(alpha_trim(sheet.crop(BOXES["row_selected"])), "row_selected", (144, 42))

    for name in (
        "icon_main", "icon_side", "icon_hidden", "icon_completed",
        "icon_journal", "icon_hint", "icon_xp", "icon_unknown",
    ):
        save(alpha_trim(sheet.crop(BOXES[name])), name, (32, 32), contain=True)


if __name__ == "__main__":
    main()
