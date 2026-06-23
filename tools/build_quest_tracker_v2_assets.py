#!/usr/bin/env python3
"""Build tracker v2 components from one complete frame and two complete badges."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "assets/ui/quest_tracker_v2"
FRAME_SOURCE = ASSET_ROOT / "complete_frame_alpha.png"
ICON_SHEET_SOURCE = ASSET_ROOT / "tracker_icon_sheet_native_v3_alpha.png"
OUTPUT = ASSET_ROOT / "components"

# Every output is cut from its matching side of the original complete frame.
# Alpha trimming removes the source canvas offset before one-time pixel-art
# downsampling. Runtime then tiles these native-size pieces without stretching.
FRAME_COMPONENTS = {
    "corner_tl": ((33, 36, 170, 170), (24, 24)),
    "corner_tr": ((1690, 36, 1827, 170), (24, 24)),
    "corner_bl": ((33, 676, 170, 810), (24, 24)),
    "corner_br": ((1690, 676, 1827, 810), (24, 24)),
    "edge_top": ((400, 36, 404, 62), (4, 3)),
    "edge_bottom": ((400, 784, 404, 810), (4, 3)),
    "edge_left": ((33, 200, 59, 204), (3, 4)),
    "edge_right": ((1800, 200, 1826, 204), (3, 4)),
    "mid_top": ((895, 30, 965, 70), (22, 12)),
    "mid_bottom": ((895, 776, 965, 818), (22, 12)),
    "mid_left": ((25, 387, 70, 459), (12, 22)),
    "mid_right": ((1790, 387, 1835, 459), (12, 22)),
}

ICON_COMPONENTS = {
    "badge_expanded": ((174, 107, 464, 399), (28, 28)),
    "icon_collapse": ((691, 188, 876, 323), (14, 14)),
    "icon_objective": ((1144, 185, 1264, 327), (11, 11)),
    "icon_progress": ((256, 632, 372, 785), (10, 10)),
    "icon_hint": ((648, 601, 866, 808), (11, 11)),
    "badge_compact": ((1061, 562, 1352, 865), (30, 30)),
}


def resize_contain(image: Image.Image, size: tuple[int, int], padding: int = 0) -> Image.Image:
    available = (max(1, size[0] - padding * 2), max(1, size[1] - padding * 2))
    scale = min(available[0] / image.width, available[1] / image.height)
    resized = image.resize(
        (max(1, round(image.width * scale)), max(1, round(image.height * scale))),
        Image.Resampling.NEAREST,
    )
    output = Image.new("RGBA", size, (0, 0, 0, 0))
    output.alpha_composite(resized, ((size[0] - resized.width) // 2, (size[1] - resized.height) // 2))
    return output


def trim_alpha(image: Image.Image) -> Image.Image:
    bounds = image.getchannel("A").getbbox()
    if bounds is None:
        raise RuntimeError("generated source has no visible pixels")
    return image.crop(bounds)


def normalize_gold_palette(image: Image.Image) -> Image.Image:
    """Match AI lighting across separately cropped sides without changing alpha."""
    output = image.copy().convert("RGBA")
    pixels = list(output.getdata())
    luminances = [0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b, a in pixels if a > 32]
    if not luminances:
        return output
    low, high = min(luminances), max(luminances)
    span = max(1.0, high - low)
    palette = (
        (8, 7, 4),
        (42, 29, 18),
        (188, 142, 80),
        (244, 227, 140),
    )
    normalized = []
    for red, green, blue, alpha in pixels:
        if alpha <= 32:
            normalized.append((red, green, blue, alpha))
            continue
        luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        level = (luminance - low) / span
        color = palette[0] if level < 0.03 else palette[1] if level < 0.22 else palette[2] if level < 0.72 else palette[3]
        normalized.append((*color, alpha))
    output.putdata(normalized)
    return output


def harden_alpha(image: Image.Image) -> Image.Image:
    """Keep native pixel edges fully opaque or transparent, never interpolated."""
    output = image.copy().convert("RGBA")
    output.putdata([
        (red, green, blue, 255 if alpha >= 128 else 0)
        for red, green, blue, alpha in output.getdata()
    ])
    return output


def main() -> None:
    frame = Image.open(FRAME_SOURCE).convert("RGBA")
    if frame.size != (1860, 845):
        raise RuntimeError(f"unexpected complete frame size: {frame.size}")
    OUTPUT.mkdir(parents=True, exist_ok=True)

    for name, (bounds, size) in FRAME_COMPONENTS.items():
        component = trim_alpha(frame.crop(bounds)).resize(size, Image.Resampling.NEAREST)
        if name.startswith("edge_") or name.startswith("mid_"):
            component = normalize_gold_palette(component)
        component.save(OUTPUT / f"{name}.png")
        print(f"wrote {name}.png {component.width}x{component.height}")

    icon_sheet = Image.open(ICON_SHEET_SOURCE).convert("RGBA")
    if icon_sheet.size != (1536, 1024):
        raise RuntimeError(f"unexpected icon sheet size: {icon_sheet.size}")
    for name, (bounds, size) in ICON_COMPONENTS.items():
        image = trim_alpha(icon_sheet.crop(bounds))
        output = harden_alpha(resize_contain(image, size))
        output.save(OUTPUT / f"{name}.png")
        print(f"wrote {name}.png {size[0]}x{size[1]}")


if __name__ == "__main__":
    main()
