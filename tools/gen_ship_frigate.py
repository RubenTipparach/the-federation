#!/usr/bin/env python3
# Generates the committed frigate: mesh, pixel art diffuse atlas, and emissive
# lights maps, in the style of the author's R1 starship sheets.
#
# Color comes from the project palette in data/palette.json (CLAUDE.md 3.1):
# this file names roles, never hex values. The finished maps are verified
# before anything is written: every pixel must be a palette entry, the lights
# map stays within budget, the engine layer is a subset of the combined
# lights map, and every painted pixel sits inside its atlas rect.
#
# Shape vocabulary source: docs/examples/ship-art/old_ships/R1-Starship-A.
#
# The R1 look, measured from the sheets and refined by critique passes:
#   - authored at the sheets' native 128 grid and exported 2x nearest, so
#     every logical pixel is the same fat chunk the R1 sheets are built from
#   - steel blue hull plates over the same blue as the atlas background;
#     blue panels carry NO black outline: their edges are a top lit ridge
#     ((120,144,193) with (99,155,255) sparks) and a (87,103,144) shadow on
#     the bottom and right; black outlines are reserved for the silhouette
#     and for gray machinery
#   - gray machinery is mid gray (105,106,106) with a (170,170,170) top
#     ridge, (76,76,76) shadow, and (148,148,148)/(167,165,168) stepped
#     highlights; black rivet dots run along machinery borders
#   - silver (170,170,170) rivet dots, with occasional (132,126,135), run
#     along blue plate seams
#   - red machinery carries an alternating black dot border ON the red and
#     (115,54,53) shading; engine bells get a silver ring, a white plus
#     specular, and a layered red glow with a wide dark halo
#   - ladders and vents are light gray rungs on (34,32,52) rails
#   - windows are a few short vertical runs of single yellow pixels, not
#     strips; bright blue capsule strips accent some plates
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

from shiplib import (Px, Obj, R1, circle_mask, disc_outline, load_palette,
                     octagon_mask, rect_mask, rings, slab, verify)

HERE = os.path.dirname(os.path.abspath(__file__))
MESH_OUT = os.path.join(HERE, "..", "assets", "meshes")
TEX_OUT = os.path.join(HERE, "..", "assets", "textures")
PALETTE = os.path.join(HERE, "..", "data", "palette.json")

# Authored at the R1 sheets' native grid, exported 2x for the engine.
## How many pieces a destroyed hull comes apart into. One number for every
## ship, so the wreck scene's chunk slots line up whatever died.
FRAGMENTS = 8

TEX = 128
SCALE = 2
RNG = random.Random(11)

# Roles, resolved through data/palette.json. Nothing here is a hex value:
# retuning the ship's color means editing that file, not this one.
ROLE, ALLOWED = load_palette(PALETTE, "frigate")
# The shared R1 vocabulary, bound to this hull's roles and RNG.
V = R1(ROLE, RNG)
BASE = ROLE["base"]              # hull base and atlas background
OUTLINE = ROLE["outline"]        # silhouette, machinery borders, rails
DEEP = ROLE["deep"]              # tiny dark window slits only
P_BLUE = ROLE["plate"]           # hull plate
P_LIGHT = ROLE["plate_light"]    # its top lit ridge
P_SHADOW = ROLE["plate_shadow"]  # its bottom shadow
GRAY = ROLE["machinery"]         # machinery fill
GRAY_D = ROLE["machinery_shadow"]
GRAY_L = ROLE["machinery_ridge"] # machinery ridge, and the rivet dots
STEP = ROLE["step"]              # stepped highlight
STEP2 = ROLE["step_warm"]
MAUVE = ROLE["rivet_pale"]       # occasional pale rivet
SILVER = ROLE["silver"]          # engine bell ring
WHITE = ROLE["specular"]         # bell plus specular
RED = ROLE["red"]                # machinery red
RED_D = ROLE["red_dark"]
RED_SH = ROLE["red_shadow"]
YELLOW = ROLE["window"]          # window pixels
ACCENT = ROLE["accent"]          # capsule strips and plate edge sparks

GLOW_HALO = ROLE["glow_halo"]    # engine bell: wide dark halo
GLOW_RED = ROLE["glow_mid"]
GLOW_LIGHT = ROLE["glow_light"]
GLOW_CORE = ROLE["glow_core"]    # hot core
GLOW_YELLOW = ROLE["glow_window"]

# ---- atlas layout (logical 128 grid) ----------------------------------------
R_SAUCER = (2, 2, 62, 62)
R_SAUCER_RIM = (2, 65, 62, 74)
R_NACELLE_SIDE = (2, 77, 62, 89)
R_NACELLE_TOP = (66, 2, 82, 62)
R_SPINE = (86, 2, 118, 32)
R_SPINE_SIDE = (86, 35, 118, 43)
R_BODY = (86, 47, 118, 77)
R_BODY_SIDE = (86, 80, 118, 88)
R_PYLON = (86, 91, 118, 107)
R_BRIDGE = (66, 66, 82, 82)
R_BRIDGE_SIDE = (66, 85, 82, 93)
R_NACELLE_AFT = (66, 96, 82, 108)
R_NACELLE_FORE = (66, 111, 82, 123)
R_BODY_AFT = (86, 110, 118, 122)
ALL_RECTS = (
    R_SAUCER, R_SAUCER_RIM, R_NACELLE_SIDE, R_NACELLE_TOP, R_SPINE,
    R_SPINE_SIDE, R_BODY, R_BODY_SIDE, R_PYLON, R_BRIDGE, R_BRIDGE_SIDE,
    R_NACELLE_AFT, R_NACELLE_FORE, R_BODY_AFT)


# ---- the atlases, painted together ------------------------------------------


def paint():
    d = Px(TEX, background=BASE)
    l = Px(TEX)
    e = Px(TEX)

    # Saucer cap: blue plate disc with ridge ring seams, silver rivet runs,
    # a gray machinery hub, and a few chunky detail panels.
    cx, cy = 32, 32
    V.plate_island(d, cx - 29, cy - 29, circle_mask(29))
    V.ridge_ring(d, cx, cy, 22)
    V.ridge_ring(d, cx, cy, 13)
    V.rivet_ring(d, cx, cy, 26, 12, offset=0.15)
    V.rivet_ring(d, cx, cy, 17, 8, offset=0.5)
    V.machinery(d, cx - 7, cy - 7, octagon_mask(7))
    d.put(cx, cy, GRAY_D)
    d.hline(cx - 2, cy + 3, 5, STEP)
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        d.put(int(cx + math.cos(a) * 10), int(cy + math.sin(a) * 10), GRAY_D)
    V.plate_panel(d, 12, 18, rect_mask(8, 6, (1, 0, 0, 1)))
    V.plate_panel(d, 40, 42, rect_mask(7, 5, (0, 1, 1, 0)))
    V.capsule(d, 44, 20, 4, vertical=True)
    V.red_block(d, 42, 12, 5, 4)
    V.machinery(d, 17, 41, rect_mask(4, 4), dots=False)
    V.window_run(d, l, 24, 26, 2)
    V.window_run(d, l, 38, 33, 3)

    # Saucer rim wall: blue band with silver rivets and two window pairs.
    V.plate_island(d, 2, 65, rect_mask(60, 9))
    V.rivet_row(d, 6, 67, 13, 4)
    V.window_run(d, l, 16, 69, 2)
    V.window_run(d, l, 44, 69, 2)
    V.capsule(d, 28, 70, 5)

    # Nacelle cap: gray armor slab, aft at the rect's top. Ladder vent aft,
    # a bright capsule, riveted seams, stepped highlights.
    V.machinery(d, 66, 2, rect_mask(16, 60, (1, 1, 3, 3)))
    V.ladder(d, (68, 6, 80, 16))
    V.capsule(d, 73, 30, 6, vertical=True)
    d.hline(68, 20, 12, OUTLINE)
    d.dots(69, 21, 4, 3, OUTLINE)
    d.hline(68, 44, 12, OUTLINE)
    d.dots(69, 45, 4, 3, OUTLINE)
    d.vline(69, 24, 18, STEP)
    d.put(71, 52, DEEP)
    d.put(76, 52, DEEP)

    # Nacelle flank: gray armor with a bright capsule leader, riveted seams,
    # a red service block, and one window pair.
    V.machinery(d, 2, 77, rect_mask(60, 12, (1, 1, 1, 1)))
    V.capsule(d, 8, 81, 8)
    d.vline(22, 79, 8, OUTLINE)
    d.dots(23, 80, 3, 3, OUTLINE, vertical=True)
    d.vline(40, 79, 8, OUTLINE)
    d.dots(41, 80, 3, 3, OUTLINE, vertical=True)
    d.hline(26, 80, 12, STEP2)
    V.red_block(d, 48, 82, 4, 3)
    V.window_run(d, l, 55, 81, 2)

    # Spine cap: blue deck with a gray walkway, ladder vent, and a capsule.
    V.plate_island(d, 86, 2, rect_mask(32, 30, (2, 2, 1, 1)))
    V.machinery(d, 96, 6, rect_mask(8, 20))
    V.window_run(d, l, 92, 10, 2)
    V.ladder(d, (108, 22, 116, 28))
    V.capsule(d, 89, 26, 5)
    V.rivet_row(d, 108, 8, 3, 3)

    # Spine walls: blue band with one window pair.
    V.plate_island(d, 86, 35, rect_mask(32, 8))
    V.window_run(d, l, 100, 37, 2)
    V.rivet_row(d, 90, 37, 3, 4)

    # Engineering body cap: gray machinery field with a blue quarter panel,
    # red machinery, a ladder, hatch greebles, and stepped highlights.
    V.machinery(d, 86, 47, rect_mask(32, 30, (1, 1, 2, 2)))
    V.plate_panel(d, 90, 51, rect_mask(10, 8, (0, 2, 0, 0)))
    V.window_run(d, l, 93, 53, 2)
    V.red_block(d, 108, 51, 6, 5)
    V.ladder(d, (104, 68, 114, 74))
    V.machinery(d, 92, 68, rect_mask(4, 4), dots=False)
    d.hline(88, 63, 24, OUTLINE)
    V.rivet_row(d, 90, 65, 6, 4)
    d.vline(88, 50, 10, STEP)
    d.put(102, 58, DEEP)

    # Body walls: blue band with the engineering windows.
    V.plate_island(d, 86, 80, rect_mask(32, 8))
    V.window_run(d, l, 96, 82, 3)
    V.window_run(d, l, 108, 82, 2)
    V.rivet_row(d, 89, 82, 4, 4)

    # Pylons: gray armor, swept, one seam and stepped highlight.
    V.machinery(d, 86, 91, rect_mask(32, 16, (0, 5, 0, 5)))
    d.hline(89, 98, 20, OUTLINE)
    d.dots(90, 99, 6, 3, OUTLINE)
    d.vline(89, 93, 4, STEP)

    # Bridge: blue octagon cap over a gray core, windows on the wall band.
    V.plate_island(d, 67, 67, octagon_mask(7))
    V.machinery(d, 71, 71, octagon_mask(3), dots=False)
    d.put(74, 69, YELLOW)
    l.put(74, 69, GLOW_YELLOW)
    V.plate_island(d, 66, 85, rect_mask(16, 8))
    V.window_run(d, l, 71, 87, 2)
    V.window_run(d, l, 77, 87, 2)

    # Nacelle stern: the R1 engine bell, glowing in the engine layer.
    V.engine_bell(d, e, 66, 96, 16, 12)

    # Nacelle bow: gray intake dome, unlit.
    V.machinery(d, 66, 111, rect_mask(16, 12, (2, 2, 2, 2)))
    d.shape(71, 114, octagon_mask(3), STEP, line=GRAY_L, width=1)
    d.put(74, 117, GRAY_D)

    # Body stern: gray armor, a ladder bay, two red impulse housings whose
    # cores glow in the hull lights layer.
    V.machinery(d, 86, 110, rect_mask(32, 12))
    V.ladder(d, (98, 112, 106, 120))
    for bx in (89, 110):
        V.red_block(d, bx, 112, 5, 8)
        d.fill((bx + 2, 115, bx + 3, 117), RED_SH)
        l.fill((bx + 2, 115, bx + 3, 117), GLOW_RED)

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
    o.write_fragments("hull_frigate", FRAGMENTS, "Okinawa inspired frigate")


def main():
    os.makedirs(MESH_OUT, exist_ok=True)
    os.makedirs(TEX_OUT, exist_ok=True)
    build_mesh()
    d, l, e = paint()
    verify(d, l, e, ALLOWED, ALL_RECTS, TEX, background=BASE,
           lit_budget=(0.0008, 0.03))
    d.save(os.path.join(TEX_OUT, "hull_frigate_diffuse.png"), scale=SCALE)
    l.save(os.path.join(TEX_OUT, "hull_frigate_lights.png"), scale=SCALE)
    e.save(os.path.join(TEX_OUT, "hull_frigate_engines.png"), scale=SCALE)


if __name__ == "__main__":
    main()
