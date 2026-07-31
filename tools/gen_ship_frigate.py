#!/usr/bin/env python3
# Generates the committed frigate: mesh, pixel art diffuse atlas, and emissive
# lights maps, in the style of the author's R1 starship sheets.
#
# Style source: docs/examples/ship-art/old_ships/R1-Starship-A. The palette is
# loaded from those PNGs at build time and the finished maps are verified
# against them before anything is written: every pixel must be a sheet color,
# the lights map stays within a sheet-like budget, the engine layer is a
# subset of the combined lights map, and every painted pixel sits inside its
# atlas rect.
#
# The R1 look, measured from the sheets:
#   - steel blue hull plates over the same blue as the atlas background, with
#     chunky dark gray armor slabs; 1px purple-dark outlines
#   - top lit bevels: a light ridge under a line's top and left, a darker
#     step above its bottom and right; fills flat otherwise
#   - rivet dots along plate edges, dashed borders on the red machinery
#   - ladders of alternating bars for engine blocks and vents
#   - windows are sparse single yellow pixels; some of them glow
#   - engines are red bells: a dark red ring, salmon glow, warm white core
#   - subtle single-pixel wear on the big armor slabs only
#
# Silhouette is a frigate in the Okinawa tradition (docs/12): saucer forward
# and dominant, short angular spine, small engineering body, two nacelles held
# high on swept pylons. No geometry or pixels from any reference are copied.
#
# Per CLAUDE.md sections 2 and 3 this writes .obj and .png to disk. Run it and
# commit what it writes. Preview with tools/render_preview.py.
#
# Usage: python3 tools/gen_ship_frigate.py

import math
import os
import random

from shiplib import (Px, Obj, circle_mask, disc_outline, octagon_mask,
                     read_png_colors, rect_mask, rings, slab, verify)

HERE = os.path.dirname(os.path.abspath(__file__))
MESH_OUT = os.path.join(HERE, "..", "assets", "meshes")
TEX_OUT = os.path.join(HERE, "..", "assets", "textures")
ART = os.path.join(HERE, "..", "docs", "examples", "ship-art", "old_ships",
                   "R1-Starship-A")
REF_DIFF = os.path.join(ART, "R1_ship2_diff4-2-export.png")
REF_ENG = os.path.join(ART, "R1_ship2_em_eng_glow.png")
REF_HULL_EM = os.path.join(ART, "R1_ship2_em_hull_lighting.png")

TEX = 256
RNG = random.Random(11)

# Roles into the R1 palette. Every value must exist in the reference sheets;
# check_palette() fails the build on a color that drifted, which keeps this
# list honest without copying the sheet wholesale.
BASE = (68, 87, 134)           # hull base and atlas background, like the sheet
OUTLINE = (34, 32, 52)         # purple-dark plate outlines
DEEP = (20, 20, 45)            # darkest: grooves, bay interiors
P_BLUE = (107, 127, 166)       # blue hull panel
P_BLUE_LIGHT = (120, 144, 193) # its top lit ridge
P_BLUE_SHADE = (95, 116, 165)  # its shaded step
B2 = (87, 103, 144)            # quieter blue panel
GRAY_D = (76, 76, 76)          # armor slab
GRAY_D_WORN = (75, 75, 75)     # its single pixel wear step
GRAY = (105, 106, 106)         # armor lit face
GRAY_L = (170, 170, 170)       # armor ridge
SILVER = (192, 192, 192)       # engine bell ring
WHITE = (228, 228, 228)        # engine bell
MAUVE = (132, 126, 135)        # trim plate
RED = (172, 50, 50)            # machinery
RED_D = (143, 52, 52)
RED_SH = (115, 54, 53)
YELLOW = (251, 242, 54)        # window pixels
ACCENT = (99, 155, 255)        # bright blue accent strips

DIFFUSE_ROLES = (
    BASE, OUTLINE, DEEP, P_BLUE, P_BLUE_LIGHT, P_BLUE_SHADE, B2, GRAY_D,
    GRAY_D_WORN, GRAY, GRAY_L, SILVER, WHITE, MAUVE, RED, RED_D, RED_SH,
    YELLOW, ACCENT)

GLOW_RING = (104, 42, 35)      # engine bell: dark ring
GLOW_RED = (194, 77, 63)       # salmon glow
GLOW_RED_LIGHT = (238, 148, 138)
GLOW_WARM = (246, 231, 207)    # warm white core
GLOW_YELLOW = (255, 248, 1)    # lit windows
LIGHTS_ROLES = (GLOW_RING, GLOW_RED, GLOW_RED_LIGHT, GLOW_WARM, GLOW_YELLOW)

# Top lit bevel maps for the one-pass shader in shiplib.
BEVEL_DARK = {OUTLINE, DEEP}
BEVEL_LIGHT = {P_BLUE: P_BLUE_LIGHT, B2: P_BLUE, GRAY_D: GRAY, GRAY: GRAY_L}
BEVEL_SHADE = {P_BLUE: P_BLUE_SHADE}

# ---- atlas layout -----------------------------------------------------------
#
# Pixel rects, shared by the painter and the UV mapper. Caps and walls get
# separate rects so a wall is a designed strip rather than a squashed cap.
R_SAUCER = (4, 4, 124, 124)
R_SAUCER_RIM = (4, 130, 124, 148)
R_NACELLE_SIDE = (4, 154, 124, 178)
R_NACELLE_TOP = (132, 4, 164, 124)
R_SPINE = (172, 4, 236, 64)
R_SPINE_SIDE = (172, 70, 236, 86)
R_BODY = (172, 94, 236, 154)
R_BODY_SIDE = (172, 160, 236, 176)
R_PYLON = (172, 182, 236, 214)
R_BRIDGE = (132, 132, 164, 164)
R_BRIDGE_SIDE = (132, 170, 164, 186)
R_NACELLE_AFT = (132, 192, 164, 216)
R_NACELLE_FORE = (132, 222, 164, 246)
R_BODY_AFT = (172, 220, 236, 244)
ALL_RECTS = (
    R_SAUCER, R_SAUCER_RIM, R_NACELLE_SIDE, R_NACELLE_TOP, R_SPINE,
    R_SPINE_SIDE, R_BODY, R_BODY_SIDE, R_PYLON, R_BRIDGE, R_BRIDGE_SIDE,
    R_NACELLE_AFT, R_NACELLE_FORE, R_BODY_AFT)


def check_palette():
    sheet = read_png_colors(REF_DIFF)
    for role in DIFFUSE_ROLES:
        assert role in sheet, "diffuse role %r is not an R1 color" % (role,)
    lit = read_png_colors(REF_ENG) | read_png_colors(REF_HULL_EM, min_count=15)
    for role in LIGHTS_ROLES:
        assert role in lit, "lights role %r is not an R1 glow color" % (role,)
    return sheet, lit


# ---- painting helpers -------------------------------------------------------


def window_run(d, l, x, y, count, step, lit_every=2, vertical=False):
    """Sparse single yellow window pixels the way R1 places them; every
    lit_every-th one glows in the lights map."""
    for i in range(count):
        wx = x + (0 if vertical else i * step)
        wy = y + (i * step if vertical else 0)
        d.put(wx, wy, YELLOW)
        if i % lit_every == 0:
            l.put(wx, wy, GLOW_YELLOW)


def red_bell(d, layer, x0, y0, w, h, r):
    """An R1 engine bell: red housing with a dashed border, a silver ringed
    white bell, and the layered red glow in the emissive layer."""
    d.shape(x0, y0, rect_mask(w, h), RED, line=OUTLINE, width=1)
    d.dash(x0 + 1, y0 + 1, w - 2, RED_D)
    d.dash(x0 + 1, y0 + h - 2, w - 2, RED_D)
    d.dash(x0 + 1, y0 + 1, h - 2, RED_D, vertical=True)
    d.dash(x0 + w - 2, y0 + 1, h - 2, RED_D, vertical=True)
    cx, cy = x0 + w // 2, y0 + h // 2
    d.shape(cx - r, cy - r, octagon_mask(r), WHITE, line=SILVER, width=1)
    d.stamp(cx - 2, cy - 2, octagon_mask(2), GRAY)
    layer.frame(cx - r, cy - r, octagon_mask(r), GLOW_RING, width=1)
    layer.stamp(cx - r + 1, cy - r + 1, octagon_mask(r - 1), GLOW_RED)
    layer.stamp(cx - r + 3, cy - r + 3, octagon_mask(r - 3), GLOW_RED_LIGHT)
    layer.stamp(cx - 1, cy - 1, octagon_mask(1), GLOW_WARM)


def rivet_ring(d, cx, cy, r, count, offset=0.0):
    """Rivet dots following a circular plate edge."""
    for i in range(count):
        a = offset + 2.0 * math.pi * i / count
        d.put(int(cx + math.cos(a) * r), int(cy + math.sin(a) * r), OUTLINE)


# ---- the atlases, painted together ------------------------------------------


def paint():
    """Paints the diffuse, combined lights, and engine layer in one pass, so
    a lit window's glow is placed by the same code that painted the window."""
    d = Px(TEX, background=BASE)
    l = Px(TEX)
    e = Px(TEX)

    # Saucer cap: blue plate disc, two ring frames, a gray armor hub, riveted
    # and asymmetrically panelled.
    cx, cy = 64, 64
    d.shape(cx - 58, cy - 58, circle_mask(58), P_BLUE, line=OUTLINE)
    d.frame(cx - 46, cy - 46, octagon_mask(46), OUTLINE)
    d.frame(cx - 28, cy - 28, octagon_mask(28), OUTLINE)
    rivet_ring(d, cx, cy, 52, 12, offset=0.1)
    rivet_ring(d, cx, cy, 37, 8, offset=0.4)
    d.shape(cx - 16, cy - 16, octagon_mask(16), GRAY_D, line=OUTLINE)
    d.rivet_row(cx - 10, cy - 13, 4, 7, OUTLINE)
    d.rivet_row(cx - 10, cy + 12, 4, 7, OUTLINE)
    d.shape(cx - 7, cy - 7, octagon_mask(7), GRAY, line=OUTLINE)
    d.stamp(cx - 1, cy - 1, octagon_mask(1), DEEP)
    # Inner ring details.
    d.shape(40, 30, rect_mask(14, 10, (2, 0, 0, 2)), B2, line=OUTLINE)
    d.shape(84, 76, rect_mask(12, 9), GRAY_D, line=OUTLINE)
    d.rivet_row(86, 78, 3, 4, OUTLINE)
    window_run(d, l, 50, 96, 3, 3)
    window_run(d, l, 88, 46, 3, 3, vertical=True)
    d.vline(76, 30, 7, ACCENT)
    # Outer ring details.
    d.frame(56, 10, rect_mask(16, 9, (0, 3, 3, 0)), OUTLINE)
    d.frame(16, 74, rect_mask(10, 9), OUTLINE)
    d.shape(96, 88, rect_mask(9, 7), MAUVE, line=OUTLINE)
    window_run(d, l, 30, 40, 2, 3)
    window_run(d, l, 84, 22, 3, 3)
    d.fill((44, 108, 50, 111), RED)
    d.frame(43, 107, rect_mask(8, 5), OUTLINE)

    # Saucer rim wall: blue band, rivets under the lip, a sparse window row.
    d.shape(4, 130, rect_mask(120, 18), P_BLUE, line=OUTLINE)
    d.rivet_row(10, 133, 16, 7, OUTLINE)
    window_run(d, l, 14, 138, 18, 6)
    d.vline(46, 132, 5, ACCENT)
    d.vline(94, 132, 5, ACCENT)

    # Nacelle cap: armor slab, aft at the rect's top. A lit left face, a
    # ladder of intake ribs, riveted seams, one accent strip.
    d.shape(132, 4, rect_mask(32, 120, (2, 2, 5, 5)), GRAY_D, line=OUTLINE)
    d.fill((134, 8, 139, 118), GRAY)
    d.ribs((141, 10, 159, 34), GRAY, GRAY_D, period=3)
    d.hline(134, 40, 26, DEEP)
    d.rivet_row(136, 43, 5, 6, OUTLINE)
    d.hline(134, 92, 26, DEEP)
    d.rivet_row(136, 95, 5, 6, OUTLINE)
    d.vline(154, 46, 40, ACCENT)
    d.speckle((134, 42, 162, 118), {GRAY_D: GRAY_D_WORN}, 0.05, RNG)

    # Nacelle flank: armor with the long deep groove and a bright leader.
    d.shape(4, 154, rect_mask(120, 24, (3, 3, 3, 3)), GRAY_D, line=OUTLINE)
    d.fill((10, 162, 112, 169), DEEP)
    d.hline(14, 165, 30, ACCENT)
    d.rivet_row(12, 157, 14, 8, OUTLINE)
    window_run(d, l, 100, 173, 2, 4)
    d.speckle((6, 156, 122, 176), {GRAY_D: GRAY_D_WORN}, 0.04, RNG)

    # Spine cap: quiet blue deck, armored walkway, vent ladder.
    d.shape(172, 4, rect_mask(64, 60, (3, 3, 2, 2)), B2, line=OUTLINE)
    d.shape(197, 10, rect_mask(14, 44, (2, 2, 2, 2)), GRAY_D, line=OUTLINE)
    d.rivet_row(200, 13, 3, 4, OUTLINE)
    d.rivet_row(200, 50, 3, 4, OUTLINE)
    d.ribs((176, 44, 190, 56), B2, DEEP, period=2)
    window_run(d, l, 190, 16, 3, 9, vertical=True)
    d.hline(214, 24, 16, DEEP)
    d.rivet_row(216, 27, 3, 5, OUTLINE)

    # Spine walls: blue band with a short window run.
    d.shape(172, 70, rect_mask(64, 16), B2, line=OUTLINE)
    window_run(d, l, 196, 77, 4, 6)
    d.hline(176, 73, 12, DEEP)

    # Engineering body cap: armor base, blue quarter panel, machinery.
    d.shape(172, 94, rect_mask(64, 60, (2, 2, 4, 4)), GRAY_D, line=OUTLINE)
    d.fill((175, 97, 180, 150), GRAY)
    d.shape(184, 100, rect_mask(22, 18, (0, 4, 0, 0)), P_BLUE, line=OUTLINE)
    window_run(d, l, 188, 104, 3, 4)
    d.fill((222, 100, 232, 108), RED)
    d.frame(221, 99, rect_mask(12, 10), OUTLINE)
    d.dash(222, 100, 10, RED_D)
    d.ribs((214, 134, 232, 148), GRAY, GRAY_D, period=3)
    d.rivet_row(184, 142, 4, 6, OUTLINE)
    d.hline(182, 126, 34, DEEP)
    d.rivet_row(186, 129, 5, 6, OUTLINE)
    d.shape(210, 112, rect_mask(10, 8), MAUVE, line=OUTLINE)
    d.speckle((174, 96, 234, 152), {GRAY_D: GRAY_D_WORN}, 0.04, RNG)

    # Body walls: blue band with the engineering window run.
    d.shape(172, 160, rect_mask(64, 16), P_BLUE, line=OUTLINE)
    window_run(d, l, 182, 167, 8, 6)
    d.rivet_row(178, 162, 8, 7, OUTLINE)

    # Pylons: armor, swept, one deep stripe and a riveted edge.
    d.shape(172, 182, rect_mask(64, 32, (0, 10, 0, 10)), GRAY_D, line=OUTLINE)
    d.fill((176, 186, 218, 190), GRAY)
    d.fill((178, 196, 224, 200), DEEP)
    d.rivet_row(180, 204, 6, 7, OUTLINE)
    d.speckle((174, 184, 232, 212), {GRAY_D: GRAY_D_WORN}, 0.04, RNG)

    # Bridge: blue octagon cap over an armor core.
    d.shape(132, 132, octagon_mask(14), P_BLUE, line=OUTLINE)
    d.shape(143, 143, octagon_mask(5), GRAY_D, line=OUTLINE)
    d.put(148, 140, YELLOW)
    d.shape(132, 170, rect_mask(32, 16), P_BLUE, line=OUTLINE)
    window_run(d, l, 138, 177, 4, 6, lit_every=1)

    # Nacelle stern: the R1 red engine bell, glowing in the engine layer.
    red_bell(d, e, 132, 192, 32, 24, 7)

    # Nacelle bow: gray intake dome, unlit.
    d.shape(132, 222, rect_mask(32, 24, (3, 3, 3, 3)), GRAY_D, line=OUTLINE)
    d.shape(142, 228, octagon_mask(6), GRAY, line=SILVER, width=1)
    d.stamp(146, 232, octagon_mask(2), DEEP)
    d.rivet_row(136, 226, 4, 7, OUTLINE)

    # Body stern: deep shuttle bay between two red impulse housings whose
    # cores glow in the hull lights layer.
    d.shape(172, 220, rect_mask(64, 24), GRAY_D, line=OUTLINE)
    d.shape(192, 224, rect_mask(24, 16, (2, 2, 0, 0)), DEEP, line=OUTLINE)
    d.ribs((196, 227, 212, 237), GRAY_D, DEEP, period=2, vertical=True)
    for bx in (177, 219):
        d.fill((bx, 226, bx + 10, 238), RED)
        d.frame(bx - 1, 225, rect_mask(12, 14), OUTLINE)
        d.dash(bx, 226, 10, RED_D)
        d.dash(bx, 237, 10, RED_D)
        d.fill((bx + 3, 230, bx + 7, 234), RED_SH)
        l.fill((bx + 4, 231, bx + 6, 233), GLOW_RED)

    d.bevel(BEVEL_DARK, BEVEL_LIGHT, BEVEL_SHADE)

    # The combined lights map is the hull layer plus the engine layer, the
    # way the R1 sheets keep a separate em_eng_glow alongside em_hull.
    for i, px in enumerate(e.px):
        if px[:3] != (0, 0, 0):
            l.px[i] = px
    return d, l, e


# ---- mesh -------------------------------------------------------------------


def build_mesh():
    o = Obj(MESH_OUT)
    # Saucer, forward and dominant.
    slab(o, disc_outline(0.0, 1.55, 1.32, 1.12, 16), 0.10, 0.42,
         R_SAUCER, R_SAUCER_RIM, TEX)
    # Bridge blister.
    slab(o, disc_outline(0.0, 1.62, 0.30, 0.26, 8), 0.42, 0.56,
         R_BRIDGE, R_BRIDGE_SIDE, TEX)
    # Angular spine running aft.
    slab(o, [(-0.34, 0.62), (0.34, 0.62), (0.24, -1.20), (-0.24, -1.20)],
         0.14, 0.38, R_SPINE, R_SPINE_SIDE, TEX)
    # Engineering body with a cut stern carrying the shuttle bay.
    slab(o, [(-0.46, -0.60), (0.46, -0.60), (0.38, -1.72), (-0.38, -1.72)],
         0.02, 0.44, R_BODY, R_BODY_SIDE, TEX, rect_aft=R_BODY_AFT)
    # Pylons, swept back and rising outboard.
    slab(o, [(-0.44, -0.55), (-0.30, -0.72), (-1.02, -1.30), (-1.16, -1.10)],
         0.30, 0.46, R_PYLON, R_PYLON, TEX)
    slab(o, [(0.30, -0.72), (0.44, -0.55), (1.16, -1.10), (1.02, -1.30)],
         0.30, 0.46, R_PYLON, R_PYLON, TEX)
    # Nacelles, above the deck line, blunt bow and cut stern.
    for side in (-1.0, 1.0):
        cx = 1.12 * side
        slab(o, [(cx - 0.17, 0.72), (cx + 0.17, 0.72),
                 (cx + 0.21, -1.62), (cx - 0.21, -1.62)],
             0.46, 0.74, R_NACELLE_TOP, R_NACELLE_SIDE, TEX,
             rect_aft=R_NACELLE_AFT, rect_fore=R_NACELLE_FORE)
    o.write("hull_frigate.obj", "Okinawa inspired frigate, nose at +Z, atlas mapped")


def main():
    os.makedirs(MESH_OUT, exist_ok=True)
    os.makedirs(TEX_OUT, exist_ok=True)
    build_mesh()
    sheet, lit_sheet = check_palette()
    d, l, e = paint()
    verify(d, l, e, sheet, lit_sheet, ALL_RECTS, TEX, background=BASE,
           lit_budget=(0.0008, 0.02))
    d.save(os.path.join(TEX_OUT, "hull_frigate_diffuse.png"))
    l.save(os.path.join(TEX_OUT, "hull_frigate_lights.png"))
    e.save(os.path.join(TEX_OUT, "hull_frigate_engines.png"))


if __name__ == "__main__":
    main()
