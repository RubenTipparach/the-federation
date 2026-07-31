#!/usr/bin/env python3
# Generates the committed raider: mesh, pixel art diffuse atlas, and emissive
# lights maps, in the style of the author's R6 starship sheets. This is the
# Kthaari hull, flown by the Bloodletter and the Talon.
#
# Style source: docs/examples/ship-art/old_ships/R6-Starship-A. The palette is
# loaded from those PNGs at build time and the finished maps are verified
# against them before anything is written, the same gates as the frigate.
#
# The R6 look, measured from the sheets and refined by critique passes:
#   - authored at the sheets' native 128 grid and exported 2x nearest
#   - the hull is the purple-black (23,14,25) family with (8,5,9) deep black
#     outlines and purple panel work; (12,12,12) is the sheet's background,
#     not a hull color, and is not used
#   - the prow is massed steel armor: (124,148,161) fields with (160,185,186)
#     ridge lines, a few (192,209,204) top highlights, (101,115,140) shadow
#   - wings are mostly dark hull with green panels toward the trailing half
#   - the signature warm exhaust trails taper and jitter, rust into orange
#     into cream with checkerboard dither, and every warm pixel is emissive:
#     the lights map repeats the diffuse pixel exactly (the R6 parity law)
#   - engine grilles are checker dithered vertical gradients from dark purple
#     to lit steel, using the seven colors of R6's em_engine, and they are
#     large: they carry the aft read
#   - windows are a few 1px yellow dots
#
# Layering note: R6 keeps em_lighting and em_engine disjoint because its
# pipeline stacks them additively. Godot's StandardMaterial3D has a single
# emission slot, so the committed lights map is the UNION of the hull layer
# and the engine layer, and the engines map remains the separable throttle
# layer (a strict subset). Same treatment as the frigate.
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

# Authored at the R6 sheets' native grid, exported 2x for the engine.
TEX = 128
SCALE = 2
RNG = random.Random(6)

# Roles into the R6 palette, asserted against the sheets at build time.
HULL = (23, 14, 25)            # the purple-black hull
OUTLINE = (8, 5, 9)            # deep black outlines
PANEL = (47, 33, 59)           # purple panel lines and ridges
PLUM = (59, 33, 55)            # dark plum, grille gradient step
PLATE = (67, 58, 96)           # purple plate faces
PLATE_L = (79, 82, 119)        # lighter purple
STEEL = (101, 115, 140)        # armor shadow
STEEL_L = (124, 148, 161)      # armor field
LIGHT = (160, 185, 186)        # armor ridge lines
PALE = (192, 209, 204)         # rare top highlights
STEEL_D = (57, 67, 77)         # deep armor shade
GREEN = (33, 59, 37)           # wing panels
GREEN_L = (58, 96, 74)
GREEN_D = (35, 43, 37)
ORANGE = (228, 148, 58)        # exhaust trail body
CREAM = (245, 237, 186)        # trail core
RUST = (154, 99, 72)           # trail fringe
RED = (134, 55, 47)            # warning ticks

DIFFUSE_ROLES = (
    HULL, OUTLINE, PANEL, PLUM, PLATE, PLATE_L, STEEL, STEEL_L, LIGHT, PALE,
    STEEL_D, GREEN, GREEN_L, GREEN_D, ORANGE, CREAM, RUST, RED)

GLOW_YELLOW = (255, 219, 0)    # lit windows
GRILLE_RAMP = (PANEL, PLUM, PLATE, PLATE_L, STEEL, STEEL_L)
LIGHTS_ROLES = (ORANGE, CREAM, RUST, GLOW_YELLOW) + GRILLE_RAMP

BEVEL_DARK = {OUTLINE}
BEVEL_LIGHT = {STEEL_L: LIGHT, GREEN: GREEN_L, PLATE: PLATE_L, HULL: PANEL}
BEVEL_SHADE = {STEEL_L: STEEL, GREEN: GREEN_D}

# ---- atlas layout (logical 128 grid) ----------------------------------------
R_WING = (2, 2, 50, 28)
R_WING_EDGE = (2, 31, 50, 37)
R_WING_TRAIL = (2, 40, 50, 47)
R_BODY = (2, 50, 34, 86)
R_BODY_SIDE = (2, 89, 34, 97)
R_BODY_AFT = (2, 100, 34, 112)
R_HEAD = (54, 2, 74, 24)
R_HEAD_SIDE = (54, 27, 74, 35)
R_BOOM = (78, 2, 90, 38)
R_BOOM_SIDE = (94, 2, 126, 10)
R_POD = (78, 42, 92, 84)
R_POD_AFT = (96, 42, 110, 54)
R_POD_FORE = (96, 57, 110, 69)
R_POD_SIDE = (78, 87, 126, 95)
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


# ---- R6 painting vocabulary -------------------------------------------------


def window_dot(d, l, x, y, lit=True):
    d.put(x, y, GLOW_YELLOW if lit else LIGHT)
    if lit:
        l.put(x, y, GLOW_YELLOW)


def trail_band(d, l, x0, y0, x1, y1):
    """The R6 exhaust trail on a wall strip: a plume that is fat in the
    middle of the run and tapers to both ends, rust into orange into cream,
    with jittered checkerboard edges. Warm pixels go to the lights map too;
    parity() later makes them exact."""
    w = x1 - x0
    h = y1 - y0
    cy = (y0 + y1) // 2
    for x in range(x0, x1):
        t = (x - x0) / float(w - 1)
        half = 1.0 + (h / 2.0 - 1.0) * (1.0 - abs(2.0 * t - 1.0)) \
            + RNG.uniform(-0.5, 0.5)
        half = max(1.0, half)
        for y in range(y0, y1):
            dy = abs(y - cy)
            if dy > half:
                continue
            depth = 1.0 - dy / (h / 2.0)
            if depth > 0.75:
                c = CREAM if (x + y) % 2 == 0 or depth > 0.9 else ORANGE
            elif depth > 0.45:
                c = ORANGE
            elif depth > 0.3:
                c = ORANGE if (x + y) % 2 == 0 else RUST
            else:
                c = RUST
            d.put(x, y, c)
            l.put(x, y, c)


def fringe(d, l, x0, y, length):
    """The dithered warm fringe on a wing cap's trailing edge; emissive like
    every warm pixel in R6."""
    for x in range(x0, x0 + length):
        top = ORANGE if (x + y) % 2 == 0 else RUST
        d.put(x, y, top)
        l.put(x, y, top)
        d.put(x, y + 1, RUST)
        l.put(x, y + 1, RUST)


def engine_grille(d, layers, rect):
    """The R6 engine grille: a checker dithered vertical gradient from dark
    purple at the edges to lit steel at the center, inside a deep frame. The
    glow layers receive the same pixels; parity() keeps them exact."""
    x0, y0, x1, y1 = rect
    d.fill(rect, OUTLINE)
    ramp = GRILLE_RAMP
    for y in range(y0 + 1, y1 - 1):
        t = 1.0 - abs(2.0 * (y - y0 - 1) / float(y1 - y0 - 3) - 1.0)
        pos = t * (len(ramp) - 1)
        lo = int(pos)
        hi = min(lo + 1, len(ramp) - 1)
        for x in range(x0 + 1, x1 - 1):
            frac = pos - lo
            use_hi = ((x + y) % 2 == 0 and frac > 0.25) or frac > 0.75
            c = ramp[hi] if use_hi else ramp[lo]
            d.put(x, y, c)
            for layer in layers:
                layer.put(x, y, c)


# ---- the atlases, painted together ------------------------------------------


def paint():
    d = Px(TEX, background=(0, 0, 0))
    l = Px(TEX)
    e = Px(TEX)

    # ---- base structure, beveled afterwards --------------------------------

    # Wing cap: dark hull forward, green panels toward the trailing half,
    # swept feather seams, a steel root plate.
    d.shape(2, 2, rect_mask(48, 26, (0, 7, 5, 0)), HULL, line=OUTLINE)
    d.stamp(6, 14, rect_mask(34, 10, (6, 0, 0, 2)), GREEN)
    d.stamp(26, 6, rect_mask(16, 8, (4, 2, 0, 0)), GREEN)
    for sx in (16, 26, 36):
        for k in range(6):
            d.put(sx - k, 16 + k, GREEN_D)
    d.shape(36, 16, rect_mask(10, 8, (0, 3, 0, 0)), STEEL_L, line=OUTLINE)
    d.put(38, 19, RED)
    d.put(40, 19, RED)
    d.hline(8, 8, 10, PANEL)

    # Wing leading edge wall: quiet dark band.
    d.shape(2, 31, rect_mask(48, 6), HULL, line=OUTLINE)
    d.hline(5, 33, 42, PANEL)

    # Body cap: purple-black hull, panel work, a dithered spine, a green
    # quarter.
    d.shape(2, 50, rect_mask(32, 36, (3, 3, 2, 2)), HULL, line=OUTLINE)
    d.stamp(13, 54, rect_mask(8, 26, (1, 1, 1, 1)), PLATE)
    d.frame(12, 53, rect_mask(10, 28), PANEL)
    d.dither((15, 58, 19, 76), PLATE, PANEL)
    d.stamp(5, 56, rect_mask(6, 11), GREEN)
    d.shape(24, 59, rect_mask(7, 9), STEEL_L, line=OUTLINE)
    d.put(26, 62, RED)
    d.hline(5, 71, 7, PANEL)
    d.vline(26, 72, 8, PANEL)
    d.put(7, 80, PALE)

    # Body walls: dark band with a purple ridge.
    d.shape(2, 89, rect_mask(32, 8), HULL, line=OUTLINE)
    d.hline(4, 91, 28, PANEL)

    # Body stern shell; the maw and grilles come after the bevel.
    d.shape(2, 100, rect_mask(32, 12), HULL, line=OUTLINE)

    # Head cap: massed steel armor over the dark hull, ridge lines, a rare
    # pale highlight, warning ticks.
    d.shape(54, 2, rect_mask(20, 22, (4, 4, 1, 1)), HULL, line=OUTLINE)
    d.stamp(57, 5, rect_mask(14, 12, (3, 3, 0, 0)), STEEL_L)
    d.hline(59, 10, 10, LIGHT)
    d.hline(58, 14, 12, STEEL)
    d.put(60, 6, PALE)
    d.put(61, 6, PALE)
    d.stamp(58, 18, rect_mask(12, 3), STEEL_L)
    d.put(60, 21, RED)
    d.put(63, 21, RED)

    # Head walls: dark band with a steel visor strip.
    d.shape(54, 27, rect_mask(20, 8), HULL, line=OUTLINE)
    d.stamp(57, 29, rect_mask(14, 3), STEEL_L)
    d.hline(57, 29, 14, LIGHT)

    # Boom cap: rails and rungs over dark hull.
    d.shape(78, 2, rect_mask(12, 36, (1, 1, 1, 1)), HULL, line=OUTLINE)
    d.vline(80, 4, 32, PLATE)
    d.vline(87, 4, 32, PLATE)
    for y in range(6, 35, 4):
        d.hline(82, y, 4, PANEL)

    # Boom walls.
    d.shape(94, 2, rect_mask(32, 8), HULL, line=OUTLINE)
    d.hline(96, 4, 28, PANEL)
    d.dots(98, 6, 5, 6, PLATE)

    # Pod cap shell and steel nose plate; the glowing mid run comes later.
    d.shape(78, 42, rect_mask(14, 42, (1, 1, 3, 3)), HULL, line=OUTLINE)
    d.stamp(80, 72, rect_mask(10, 8, (0, 0, 2, 2)), STEEL_L)
    d.hline(81, 72, 8, LIGHT)
    d.hline(80, 68, 10, PANEL)
    d.put(81, 70, RED)

    # Pod stern shell.
    d.shape(96, 42, rect_mask(14, 12), HULL, line=OUTLINE)

    # Pod bow: steel intake maw.
    d.shape(96, 57, rect_mask(14, 12, (2, 2, 2, 2)), STEEL_L, line=OUTLINE)
    d.stamp(100, 60, octagon_mask(3), STEEL_D)
    d.put(103, 63, OUTLINE)
    d.put(98, 66, RED)

    # Pod walls: dark band with a purple ridge.
    d.shape(78, 87, rect_mask(48, 8), HULL, line=OUTLINE)
    d.hline(80, 89, 44, PANEL)

    d.bevel(BEVEL_DARK, BEVEL_LIGHT, BEVEL_SHADE)

    # ---- glow features, flat and painted after the bevel -------------------

    # The warm fringe on the wing cap and the trailing exhaust plume, over a
    # flat hull-dark base so the wall face stays hull colored around it.
    fringe(d, l, 5, 24, 36)
    d.fill((2, 40, 50, 47), HULL)
    trail_band(d, l, 2, 40, 50, 47)

    # Body stern: orange impulse maw between two big purple grilles.
    for canvas in (d, l):
        canvas.fill((14, 103, 22, 104), RUST)
        canvas.dither((14, 104, 22, 105), RUST, ORANGE)
        canvas.fill((14, 105, 22, 107), ORANGE)
        canvas.dither((14, 107, 22, 108), ORANGE, CREAM)
        canvas.fill((14, 108, 22, 109), CREAM)
    engine_grille(d, (e, l), (4, 101, 13, 111))
    engine_grille(d, (e, l), (23, 101, 32, 111))

    # The pod cap's long dithered run is a glowing grille, like R6's nacelle
    # columns, and the pod stern grille fills its face.
    engine_grille(d, (e, l), (80, 47, 90, 65))
    engine_grille(d, (e, l), (97, 43, 109, 53))

    # Windows: a few 1px yellow dots.
    window_dot(d, l, 22, 11)
    window_dot(d, l, 23, 53)
    window_dot(d, l, 7, 75)
    window_dot(d, l, 10, 94)
    window_dot(d, l, 24, 94, lit=False)
    window_dot(d, l, 66, 19)
    window_dot(d, l, 61, 33)
    window_dot(d, l, 84, 18)
    window_dot(d, l, 85, 69)
    window_dot(d, l, 90, 92)
    window_dot(d, l, 112, 92, lit=False)

    # The R6 parity law: every lit pixel glows with its own painted color.
    l.parity(d)
    e.parity(d)
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
           lit_budget=(0.002, 0.05))
    d.save(os.path.join(TEX_OUT, "hull_raider_diffuse.png"), scale=SCALE)
    l.save(os.path.join(TEX_OUT, "hull_raider_lights.png"), scale=SCALE)
    e.save(os.path.join(TEX_OUT, "hull_raider_engines.png"), scale=SCALE)


if __name__ == "__main__":
    main()
