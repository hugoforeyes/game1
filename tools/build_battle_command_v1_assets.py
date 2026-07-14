#!/usr/bin/env python3
"""Extract production battle-command frames and icons from the approved V1 sheets."""

from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parents[1]
CONCEPTS = ROOT / "assets/ui/battle_command_v1/concepts"
COMPONENT_OUTPUT = ROOT / "assets/ui/battle_command_v1/components"
ICON_OUTPUT = ROOT / "assets/ui/battle_command_v1/icons"

OUTPUT_SIZE = (256, 256)
ICON_ART_SIZE = 208

# Both 210px windows align the square body of the two generated frame states.
# The selected window simply reserves more transparent room for its top gem.
FRAME_CROPS = {
    "command_slot_normal": (50, 198, 260, 408),
    "command_slot_selected": (581, 190, 791, 400),
}
FRAME_RESIZE = (244, 244)
FRAME_OFFSETS = {
    "command_slot_normal": (6, 6),
    # The generated selected window reserves extra room above its square body
    # for the sapphire. Lift that window so the square body does not jump when
    # toggling between states.
    "command_slot_selected": (6, -4),
}

COMMAND_PLAYER_X = (0, 359, 680, 998, 1402)
COMMAND_PLAYER_Y = (0, 242, 452, 663, 873, 1122)
COMMAND_PLAYER_IDS = (
    ("attack", "skill", "probe", "item"),
    ("guard", "flee", "finisher", "spare"),
    ("back", "strike", "power_strike", "focus"),
    ("ember_slash", "crush", "mend", "tempest"),
    ("pierce", None, None, None),
)

COMPANION_A_X = (0, 378, 726, 1052, 1448)
COMPANION_A_Y = (0, 373, 693, 1086)
COMPANION_A_IDS = (
    ("venom_fang", "flame_burst", "frost_lance", "thunder_jolt"),
    ("shadow_drain", "wild_flurry", "skull_crack", "armor_break"),
    ("lullaby", "blinding_dust", "silencing_seal", "slow_mire"),
)

COMPANION_B_X = (0, 380, 709, 1093, 1448)
COMPANION_B_Y = (0, 370, 719, 1086)
COMPANION_B_IDS = (
    ("war_cry", "stone_ward", "quicksilver", "purify"),
    ("soothing_light", "verdant_rain", "regrowth", "guiding_star"),
    ("taunt", "iron_bastion", "shield_bash", None),
)


def _is_strong_key(pixel: tuple[int, int, int, int]) -> bool:
    red, green, blue, _alpha = pixel
    return green > 170 and green - max(red, blue) > 100


def _remove_border_green(image: Image.Image) -> Image.Image:
    """Turn only border-connected chroma green into a feathered alpha matte.

    The generated sheets use slightly graded green rather than one exact RGB
    value. A connected matte preserves real green artwork such as leaves,
    healing light and venom inside each outlined glyph.
    """

    rgba = image.convert("RGBA")
    width, height = rgba.size
    pixels = rgba.load()
    matte = Image.new("L", rgba.size, 0)
    matte_pixels = matte.load()
    queue: deque[tuple[int, int]] = deque()

    def seed(x: int, y: int) -> None:
        if matte_pixels[x, y] == 0 and _is_strong_key(pixels[x, y]):
            matte_pixels[x, y] = 255
            queue.append((x, y))

    for x in range(width):
        seed(x, 0)
        seed(x, height - 1)
    for y in range(height):
        seed(0, y)
        seed(width - 1, y)

    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if nx < 0 or nx >= width or ny < 0 or ny >= height:
                continue
            if matte_pixels[nx, ny] != 0 or not _is_strong_key(pixels[nx, ny]):
                continue
            matte_pixels[nx, ny] = 255
            queue.append((nx, ny))

    # One source-pixel feather catches chroma blended into antialiased edges.
    near_matte = matte.filter(ImageFilter.MaxFilter(3))
    near_pixels = near_matte.load()
    output = rgba.copy()
    output_pixels = output.load()
    for y in range(height):
        for x in range(width):
            red, green, blue, alpha = pixels[x, y]
            if matte_pixels[x, y] != 0:
                output_pixels[x, y] = (0, 0, 0, 0)
                continue
            if near_pixels[x, y] == 0:
                continue
            excess = green - max(red, blue)
            if green <= 80 or excess <= 24:
                continue
            edge_alpha = round(255.0 * (1.0 - min(max((excess - 24.0) / 76.0, 0.0), 1.0)))
            final_alpha = min(alpha, edge_alpha)
            # Remove green spill from the remaining partially transparent edge.
            neutral_green = min(green, max(red, blue) + 8)
            output_pixels[x, y] = (red, neutral_green, blue, final_alpha)
    return output


def _cell_box(xs: tuple[int, ...], ys: tuple[int, ...], column: int, row: int) -> tuple[int, int, int, int]:
    return xs[column], ys[row], xs[column + 1], ys[row + 1]


def _contain_on_canvas(image: Image.Image, art_size: int) -> Image.Image:
    alpha_bounds = image.getchannel("A").getbbox()
    if alpha_bounds is None:
        raise RuntimeError("source cell became empty after chroma cleanup")
    art = image.crop(alpha_bounds)
    scale = min(art_size / art.width, art_size / art.height)
    resized = art.resize(
        (max(1, round(art.width * scale)), max(1, round(art.height * scale))),
        Image.Resampling.LANCZOS,
    )
    canvas = Image.new("RGBA", OUTPUT_SIZE, (0, 0, 0, 0))
    canvas.alpha_composite(
        resized,
        ((OUTPUT_SIZE[0] - resized.width) // 2, (OUTPUT_SIZE[1] - resized.height) // 2),
    )
    return canvas


def _build_frames() -> None:
    source = Image.open(CONCEPTS / "component_sheet_v1.png").convert("RGBA")
    if source.size != (1536, 1024):
        raise RuntimeError(f"unexpected component sheet size: {source.size}")
    COMPONENT_OUTPUT.mkdir(parents=True, exist_ok=True)
    for name, box in FRAME_CROPS.items():
        frame = _remove_border_green(source.crop(box))
        # Keep the aligned source window instead of trimming each state. The
        # small selected-state lift aligns the square body while retaining its
        # top sapphire and bottom underlight inside the common 256px canvas.
        frame = frame.resize(FRAME_RESIZE, Image.Resampling.LANCZOS)
        canvas = Image.new("RGBA", OUTPUT_SIZE, (0, 0, 0, 0))
        canvas.alpha_composite(frame, FRAME_OFFSETS[name])
        output = COMPONENT_OUTPUT / f"{name}.png"
        canvas.save(output, optimize=True)
        print(f"wrote {output.relative_to(ROOT)}")


def _build_icon_sheet(
    source_name: str,
    xs: tuple[int, ...],
    ys: tuple[int, ...],
    ids: tuple[tuple[str | None, ...], ...],
) -> None:
    source = Image.open(CONCEPTS / source_name).convert("RGBA")
    if source.size != (xs[-1], ys[-1]):
        raise RuntimeError(f"unexpected {source_name} size: {source.size}")
    ICON_OUTPUT.mkdir(parents=True, exist_ok=True)
    for row, row_ids in enumerate(ids):
        for column, icon_id in enumerate(row_ids):
            if icon_id is None:
                continue
            cell = source.crop(_cell_box(xs, ys, column, row))
            icon = _contain_on_canvas(_remove_border_green(cell), ICON_ART_SIZE)
            output = ICON_OUTPUT / f"icon_{icon_id}.png"
            icon.save(output, optimize=True)
            print(f"wrote {output.relative_to(ROOT)}")


def main() -> None:
    _build_frames()
    _build_icon_sheet(
        "command_player_icon_atlas_v1.png",
        COMMAND_PLAYER_X,
        COMMAND_PLAYER_Y,
        COMMAND_PLAYER_IDS,
    )
    _build_icon_sheet(
        "companion_icon_atlas_a_v1.png",
        COMPANION_A_X,
        COMPANION_A_Y,
        COMPANION_A_IDS,
    )
    _build_icon_sheet(
        "companion_icon_atlas_b_v1.png",
        COMPANION_B_X,
        COMPANION_B_Y,
        COMPANION_B_IDS,
    )


if __name__ == "__main__":
    main()
