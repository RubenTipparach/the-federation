#!/usr/bin/env python3
# Generates the committed raider: mesh, pixel art diffuse atlas, and emissive
# lights maps, in the style of the author's R6 starship sheets. This is the
# Kthaari hull, flown by the Bloodletter and the Talon.
#
# Style source: docs/examples/ship-art/old_ships/R6-Starship-A. The palette is
# loaded from those PNGs at build time and the finished maps are verified
# against them before anything is written, the same gates as the frigate.
#
# The R6 look, measured from the sheets:
#   - near black hull pieces edged in a purple-dark 1px outline, with purple
#     panel lines and plates; the ship is mostly shadow
#   - steel blue armor on the prow, dark green surfaces on the wings
#   - the signature: broad warm exhaust trails, rust into orange into cream,
#     stepped with checkerboard dither, baked in the diffuse AND glowing in
#     the lighting map with the same colors
#   - engine grilles are dithered purple and steel columns, glowing in the
#     separate engine layer the way R6 keeps em_engine apart from em_lighting
#   - windows are sparse single yellow pixels
#
# Silhouette is the predator grammar of docs/12: a narrow armored head on a
# thin boom, mass aft, swept wings carrying the exhaust trails, and wingtip
# pods. No geometry or pixels from any reference are copied.
#
# Per CLAUDE.md sections 2 and 3 this writes .obj and .png to disk. Run it and
# commit what it writes. Preview with tools/render_preview.py.
#
# Usage: python3 tools/gen_ship_raider.py

import os
import random

from shiplib import (Px, Obj, octagon_mask, read_png_colors, rect_mask, slab,
                     verify)

HERE = os.path.dirname(os.path.abspath(__file__))
MESH_OUT = os.path.join(HERE, "..", "assets", "meshes")
TEX_OUT = os.path.join(HERE, "..", "assets", "textures")
ART = os.path.join(HERE, "..", "docs", "examples", "ship-art", "old_ships",
                   "R6-Starship-A")
REF_DIFF = os.path.join(ART, "R6_Starship_A_Diffuse.png")
REF_EM = os.path.join(ART, "R6_Starship_A_em_lighting.png")
REF_ENG = os.path.join(ART, "R6_Starship_A_em_engine.png")

TEX = 256
RNG = random.Random(6)

# Roles into the R6 palette, asserted against the sheets at build time.
HULL = (12, 12, 12)            # the near black hull
OUTLINE = (23, 14, 25)         # purple-dark outlines
PANEL = (47, 33, 59)           # purple panel lines and ridges
PLATE = (67, 58, 96)           # purple plate faces
PLATE_L = (79, 82, 119)        # lighter purple
STEEL = (101, 115, 140)        # prow armor
STEEL_L = (124, 148, 161)      # its lit ridge
STEEL_D = (57, 67, 77)         # its shade
GREEN = (33, 59, 37)           # wing surfaces
GREEN_L = (58, 96, 74)
GREEN_D = (35, 43, 37)
ORANGE = (228, 148, 58)        # exhaust trail body
CREAM = (245, 237, 186)        # trail core
RUST = (154, 99, 72)           # trail fringe
LIGHT = (160, 185, 186)        # small bright greebles
RED = (134, 55, 47)            # warning ticks

DIFFUSE_ROLES = (
    HULL, OUTLINE, PANEL, PLATE, PLATE_L, STEEL, STEEL_L, STEEL_D, GREEN,
    GREEN_L, GREEN_D, ORANGE, CREAM, RUST, LIGHT, RED)

GLOW_ORANGE = ORANGE           # the trails glow with their own colors
GLOW_CREAM = CREAM
GLOW_RUST = RUST
GLOW_YELLOW = (255, 219, 0)    # lit windows
ENG_A = PLATE_L                # engine grille glow, from em_engine
ENG_B = STEEL_L
ENG_C = STEEL
LIGHTS_ROLES = (GLOW_ORANGE, GLOW_CREAM, GLOW_RUST, GLOW_YELLOW,
                ENG_A, ENG_B, ENG_C)

BEVEL_DARK = {OUTLINE}
BEVEL_LIGHT = {STEEL: STEEL_L, GREEN: GREEN_L, PLATE: PLATE_L, HULL: PANEL}
BEVEL_SHADE = {STEEL: STEEL_D, GREEN: GREEN_D}

# ---- atlas layout -----------------------------------------------------------
R_WING = (4, 4, 100, 56)
R_WING_EDGE = (4, 62, 100, 74)
R_WING_TRAIL = (4, 80, 100, 94)
R_BODY = (4, 100, 68, 172)
R_BODY_SIDE = (4, 178, 68, 194)
R_BODY_AFT = (4, 200, 68, 224)
R_HEAD = (108, 4, 148, 48)
R_HEAD_SIDE = (108, 54, 148, 70)
R_BOOM = (156, 4, 180, 76)
R_BOOM_SIDE = (188, 4, 252, 20)
R_POD = (156, 84, 184, 168)
R_POD_AFT = (192, 84, 220, 108)
R_POD_FORE = (192, 114, 220, 138)
R_POD_SIDE = (156, 174, 252, 190)
ALL_RECTS = (
    R_WING, R_WING_EDGE, R_WING_TRAIL, R_BODY, R_BODY_SIDE, R_BODY_AFT,
    R_HEAD, R_HEAD_SIDE, R_BOOM, R_BOOM_SIDE, R_POD, R_POD_AFT, R_POD_FORE,
    R_POD_SIDE)


def check_palette():
    sheet = read_png_colors(REF_DIFF)
    for role in DIFFUSE_ROLES:
        assert role in sheet, "diffuse role %r is not an R6 color" % (role,)
    lit = read_png_colors(REF_EM) | read_png_colors(REF_ENG)
    for role in LIGHTS_ROLES:
        assert role in lit, "lights role %r is not an R6 glow color" % (role,)
    return sheet, lit


# ---- painting helpers -------------------------------------------------------


def window_dot(d, l, x, y, lit=True):
    d.put(x, y, GLOW_YELLOW if lit else LIGHT)
    if lit:
        l.put(x, y, GLOW_YELLOW)


def trail_band(d, l, x0, y0, x1, y1):
    """The R6 exhaust trail: rust fringe, orange body, cream core, stepped
    with checkerboard dither, identical in diffuse and lighting map."""
    h = y1 - y0
    for canvas in (d, l):
        canvas.fill((x0, y0, x1, y0 + 1), RUST)
        canvas.dither((x0, y0 + 1, x1, y0 + 3), RUST, ORANGE)
        canvas.fill((x0, y0 + 3, x1, y1 - 6), ORANGE)
        canvas.dither((x0, y1 - 6, x1, y1 - 4), ORANGE, CREAM)
        canvas.fill((x0, y1 - 4, x1, y1 - 2), CREAM)
        canvas.dither((x0, y1 - 2, x1, y1 - 1), CREAM, ORANGE)
        canvas.fill((x0, y1 - 1, x1, y1), RUST)
    assert h >= 8


def engine_grille(d, layers, x0, y0, x1, y1):
    """A dithered purple and steel engine grille; the glow layers get the
    same columns the way R6's em_engine glows its grilles."""
    d.fill((x0, y0, x1, y1), OUTLINE)
    x = x0 + 2
    toggle = False
    while x + 2 <= x1 - 2:
        a, b = (ENG_A, ENG_C) if toggle else (ENG_B, ENG_A)
        d.dither((x, y0 + 2, x + 2, y1 - 2), a, b)
        for layer in layers:
            layer.dither((x, y0 + 2, x + 2, y1 - 2), a, b)
        toggle = not toggle
        x += 3


# ---- the atlases, painted together ------------------------------------------


def paint():
    d = Px(TEX, background=(0, 0, 0))
    l = Px(TEX)
    e = Px(TEX)

    # Wing cap: dark green surfaces, swept 45 degree feather seams, a steel
    # root plate, and a hot dithered fringe along the trailing edge.
    d.shape(4, 4, rect_mask(96, 52, (0, 14, 10, 0)), GREEN, line=OUTLINE)
    for i, sx in enumerate((26, 44, 62, 80)):
        for k in range(10 + i * 2):
            d.put(sx - k, 10 + k, OUTLINE)
    d.fill((10, 8, 34, 20), GREEN_D)
    d.frame(9, 7, rect_mask(27, 15), OUTLINE)
    d.shape(70, 30, rect_mask(22, 16, (0, 6, 0, 0)), STEEL, line=OUTLINE)
    d.dots(74, 34, 3, 5, RED)
    d.dither((8, 46, 78, 49), RUST, ORANGE)
    d.fill((8, 49, 78, 51), RUST)
    window_dot(d, l, 40, 26)
    window_dot(d, l, 46, 26, lit=False)

    # Wing leading edge wall: quiet armored band.
    d.shape(4, 62, rect_mask(96, 12), HULL, line=OUTLINE)
    d.hline(8, 65, 88, PANEL)
    d.dots(12, 68, 10, 9, PLATE, w=2)

    # Wing trailing wall: the signature exhaust trail.
    trail_band(d, l, 4, 80, 100, 94)

    # Body cap: near black hull, purple panel work, a dithered spine, a green
    # quarter, sparse lit windows.
    d.shape(4, 100, rect_mask(64, 72, (6, 6, 4, 4)), HULL, line=OUTLINE)
    d.shape(26, 108, rect_mask(16, 52, (2, 2, 2, 2)), PLATE, line=OUTLINE)
    d.dither((30, 112, 38, 156), PLATE, PANEL)
    d.shape(10, 112, rect_mask(12, 22, (0, 2, 0, 2)), GREEN, line=OUTLINE)
    d.shape(48, 118, rect_mask(14, 18), STEEL, line=OUTLINE)
    d.dots(51, 122, 2, 5, RED)
    d.hline(10, 142, 14, PANEL)
    d.vline(52, 144, 16, PANEL)
    d.fill((14, 160, 20, 163), LIGHT)
    window_dot(d, l, 46, 106)
    window_dot(d, l, 50, 106)
    window_dot(d, l, 14, 150)

    # Body walls: hull band, purple ridge, window run.
    d.shape(4, 178, rect_mask(64, 16), HULL, line=OUTLINE)
    d.hline(8, 181, 56, PANEL)
    for i in range(6):
        window_dot(d, l, 12 + i * 9, 186, lit=(i % 2 == 0))

    # Body stern: orange impulse maw between purple grilles.
    d.shape(4, 200, rect_mask(64, 24), HULL, line=OUTLINE)
    for canvas in (d, l):
        canvas.fill((26, 206, 46, 208), RUST)
        canvas.dither((26, 208, 46, 210), RUST, ORANGE)
        canvas.fill((26, 210, 46, 214), ORANGE)
        canvas.dither((26, 214, 46, 216), ORANGE, CREAM)
        canvas.fill((26, 216, 46, 218), CREAM)
    engine_grille(d, (e, l), 8, 204, 20, 220)
    engine_grille(d, (e, l), 52, 204, 64, 220)

    # Head cap: armored steel chevrons over the dark hull.
    d.shape(108, 4, rect_mask(40, 44, (8, 8, 2, 2)), HULL, line=OUTLINE)
    d.shape(114, 8, rect_mask(28, 14, (6, 6, 0, 0)), STEEL, line=OUTLINE)
    d.shape(114, 26, rect_mask(28, 8), STEEL, line=OUTLINE)
    d.hline(118, 38, 20, PANEL)
    d.dots(120, 41, 2, 6, RED)
    window_dot(d, l, 126, 30)
    window_dot(d, l, 130, 30)

    # Head walls: hull band with a steel visor strip.
    d.shape(108, 54, rect_mask(40, 16), HULL, line=OUTLINE)
    d.fill((114, 58, 142, 62), STEEL)
    d.frame(113, 57, rect_mask(30, 6), OUTLINE)
    window_dot(d, l, 122, 66)
    window_dot(d, l, 132, 66)

    # Boom cap: rails and rungs.
    d.shape(156, 4, rect_mask(24, 72, (2, 2, 2, 2)), HULL, line=OUTLINE)
    d.vline(160, 8, 64, PLATE, t=2)
    d.vline(174, 8, 64, PLATE, t=2)
    for y in range(12, 70, 8):
        d.hline(163, y, 10, PANEL)
    window_dot(d, l, 168, 34)

    # Boom walls.
    d.shape(188, 4, rect_mask(64, 16), HULL, line=OUTLINE)
    d.hline(192, 8, 56, PANEL)
    d.dots(196, 12, 6, 9, PLATE, w=2)

    # Pod cap: dark hull, steel nose plate, dithered purple mid run.
    d.shape(156, 84, rect_mask(28, 84, (2, 2, 5, 5)), HULL, line=OUTLINE)
    d.shape(160, 146, rect_mask(20, 16, (0, 0, 3, 3)), STEEL, line=OUTLINE)
    d.dither((162, 96, 178, 130), PLATE, PANEL)
    d.frame(161, 95, rect_mask(18, 36), OUTLINE)
    d.hline(160, 136, 20, PANEL)
    d.dots(163, 139, 2, 8, RED)
    window_dot(d, l, 170, 133)

    # Pod stern: the engine grille, glowing purple and steel.
    d.shape(192, 84, rect_mask(28, 24), HULL, line=OUTLINE)
    engine_grille(d, (e, l), 196, 88, 216, 104)

    # Pod bow: steel intake maw.
    d.shape(192, 114, rect_mask(28, 24, (3, 3, 3, 3)), STEEL, line=OUTLINE)
    d.shape(199, 119, octagon_mask(7), STEEL_D, line=OUTLINE)
    d.stamp(203, 123, octagon_mask(3), OUTLINE)
    d.dots(196, 132, 2, 4, RED)

    # Pod walls: hull band, purple ridge, sparse windows.
    d.shape(156, 174, rect_mask(96, 16), HULL, line=OUTLINE)
    d.hline(160, 177, 88, PANEL)
    for i in range(4):
        window_dot(d, l, 168 + i * 18, 183, lit=(i % 2 == 0))

    d.bevel(BEVEL_DARK, BEVEL_LIGHT, BEVEL_SHADE)
    return d, l, e


# ---- mesh -------------------------------------------------------------------


def build_mesh():
    o = Obj(MESH_OUT)
    # Armored head, blunt and forward.
    slab(o, [(-0.30, 2.30), (0.30, 2.30), (0.36, 1.55), (-0.36, 1.55)],
         0.26, 0.54, R_HEAD, R_HEAD_SIDE, TEX)
    # Thin boom back to the body.
    slab(o, [(-0.15, 1.60), (0.15, 1.60), (0.17, 0.10), (-0.17, 0.10)],
         0.32, 0.50, R_BOOM, R_BOOM_SIDE, TEX)
    # Engineering body, deepest aft.
    slab(o, [(-0.55, 0.25), (0.55, 0.25), (0.44, -1.45), (-0.44, -1.45)],
         0.10, 0.54, R_BODY, R_BODY_SIDE, TEX, rect_aft=R_BODY_AFT)
    # Swept wings, thin, carrying the exhaust trails on their trailing edges.
    slab(o, [(-0.50, 0.05), (-0.32, -0.42), (-1.48, -1.18), (-1.62, -0.86)],
         0.28, 0.40, R_WING, R_WING_EDGE, TEX,
         rect_aft=R_WING_TRAIL, aft_dot=-0.7)
    slab(o, [(0.32, -0.42), (0.50, 0.05), (1.62, -0.86), (1.48, -1.18)],
         0.28, 0.40, R_WING, R_WING_EDGE, TEX,
         rect_aft=R_WING_TRAIL, aft_dot=-0.7)
    # Wingtip pods.
    for side in (-1.0, 1.0):
        cx = 1.52 * side
        slab(o, [(cx - 0.16, -0.50), (cx + 0.16, -0.50),
                 (cx + 0.20, -1.60), (cx - 0.20, -1.60)],
             0.22, 0.52, R_POD, R_POD_SIDE, TEX,
             rect_aft=R_POD_AFT, rect_fore=R_POD_FORE)
    o.write("hull_raider.obj",
            "Kthaari raider, armored head, swept wings, nose at +Z, atlas mapped")


def main():
    os.makedirs(MESH_OUT, exist_ok=True)
    os.makedirs(TEX_OUT, exist_ok=True)
    build_mesh()
    sheet, lit_sheet = check_palette()
    d, l, e = paint()
    verify(d, l, e, sheet, lit_sheet, ALL_RECTS, TEX,
           lit_budget=(0.002, 0.04))
    d.save(os.path.join(TEX_OUT, "hull_raider_diffuse.png"))
    l.save(os.path.join(TEX_OUT, "hull_raider_lights.png"))
    e.save(os.path.join(TEX_OUT, "hull_raider_engines.png"))


if __name__ == "__main__":
    main()
