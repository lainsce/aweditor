#!/usr/bin/env python3
"""Build the 80x128 cursor atlases for the historical Wars palettes.

The original editor stores cursor artwork in a fixed, deliberately small
atlas.  The three shipped sheets (misc_0, misc_4, misc_5) establish the
pointer and frame masks used by CursorAtlas.swift.  The historical games do
not have a matching editor resource, so this builder keeps the atlas geometry
and supplies palette-specific corner frames plus the wrench badge used by the
corresponding game references.  It is intentionally nearest-neighbour/
pixel-only: cursor art must stay crisp at native map scale.
"""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SPRITESHEETS = ROOT / "Sources" / "AWED" / "Resources" / "Spritesheets"

# Slots consumed by CursorAtlas.swift.  Keeping them in one place makes the
# binary contract obvious and gives the verification pass a single source of
# truth.
POINTER_SLOTS = {
    "allowed": (0, 0, 16, 16),
    "forbidden": (16, 0, 16, 16),
    "delete": (48, 0, 32, 16),
}
FRAME_SLOTS = {
    "single": (0, 16, 18, 18),
    "large3": (18, 16, 48, 48),
    "large4": (0, 64, 64, 64),
}

RGBA = tuple[int, int, int, int]

# Common NTSC RP2C02 display swatches used by the Famicom UI.  These are
# palette entries, not arbitrary CSS-like colours: $30 is the bright white,
# $3A is the pale green used for the cursor shadow, and $0F is black.
FAMICOM_PPU_BLACK = (0, 0, 0)
FAMICOM_PPU_WHITE = (252, 252, 252)
FAMICOM_PPU_PALE_GREEN = (184, 248, 184)


def opaque(color: tuple[int, int, int]) -> RGBA:
    return (*color, 255)


def paste_slot(destination: Image.Image, source: Image.Image, box: tuple[int, int, int, int]) -> None:
    """Copy a source slot into a same-sized destination slot."""

    x, y, width, height = box
    destination.alpha_composite(source.crop((x, y, x + width, y + height)), (x, y))


def padded(rows: Iterable[str], width: int) -> tuple[str, ...]:
    """Pad hand-authored pixel rows without making whitespace error-prone."""

    return tuple(row.ljust(width)[:width] for row in rows)


# These games show the map cursor as corner angles, not as the AWDS-style
# arrow/X pointer pair. Their delete affordance is a compact wrench badge.
# The badge is intentionally kept in the existing 32×16 delete slot so the
# editor can continue to use the same atlas contract.


def put_pixel(destination: Image.Image, x: int, y: int, colour: RGBA) -> None:
    if 0 <= x < destination.width and 0 <= y < destination.height:
        destination.putpixel((x, y), colour)


def fill_rect(destination: Image.Image, x: int, y: int, width: int, height: int, colour: RGBA) -> None:
    for py in range(y, y + height):
        for px in range(x, x + width):
            put_pixel(destination, px, py, colour)


def draw_line(
    destination: Image.Image,
    start: tuple[int, int],
    end: tuple[int, int],
    colour: RGBA,
    thickness: int = 1,
) -> None:
    x0, y0 = start
    x1, y1 = end
    steps = max(abs(x1 - x0), abs(y1 - y0))
    for step in range(steps + 1):
        fraction = step / steps if steps else 0
        x = round(x0 + (x1 - x0) * fraction)
        y = round(y0 + (y1 - y0) * fraction)
        for dy in range(thickness):
            for dx in range(thickness):
                put_pixel(destination, x + dx, y + dy, colour)


def draw_box(
    destination: Image.Image,
    origin: tuple[int, int],
    size: tuple[int, int],
    border: RGBA,
    fill: RGBA,
    cut: int = 0,
) -> None:
    ox, oy = origin
    width, height = size
    for y in range(height):
        for x in range(width):
            if cut:
                corner = (
                    (x < cut and y < cut and x + y < cut)
                    or (x >= width - cut and y < cut and width - 1 - x + y < cut)
                    or (x < cut and y >= height - cut and x + height - 1 - y < cut)
                    or (x >= width - cut and y >= height - cut and width - 1 - x + height - 1 - y < cut)
                )
                if corner:
                    continue
            edge = x == 0 or y == 0 or x == width - 1 or y == height - 1
            put_pixel(destination, ox + x, oy + y, border if edge else fill)


def draw_wrench_icon(
    destination: Image.Image,
    origin: tuple[int, int],
    size: tuple[int, int],
    palette: dict[object, RGBA],
    style: str,
) -> None:
    """Draw a compact open-jaw wrench, sized for the game's badge slot."""

    width, height = size
    # Center the 16-pixel reference icon in each badge. Smaller DMG/GBW3
    # badges simply clip one pixel at either side, preserving a crisp edge.
    shift_x = max(0, (width - 16) // 2)
    small = height <= 12
    shift_y = 0 if small else 0
    wrench = palette["wrench"]
    highlight = palette["highlight"]

    def point(x: int, y: int, colour: RGBA = wrench) -> None:
        put_pixel(destination, origin[0] + shift_x + x, origin[1] + shift_y + y, colour)

    # Open jaw at the upper-right. Leaving the centre gap transparent exposes
    # the badge fill and keeps the icon recognisable at native 1x scale.
    for x, y in ((10, 1), (11, 1), (9, 2), (9, 3), (10, 4),
                 (12, 1), (13, 1), (13, 2), (13, 3), (12, 4),
                 (11, 4), (12, 4)):
        point(x, y)

    start_y = 4
    end_y = 10 if small else 12
    start_x = 11
    end_x = 5
    thickness = 1 if small else 2
    draw_line(
        destination,
        (origin[0] + shift_x + start_x, origin[1] + shift_y + start_y),
        (origin[0] + shift_x + end_x, origin[1] + shift_y + end_y),
        wrench,
        thickness,
    )
    for x, y in ((4, end_y), (5, end_y), (4, end_y - 1), (5, end_y - 1)):
        point(x, y)

    # A one-pixel metal glint differentiates the wrench from a plain slash.
    point(11, 3, highlight)


def draw_wrench_badge(destination: Image.Image, origin: tuple[int, int], palette: dict[object, RGBA], style: str) -> None:
    """Draw the historical delete affordance as a badge with a wrench."""

    configs = {
        # x, y, width, height, corner-cut, wrench offset
        "nes": (8, 1, 16, 14, 1, (0, 0)),
        "dmg": (9, 2, 14, 12, 2, (0, 0)),
        "snes": (7, 1, 18, 14, 1, (0, 0)),
        "ds": (8, 1, 16, 14, 2, (0, 0)),
        "cgb2": (7, 1, 18, 14, 1, (0, 0)),
        "cgb3": (9, 2, 14, 12, 1, (0, 0)),
    }
    x, y, width, height, cut, wrench_offset = configs[style]
    draw_box(destination, (origin[0] + x, origin[1] + y), (width, height), palette["border"], palette["fill"], cut)
    wx, wy = wrench_offset
    draw_wrench_icon(
        destination,
        (origin[0] + x + wx, origin[1] + y + wy),
        (width, height),
        palette,
        style,
    )


def draw_pointer_set(destination: Image.Image, palette: dict[object, RGBA], style: str) -> None:
    # The six historical games use map-frame corner angles as their cursor.
    # Their atlas pointer/X slots remain transparent; only the delete slot is
    # populated, using the in-game wrench badge treatment.
    draw_wrench_badge(destination, (POINTER_SLOTS["delete"][0], POINTER_SLOTS["delete"][1]), palette, style)


def draw_pattern(
    destination: Image.Image,
    origin: tuple[int, int],
    pattern: tuple[str, ...],
    colours: dict[str, RGBA],
) -> None:
    """Draw a corner pattern, where a space means transparent."""

    ox, oy = origin
    for row, line in enumerate(pattern):
        for column, token in enumerate(line):
            if token != " ":
                destination.putpixel((ox + column, oy + row), colours[token])


def rotate_pattern(pattern: tuple[str, ...], quarter_turns: int) -> tuple[str, ...]:
    result = pattern
    for _ in range(quarter_turns % 4):
        result = tuple("".join(row[index] for row in result[::-1]) for index in range(len(result[0])))
    return result


def draw_frame(
    destination: Image.Image,
    size: int,
    pattern: tuple[str, ...],
    colours: dict[str, RGBA],
    include_midpoints: bool,
) -> None:
    """Draw four (or, for a 4x4 cursor, nine) corner brackets."""

    mark = len(pattern[0])
    positions = [0, size - mark]
    if include_midpoints:
        positions.insert(1, (size - mark) // 2)

    last = positions[-1]
    for y in positions:
        for x in positions:
            # A single top-left pattern is enough; rotate it for the outside
            # edge of each quadrant so a corner remains a corner after it is
            # mirrored to the right/bottom side.  The midpoint marks used by
            # the 4x4 frame are edge markers rather than additional corners.
            if y == 0:
                quarter_turns = 0 if x != last else 1
            elif y == last:
                quarter_turns = 3 if x != last else 2
            elif x == 0:
                quarter_turns = 3
            elif x == last:
                quarter_turns = 1
            else:
                quarter_turns = 0
            draw_pattern(destination, (x, y), rotate_pattern(pattern, quarter_turns), colours)


def replace_frames(
    destination: Image.Image,
    pattern: tuple[str, ...],
    colours: dict[str, RGBA],
) -> None:
    for name, (x, y, width, height) in FRAME_SLOTS.items():
        frame = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        draw_frame(frame, width, pattern, colours, include_midpoints=name == "large4")
        destination.alpha_composite(frame, (x, y))


def build_sheet(
    name: str,
    pointer_palette: dict[object, RGBA],
    frame_pattern: tuple[str, ...],
    frame_colours: dict[str, RGBA],
    pointer_style: str,
) -> None:
    source = Image.open(SPRITESHEETS / "misc_0.png").convert("RGBA")
    destination = Image.new("RGBA", source.size, (0, 0, 0, 0))
    draw_pointer_set(destination, pointer_palette, pointer_style)
    replace_frames(destination, frame_pattern, frame_colours)
    destination.save(SPRITESHEETS / f"misc_{name}.png", optimize=False)


def palette_map(**colours: tuple[int, int, int]) -> dict[object, RGBA]:
    """Map the misc_0 pointer ramp by semantic colour role."""

    source = {
        "paper": (255, 255, 247, 255),
        "red": (231, 71, 39, 255),
        "blue": (148, 205, 251, 255),
        "cream": (252, 247, 143, 255),
        "peach": (247, 215, 175, 255),
        "pink": (247, 159, 167, 255),
        "yellow": (255, 255, 63, 255),
        "indigo": (87, 95, 255, 255),
        "orange": (255, 111, 56, 255),
        "gold": (255, 183, 87, 255),
        "lemon": (255, 239, 82, 255),
        "lavender": (239, 239, 255, 255),
    }
    result: dict[object, RGBA] = {source[key]: opaque(value) for key, value in colours.items()}
    # Keep the semantic names alongside the source-colour mapping.  The
    # The pointer extras below are intentionally redrawn rather than copied,
    # so they can select a per-game border/fill/highlight/wrench role.
    result.update({key: opaque(value) for key, value in colours.items()})
    result["fallback"] = opaque(colours["paper"])
    result.setdefault("border", result["red"])
    result.setdefault("dark", result["red"])
    result.setdefault("light", result["paper"])
    result.setdefault("fill", result["paper"])
    result.setdefault("highlight", result["blue"])
    result.setdefault("accent", result["yellow"])
    result.setdefault("wrench", result["orange"])
    result.setdefault("green", result["blue"])
    return result


def main() -> None:
    # Famicom Wars: PPU-white cursor brackets with the NES's green/black
    # shadow. The actual game stores palette indices; these RGB values are the
    # display-space rendition of those indices.
    build_sheet(
        "6",
        palette_map(
            paper=FAMICOM_PPU_WHITE, red=FAMICOM_PPU_BLACK, blue=FAMICOM_PPU_PALE_GREEN,
            cream=FAMICOM_PPU_WHITE, peach=FAMICOM_PPU_BLACK, pink=FAMICOM_PPU_PALE_GREEN,
            yellow=FAMICOM_PPU_WHITE, indigo=FAMICOM_PPU_BLACK, orange=FAMICOM_PPU_BLACK,
            gold=FAMICOM_PPU_PALE_GREEN, lemon=FAMICOM_PPU_WHITE, lavender=FAMICOM_PPU_WHITE,
        ),
        frame_pattern=("AAAAA", "ABBBB", "ABB  ", "AB   ", "A    "),
        frame_colours={"A": opaque(FAMICOM_PPU_WHITE), "B": opaque(FAMICOM_PPU_PALE_GREEN)},
        pointer_style="nes",
    )

    # Game Boy Wars: the DMG's four green shades, with the darkest tone
    # outlining the cursor and the lightest tone carrying the highlight.
    build_sheet(
        "7",
        palette_map(
            paper=(154, 158, 63), red=(27, 42, 9), blue=(73, 107, 34),
            cream=(154, 158, 63), peach=(14, 69, 11), pink=(73, 107, 34),
            yellow=(154, 158, 63), indigo=(27, 42, 9), orange=(14, 69, 11),
            gold=(73, 107, 34), lemon=(154, 158, 63), lavender=(154, 158, 63),
        ),
        frame_pattern=("AAAAA", "ABBBB", "ABB  ", "AB   ", "A    "),
        frame_colours={"A": opaque((27, 42, 9)), "B": opaque((154, 158, 63))},
        pointer_style="dmg",
    )

    # Super Famicom Wars: the gameplay reference has a distinctive red
    # outside edge, salmon inner pixels, and a white highlight on each corner.
    build_sheet(
        "8",
        palette_map(
            paper=(248, 248, 248), red=(162, 11, 0), blue=(250, 168, 158),
            cream=(255, 204, 64), peach=(248, 248, 248), pink=(250, 168, 158),
            yellow=(255, 204, 64), indigo=(162, 11, 0), orange=(226, 77, 0),
            gold=(255, 204, 64), lemon=(255, 204, 64), lavender=(248, 248, 248),
        ),
        frame_pattern=("ABBBB", "BCCCC", "CCBAA", "CCB  ", "BBA  "),
        frame_colours={
            "A": opaque((162, 11, 0)),
            "B": opaque((250, 168, 158)),
            "C": opaque((248, 248, 248)),
        },
        pointer_style="snes",
    )

    # Days of Ruin: charcoal outline, IDS red accent, and the dusty cream
    # used by the DS map UI.  The cursor remains legible over its muted maps.
    build_sheet(
        "9",
        palette_map(
            paper=(255, 222, 206), red=(24, 27, 30), blue=(132, 148, 214),
            cream=(255, 231, 123), peach=(189, 181, 173), pink=(220, 64, 48),
            yellow=(255, 231, 123), indigo=(12, 12, 16), orange=(206, 115, 107),
            gold=(206, 173, 99), lemon=(255, 231, 123), lavender=(222, 222, 214),
        ),
        frame_pattern=("AAAAAA", "ABBBBA", "ABCCBA", "ABCDBA", "ABBDBA", "AAAAAA"),
        frame_colours={
            "A": opaque((24, 27, 30)),
            "B": opaque((222, 222, 214)),
            "C": opaque((220, 64, 48)),
            "D": opaque((255, 231, 123)),
        },
        pointer_style="ds",
    )

    # Game Boy Wars 2: CGB blue water/sky with a yellow cursor highlight.
    build_sheet(
        "10",
        palette_map(
            paper=(248, 248, 248), red=(16, 40, 168), blue=(80, 184, 248),
            cream=(248, 248, 0), peach=(248, 176, 144), pink=(80, 184, 248),
            yellow=(248, 248, 0), indigo=(0, 0, 0), orange=(0, 96, 240),
            gold=(248, 176, 144), lemon=(248, 248, 0), lavender=(248, 248, 248),
        ),
        frame_pattern=("AAAAAA", "ABBBBA", "ABCCBA", "ABCDBA", "ABBDBA", "AAAAAA"),
        frame_colours={
            "A": opaque((16, 40, 168)),
            "B": opaque((248, 248, 248)),
            "C": opaque((248, 248, 0)),
            "D": opaque((80, 184, 248)),
        },
        pointer_style="cgb2",
    )

    # Game Boy Wars 3: a brighter CGB palette than GBW2, keyed to its
    # blue/green map tiles and white unit lettering.
    build_sheet(
        "11",
        palette_map(
            paper=(255, 255, 255), red=(0, 25, 136), blue=(148, 234, 255),
            cream=(228, 204, 72), peach=(255, 172, 169), pink=(148, 234, 255),
            yellow=(228, 204, 72), indigo=(0, 25, 136), orange=(118, 225, 7),
            gold=(228, 204, 72), lemon=(228, 204, 72), lavender=(255, 255, 255),
        ),
        frame_pattern=("AAAAA", "ABBBB", "ABB  ", "AB   ", "A    "),
        frame_colours={"A": opaque((0, 25, 136)), "B": opaque((255, 255, 255))},
        pointer_style="cgb3",
    )


if __name__ == "__main__":
    main()
