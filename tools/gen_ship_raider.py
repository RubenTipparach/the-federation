#!/usr/bin/env python3
# Generates the committed raider: mesh, pixel art diffuse atlas, and emissive
# lights maps, in the style of the author's R6 starship sheets. This is the
# Kthaari hull, flown by the Bloodletter and the Talon.
#
# Color comes from the project palette in data/palette.json (CLAUDE.md 3.1):
# this file names roles, never hex values. The finished maps pass the same
# gates as the frigate before anything is written.
#
# Shape vocabulary source: docs/examples/ship-art/old_ships/R6-Starship-A.
#
# The R6 shapes, measured from the sheets and refined by critique passes:
#   - authored at the sheets' native 128 grid and exported 2x nearest
#   - a dark hull with 1px outlines and panel work one step lighter, so the
#     ship reads as mass rather than as lines
#   - the prow is massed armor: a bright field with ridge lines, a few rare
#     top highlights, and a shadow step
#   - wings are mostly hull with green panels toward the trailing half
#   - the exhaust trails taper and jitter, fringe into body into core with
#     checkerboard dither, and every lit pixel is emissive: the lights map
#     repeats the diffuse pixel exactly (the R6 parity law)
#   - engine grilles are checker dithered vertical gradients along a six step
#     ramp, and they are large: they carry the aft read
#   - windows are a few 1px dots
#
# Where the R6 sheets are grayscale-dark, this ship is not: the Kthaari hull
# is rust, its plates bronze and gold, its armor warm and pale, and its
# drives deliberately COOL. That inversion is the point. The Federation
# frigate is a cool blue hull with hot red drives, so at tactical scale the
# two fleets read as opposites by temperature alone, before any marking or
# silhouette is resolved (docs/12 section 6).
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

from shiplib import Px, Obj, load_palette, octagon_mask, rect_mask, slab, verify

HERE = os.path.dirname(os.path.abspath(__file__))
MESH_OUT = os.path.join(HERE, "..", "assets", "meshes")
TEX_OUT = os.path.join(HERE, "..", "assets", "textures")
PALETTE = os.path.join(HERE, "..", "data", "palette.json")

# Authored at the R6 sheets' native grid, exported 2x for the engine.
## How many pieces a destroyed hull comes apart into. One number for every
## ship, so the wreck scene's chunk slots line up whatever died.
FRAGMENTS = 8

TEX = 128
SCALE = 2
# The two ships this painter makes: role map name, and the texture prefix.
# The Talon is the Bloodletter's escort, same hull and same marks in duller
# paint, so it gets a role map rather than a painter of its own
# (CLAUDE.md 4.1). Adding a third Kthaari ship is a line here plus a map.
VARIANTS = (("raider", "hull_raider", 6), ("talon", "hull_talon", 19))

RNG = random.Random(6)

# Roles, resolved through data/palette.json. Nothing here is a hex value.
ROLE, ALLOWED = load_palette(PALETTE, "raider")
HULL = ROLE["hull"]            # the rust hull, the ship's primary color
OUTLINE = ROLE["outline"]      # darkest step: silhouette and frames
PANEL = ROLE["panel"]          # panel lines and hull ridges
PLATE = ROLE["plate"]          # plate faces and dithered runs
PLATE_L = ROLE["plate_light"]
STEEL_L = ROLE["armor"]        # armor field
LIGHT = ROLE["armor_ridge"]    # armor ridge lines
PALE = ROLE["armor_pale"]      # rare top highlights
STEEL = ROLE["armor_shadow"]
STEEL_D = ROLE["armor_deep"]
GREEN = ROLE["green"]          # wing panels
GREEN_L = ROLE["green_light"]
GREEN_D = ROLE["green_dark"]
PLUME_EDGE = ROLE["plume_edge"]  # exhaust fringe
PLUME_MID = ROLE["plume_mid"]    # exhaust body
PLUME_CORE = ROLE["plume_core"]  # exhaust core
MARK = ROLE["mark"]            # warning ticks
GLOW_YELLOW = ROLE["window"]   # lit windows

# The grille gradient, ordered dark to light; the painter dithers between
# neighbouring steps.
GRILLE_RAMP = ROLE["grille_ramp"]

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


# ---- R6 painting vocabulary -------------------------------------------------


def window_dot(d, l, x, y, lit=True):
    d.put(x, y, GLOW_YELLOW if lit else LIGHT)
    if lit:
        l.put(x, y, GLOW_YELLOW)


def trail_band(d, l, x0, y0, x1, y1):
    """The R6 exhaust trail on a wall strip: a plume that is fat in the
    middle of the run and tapers to both ends, fringe into body into core,
    with jittered checkerboard edges. Lit pixels go to the lights map too;
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
                c = PLUME_CORE if (x + y) % 2 == 0 or depth > 0.9 else PLUME_MID
            elif depth > 0.45:
                c = PLUME_MID
            elif depth > 0.3:
                c = PLUME_MID if (x + y) % 2 == 0 else PLUME_EDGE
            else:
                c = PLUME_EDGE
            d.put(x, y, c)
            l.put(x, y, c)


def fringe(d, l, x0, y, length):
    """The dithered plume fringe on a wing cap's trailing edge; emissive like
    every lit pixel in R6."""
    for x in range(x0, x0 + length):
        top = PLUME_MID if (x + y) % 2 == 0 else PLUME_EDGE
        d.put(x, y, top)
        l.put(x, y, top)
        d.put(x, y + 1, PLUME_EDGE)
        l.put(x, y + 1, PLUME_EDGE)


def engine_grille(d, layers, rect):
    """The R6 engine grille: a checker dithered vertical gradient, darkest at
    the edges and brightest at the center, inside a deep frame. The glow
    layers receive the same pixels; parity() keeps them exact."""
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
    # The atlas gutter is the palette's black rather than pure black, so any
    # bleed at a UV seam stays in family, the way the frigate's gutter is its
    # hull base.
    d = Px(TEX, background=OUTLINE)
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
    d.put(38, 19, MARK)
    d.put(40, 19, MARK)
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
    d.put(26, 62, MARK)
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
    d.put(60, 21, MARK)
    d.put(63, 21, MARK)

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
    d.put(81, 70, MARK)

    # Pod stern shell.
    d.shape(96, 42, rect_mask(14, 12), HULL, line=OUTLINE)

    # Pod bow: steel intake maw.
    d.shape(96, 57, rect_mask(14, 12, (2, 2, 2, 2)), STEEL_L, line=OUTLINE)
    d.stamp(100, 60, octagon_mask(3), STEEL_D)
    d.put(103, 63, OUTLINE)
    d.put(98, 66, MARK)

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
        canvas.fill((14, 103, 22, 104), PLUME_EDGE)
        canvas.dither((14, 104, 22, 105), PLUME_EDGE, PLUME_MID)
        canvas.fill((14, 105, 22, 107), PLUME_MID)
        canvas.dither((14, 107, 22, 108), PLUME_MID, PLUME_CORE)
        canvas.fill((14, 108, 22, 109), PLUME_CORE)
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
    o.write_fragments("hull_raider", FRAGMENTS, "Kthaari raider")


def configure(ship, seed):
    """Point the painter's colour globals at one variant's role map.

    paint() is three hundred lines of hand placed marks reading bare names,
    and threading a palette through all of them would be a large edit to
    working art for no gain. Rebinding the module globals is the small,
    honest version: the vocabulary and the layout stay one implementation,
    and only which colours those names mean changes."""
    role, allowed = load_palette(PALETTE, ship)
    g = globals()
    g["RNG"] = random.Random(seed)
    g["ROLE"], g["ALLOWED"] = role, allowed
    names = {
        "HULL": "hull", "OUTLINE": "outline", "PANEL": "panel",
        "PLATE": "plate", "PLATE_L": "plate_light", "STEEL_L": "armor",
        "LIGHT": "armor_ridge", "PALE": "armor_pale", "STEEL": "armor_shadow",
        "STEEL_D": "armor_deep", "GREEN": "green", "GREEN_L": "green_light",
        "GREEN_D": "green_dark", "PLUME_EDGE": "plume_edge",
        "PLUME_MID": "plume_mid", "PLUME_CORE": "plume_core",
        "MARK": "mark", "GLOW_YELLOW": "window", "GRILLE_RAMP": "grille_ramp",
    }
    for const, key in names.items():
        g[const] = role[key]
    # The bevel tables are derived from those colours, so they are rebuilt
    # here rather than left pointing at the previous variant's.
    g["BEVEL_DARK"] = {role["outline"]}
    g["BEVEL_LIGHT"] = {
        role["armor"]: role["armor_ridge"], role["green"]: role["green_light"],
        role["plate"]: role["plate_light"], role["hull"]: role["panel"],
    }
    g["BEVEL_SHADE"] = {
        role["armor"]: role["armor_shadow"], role["green"]: role["green_dark"],
    }


def main():
    os.makedirs(MESH_OUT, exist_ok=True)
    os.makedirs(TEX_OUT, exist_ok=True)
    build_mesh()
    for ship, prefix, seed in VARIANTS:
        configure(ship, seed)
        d, l, e = paint()
        verify(d, l, e, ALLOWED, ALL_RECTS, TEX, background=OUTLINE,
               lit_budget=(0.002, 0.05))
        d.save(os.path.join(TEX_OUT, prefix + "_diffuse.png"), scale=SCALE)
        l.save(os.path.join(TEX_OUT, prefix + "_lights.png"), scale=SCALE)
        e.save(os.path.join(TEX_OUT, prefix + "_engines.png"), scale=SCALE)


if __name__ == "__main__":
    main()
