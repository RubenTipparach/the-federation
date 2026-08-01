#!/usr/bin/env python3
# Generates the committed UI chassis for the active skin.
#
# Per CLAUDE.md section 3 an art asset is delivered as a .png, and per 5.1 a
# script may generate one only by writing the file to disk, never by building
# it at runtime. This writes the nine patch plate, the header bar and the button
# faces that assets/ui/skin_theme.tres maps onto the interface's controls.
#
# Every pixel is a Waldgeist entry named through the active skin's chassis role
# map in data/palette.json (CLAUDE.md 3.1 and 5.4): this file asks for "face"
# and "bevel_hi", and only the palette file says what those are. verify() below
# is the same gate the ship painter passes, so an off palette pixel stops the
# run before anything is written.
#
# Output always lands in assets/ui/skin/ whichever skin is active, so the
# theme's texture paths never move and swapping is a data change plus a rerun.
# Run scripts/gen-skin.sh rather than this directly: the theme is generated
# from the same skin and the two have to agree.
#
# Detail is drawn in 2 pixel blocks because the game runs at 1600x900 and the
# skin is pixel art at that scale: a 1 pixel bevel would vanish and a stretched
# one would blur. The nine patch margins are quoted alongside each texture and
# tools/gen_theme.py reads MARGINS below so the two cannot drift.
#
# Usage: python3 tools/gen_ui_plates.py

import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from shiplib import Px  # noqa: E402

HERE = os.path.dirname(__file__)
PALETTE = os.path.join(HERE, "..", "data", "palette.json")
OUT = os.path.join(HERE, "..", "assets", "ui", "skin")

# The art block. Everything below is measured in blocks and multiplied by this,
# so the whole skin rescales from one number if the game's resolution changes.
B = 2


# Nine patch margins in art blocks, keyed by texture. gen_theme.py imports
# this, so the painter and the theme cannot disagree about where a plate's
# stretchable middle begins.
MARGINS = {
    "plate": (4, 4, 4, 4),
    "header": (5, 3, 5, 3),
    "button_normal": (3, 3, 3, 3),
    "button_hover": (3, 3, 3, 3),
    "button_pressed": (3, 3, 3, 3),
    "button_disabled": (3, 3, 3, 3),
}


def active_skin(data=None):
    """The skin data/palette.json currently names, with its role maps."""
    if data is None:
        with open(PALETTE) as f:
            data = json.load(f)
    name = data["ui_skin"]
    assert name in data["ui_skins"], "ui_skin names unknown skin %r" % (name,)
    return name, data["ui_skins"][name], data


def load_roles():
    """The active skin's chassis role map plus every colour it is allowed to
    name. A role pointing at a colour the palette does not have raises here
    rather than painting something off palette, which is the point of the
    indirection."""
    name, skin, data = active_skin()
    colors = {}
    for cname, value in data["colors"].items():
        t = value.lstrip("#")
        colors[cname] = (int(t[0:2], 16), int(t[2:4], 16), int(t[4:6], 16))
    roles = {}
    for role, cname in skin["chassis"].items():
        assert cname in colors, "%s chassis role %r names unknown colour %r" % (
            name, role, cname)
        roles[role] = colors[cname]
    return roles, set(colors.values()), name


def verify(canvas, palette, path):
    """The gate: every pixel is a palette entry, checked before the file is
    written. Same contract as tools/shiplib.py verify() for ship art."""
    bad = {px[:3] for px in canvas.px if px[3] and px[:3] not in palette}
    assert not bad, "off palette pixels in %s: %r" % (path, bad)


def hashed(i, j):
    """A stable speckle. Deterministic so a rerun writes the same bytes and a
    regenerated texture is an empty diff unless the palette actually moved."""
    n = (i * 374761393 + j * 668265263) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return n ^ (n >> 16)


def blocks(p, x, y, w, h, rgb, alpha=255):
    """A rectangle measured in art blocks."""
    for j in range(h * B):
        for i in range(w * B):
            p.put(x * B + i, y * B + j, rgb, alpha)


def clear(p, x, y, w, h):
    """Cut a hole. The header's notched corners are not black, they are the
    bulkhead showing through, so they have to carry no pixel at all."""
    blocks(p, x, y, w, h, (0, 0, 0), 0)


def grit(p, x, y, w, h, base, specks, density):
    """A flecked face: the oxidised metal of the reference plates. Density is
    one speck per that many blocks."""
    blocks(p, x, y, w, h, base)
    for j in range(h):
        for i in range(w):
            n = hashed(x + i, y + j)
            if n % density == 0:
                blocks(p, x + i, y + j, 1, 1, specks[n % len(specks)])


# ---- the textures ------------------------------------------------------------
#
# Each returns (canvas, description). Sizes are in art blocks; the file is B
# times larger. Nine patch margins are stated in blocks and doubled in the
# theme, and they are quoted here so the two cannot drift silently.


def plate(R):
    """The instrument plate: a bronze frame around a glass face. 20x20 blocks,
    nine patch margin 4 blocks, centre tiled.

    Frame and glass are one texture rather than two nested panels, because a
    panel is what every readout is drawn on and nesting a second container
    inside every one of them would be scene surgery for a thing the art can
    just say.

    The frame is four blocks and no more. Eight device pixels of bronze times
    two edges times the eight panels a column carries is most of a column's
    height, and the first cut at six blocks pushed the bottom panel of both
    columns off the screen.

    The centre is glass and tiles rather than stretching: scanlines have to
    repeat or a tall panel gets four fat bands instead of a raster. Twelve
    blocks of centre over a three block period divides evenly, which is what
    makes the tiling seamless."""
    p = Px(20 * B, background=R["outline"], height=20 * B)
    grit(p, 1, 1, 18, 18, R["face"], [R["fleck_a"], R["fleck_b"]], 23)
    blocks(p, 1, 1, 18, 1, R["bevel_hi"])
    blocks(p, 1, 2, 1, 17, R["bevel_hi_2"])
    blocks(p, 1, 18, 18, 1, R["bevel_lo"])
    blocks(p, 18, 2, 1, 16, R["bevel_lo"])
    for rx, ry in [(2, 2), (17, 2), (2, 17), (17, 17)]:
        blocks(p, rx, ry, 1, 1, R["rivet"])
    # the glass well, rimmed so it reads as cut into the plate
    blocks(p, 3, 3, 14, 14, R["outline"])
    blocks(p, 4, 4, 12, 12, R["glass"])
    for j in range(4, 16, 3):
        blocks(p, 4, j, 12, 1, R["scan"])
    return p, "plate, margin 4, centre tiled"


def header(R):
    """The raised header bar, notched at the top corners like the reference
    plate. 24x11 blocks, nine patch margin 5 left and right, 3 top and bottom.

    The notch has to live inside the horizontal margin or stretching would
    smear the diagonal, which is why the margin is 5 and the cut is 3."""
    w, h, cut = 24, 11, 3
    p = Px(w * B, background=R["outline"], height=h * B, alpha=0)
    for j in range(h):
        for i in range(w):
            if i + j < cut or (w - 1 - i) + j < cut:
                clear(p, i, j, 1, 1)
                continue
            edge = (j in (0, h - 1) or i in (0, w - 1)
                    or i + j == cut or (w - 1 - i) + j == cut)
            if edge:
                blocks(p, i, j, 1, 1, R["outline"])
                continue
            top = j == 1 or i + j == cut + 1
            low = j == h - 2 or i == w - 2
            blocks(p, i, j, 1, 1,
                   R["bevel_hi"] if (top and j <= 2) else
                   (R["bevel_lo"] if low else R["face"]))
    for i in range(4, w - 4):
        if hashed(i, 5) % 9 == 0:
            blocks(p, i, 5, 1, 1, R["fleck_a"])
    # A rivet at each end of the bar, clear of where the label runs.
    for rx in (2, w - 3):
        blocks(p, rx, 5, 1, 1, R["rivet"])
    return p, "header, margin 5/3"


def button(R, state):
    """A control face. 12x10 blocks, margin 3.

    Pressed inverts the bevel and darkens the face, which is what makes a
    selected station tab read as pushed in rather than merely tinted."""
    face = {
        "normal": R["face"],
        "hover": R["bevel_hi_2"],
        "pressed": R["face_down"],
        "disabled": R["face_disabled"],
    }[state]
    hi = R["bevel_lo"] if state == "pressed" else R["bevel_hi"]
    lo = R["bevel_hi_2"] if state == "pressed" else R["bevel_lo"]
    if state == "disabled":
        hi, lo = R["face_disabled"], R["outline"]
    p = Px(12 * B, background=R["outline"], height=10 * B)
    if state == "disabled":
        blocks(p, 1, 1, 10, 8, face)
    else:
        grit(p, 1, 1, 10, 8, face, [R["fleck_a"], R["fleck_b"]], 31)
    blocks(p, 1, 1, 10, 1, hi)
    blocks(p, 1, 8, 10, 1, lo)
    return p, "button %s, margin 3" % state


def main():
    R, palette, skin = load_roles()
    print("skin: %s" % skin)
    os.makedirs(OUT, exist_ok=True)
    jobs = [("plate", plate(R)), ("header", header(R))]
    for state in ("normal", "hover", "pressed", "disabled"):
        jobs.append(("button_" + state, button(R, state)))
    for name, (canvas, note) in jobs:
        path = os.path.join(OUT, name + ".png")
        verify(canvas, palette, path)
        canvas.save(path)
        print("   %s" % note)


if __name__ == "__main__":
    main()
