#!/usr/bin/env python3
"""Extract generated tracker controls into stable, transparent 28px game assets."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/ui/quest_hint_v1/tracker_controls_frameless_v4_alpha.png"
OUTPUT = ROOT / "assets/ui/quest_hint_v1/components"

# Exact alpha bounds from the three evenly-spaced frameless generated cells.
ASSETS = {
    "icon_objective_pointer": (201, 212, 458, 614),
    "icon_tracker_collapse": (713, 269, 1091, 559),
    "icon_tracker_expand": (1285, 227, 1650, 599),
}


def resize_contain(image: Image.Image, size: tuple[int, int], padding: int = 1) -> Image.Image:
    available = (size[0] - padding * 2, size[1] - padding * 2)
    scale = min(available[0] / image.width, available[1] / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.NEAREST,
    )
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    output.alpha_composite(resized, ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2))
    return output


def main() -> None:
    sheet = Image.open(SOURCE).convert("RGBA")
    if sheet.size != (1821, 864):
        raise RuntimeError(f"unexpected tracker controls sheet size: {sheet.size}")
    OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, bounds in ASSETS.items():
        component = sheet.crop(bounds)
        output = resize_contain(component, (28, 28))
        output.save(OUTPUT / f"{name}.png")
        print(f"wrote {name}.png 28x28")



if __name__ == "__main__":
    main()
