#!/usr/bin/env python3
# Paints the Federation heavy cruiser and rebuilds its mesh atlas mapped.
#
# The cruiser was the one hull with no texture at all, and it could not have
# had one: assets/meshes/hull_cruiser.obj was built by tools/gen_meshes.py out
# of plain extrusions, which carry no UVs. A painted hull owns its mesh, the
# way the frigate does, because the atlas layout and the geometry are the same
# decision written twice if they live apart. This file replaces that mesh.
#
# Two ships come off this painter. The Wayfarer is the Federation heavy
# cruiser; the Ironhold is a battlecruiser on the same hull, and it gets its
# own role map rather than its own painter, so the two read as different ships
# without a second copy of this file existing (CLAUDE.md 4.1).
#
# The marks are the shared R1 vocabulary in tools/shiplib.py, the same one the
# frigate speaks, because both are Federation and docs/12 puts empire in
# proportion rather than in detail. Nothing here is a hex value: every colour
# is a role resolved through data/palette.json (CLAUDE.md 3.1).
#
# Usage: python3 tools/gen_ship_cruiser.py

import math
import os
import random

from shiplib import (Px, Obj, R1, circle_mask, disc_outline, load_palette,
                     octagon_mask, rect_mask, slab, verify)

HERE = os.path.dirname(os.path.abspath(__file__))
MESH_OUT = os.path.join(HERE, "..", "assets", "meshes")
TEX_OUT = os.path.join(HERE, "..", "assets", "textures")
PALETTE = os.path.join(HERE, "..", "data", "palette.json")

TEX = 128
SCALE = 2

# The two ships this painter makes: role map name, and the texture prefix.
# Adding a third is a line here plus a role map, never another file.
VARIANTS = (("cruiser", "hull_cruiser"), ("ironhold", "hull_ironhold"))

# ---- atlas layout (logical 128 grid) ----------------------------------------
#
# Laid out so no two rects overlap, which verify() checks by refusing any
# painted pixel that falls outside one of them.
R_SAUCER = (2, 2, 64, 64)
R_SAUCER_RIM = (2, 66, 64, 75)
R_NACELLE_SIDE = (2, 77, 64, 89)
R_NECK = (2, 91, 20, 109)
R_NECK_SIDE = (22, 91, 40, 99)
R_BRIDGE = (42, 91, 58, 107)
R_BRIDGE_SIDE = (42, 109, 58, 117)
R_BODY = (66, 2, 98, 44)
R_BODY_SIDE = (66, 46, 98, 54)
R_BODY_AFT = (66, 56, 98, 68)
R_PYLON = (66, 70, 98, 86)
R_NACELLE_TOP = (100, 2, 116, 64)
R_NACELLE_AFT = (100, 66, 116, 78)
R_NACELLE_FORE = (100, 80, 116, 92)
ALL_RECTS = (
    R_SAUCER, R_SAUCER_RIM, R_NACELLE_SIDE, R_NECK, R_NECK_SIDE, R_BRIDGE,
    R_BRIDGE_SIDE, R_BODY, R_BODY_SIDE, R_BODY_AFT, R_PYLON, R_NACELLE_TOP,
    R_NACELLE_AFT, R_NACELLE_FORE)


def paint(role, seed):
    """The three maps: diffuse, hull lights, engine glow.

    A cruiser is read at a glance from directly above, so the saucer carries
    the detail budget and the aft end carries the light. Every mark sits
    inside one of the rects above."""
    rng = random.Random(seed)
    v = R1(role, rng)
    d = Px(TEX, background=role["base"])
    lights = Px(TEX)
    engines = Px(TEX)

    outline = role["outline"]
    deep = role["deep"]
    gray_d = role["machinery_shadow"]
    gray_l = role["machinery_ridge"]
    step = role["step"]
    step2 = role["step_warm"]
    yellow = role["window"]
    glow_yellow = role["glow_window"]
    glow_red = role["glow_mid"]
    red_sh = role["red_shadow"]

    # Saucer cap. Broader than the frigate's and given a third ring seam,
    # because docs/12 reads class off part count and this is the mark that
    # says heavy at the camera this game uses.
    cx, cy = 33, 33
    v.plate_island(d, cx - 30, cy - 30, circle_mask(30))
    v.ridge_ring(d, cx, cy, 25)
    v.ridge_ring(d, cx, cy, 17)
    v.ridge_ring(d, cx, cy, 9)
    v.rivet_ring(d, cx, cy, 28, 16, offset=0.1)
    v.rivet_ring(d, cx, cy, 21, 12, offset=0.4)
    v.rivet_ring(d, cx, cy, 13, 8, offset=0.2)
    v.machinery(d, cx - 6, cy - 6, octagon_mask(6))
    d.put(cx, cy, gray_d)
    d.hline(cx - 2, cy + 3, 5, step)
    for i in range(6):
        a = i * math.pi / 3
        d.put(int(cx + math.cos(a) * 12), int(cy + math.sin(a) * 12), gray_d)
    v.plate_panel(d, 11, 17, rect_mask(9, 7, (1, 0, 0, 1)))
    v.plate_panel(d, 44, 44, rect_mask(8, 6, (0, 1, 1, 0)))
    v.plate_panel(d, 12, 44, rect_mask(7, 6, (1, 1, 0, 0)))
    v.capsule(d, 47, 22, 5, vertical=True)
    v.capsule(d, 16, 30, 5, vertical=True)
    v.red_block(d, 44, 12, 6, 4)
    v.machinery(d, 18, 40, rect_mask(4, 4), dots=False)
    v.window_run(d, lights, 24, 25, 3)
    v.window_run(d, lights, 41, 34, 3)
    v.window_run(d, lights, 30, 50, 2)

    # Saucer rim wall: the promenade, three window pairs on a heavy cruiser.
    v.plate_island(d, 2, 66, rect_mask(62, 9))
    v.rivet_row(d, 6, 68, 14, 4)
    v.window_run(d, lights, 14, 70, 2)
    v.window_run(d, lights, 32, 70, 2)
    v.window_run(d, lights, 50, 70, 2)
    v.capsule(d, 22, 71, 6)

    # Nacelle flank: long armour run with a capsule leader and two seams.
    v.machinery(d, 2, 77, rect_mask(62, 12, (1, 1, 1, 1)))
    v.capsule(d, 8, 81, 10)
    for sx in (24, 42):
        d.vline(sx, 79, 8, outline)
        d.dots(sx + 1, 80, 3, 3, outline, vertical=True)
    d.hline(28, 80, 12, step2)
    v.red_block(d, 52, 82, 4, 3)
    v.window_run(d, lights, 59, 81, 2)

    # Neck cap and wall: the narrow deck joining saucer to engineering.
    v.plate_island(d, 2, 91, rect_mask(18, 18, (1, 1, 1, 1)))
    v.machinery(d, 7, 95, rect_mask(8, 10))
    v.rivet_row(d, 4, 94, 3, 4)
    v.plate_island(d, 22, 91, rect_mask(18, 8))
    v.window_run(d, lights, 30, 93, 2)

    # Bridge: plate octagon over a machinery core, windows on the wall band.
    v.plate_island(d, 43, 92, octagon_mask(7))
    v.machinery(d, 47, 96, octagon_mask(3), dots=False)
    d.put(50, 94, yellow)
    lights.put(50, 94, glow_yellow)
    v.plate_island(d, 42, 109, rect_mask(16, 8))
    v.window_run(d, lights, 46, 111, 2)
    v.window_run(d, lights, 52, 111, 2)

    # Engineering body cap: a machinery field with plate quarters, the
    # deuterium block, a ladder bay and hatch greebles.
    v.machinery(d, 66, 2, rect_mask(32, 42, (1, 1, 2, 2)))
    v.plate_panel(d, 70, 6, rect_mask(11, 9, (0, 2, 0, 0)))
    v.window_run(d, lights, 73, 8, 2)
    v.red_block(d, 86, 6, 7, 5)
    v.ladder(d, (82, 30, 94, 38))
    v.machinery(d, 70, 30, rect_mask(5, 5), dots=False)
    d.hline(68, 20, 28, outline)
    v.rivet_row(d, 70, 23, 7, 4)
    d.hline(68, 26, 28, outline)
    d.vline(68, 5, 12, step)
    d.put(84, 24, deep)
    v.capsule(d, 74, 40, 7)

    # Body walls: the engineering windows, the brightest run on the ship.
    v.plate_island(d, 66, 46, rect_mask(32, 8))
    v.window_run(d, lights, 72, 48, 3)
    v.window_run(d, lights, 82, 48, 3)
    v.window_run(d, lights, 92, 48, 2)
    v.rivet_row(d, 68, 48, 3, 4)

    # Body stern: armour, a shuttle bay ladder, and two impulse housings
    # whose cores glow in the hull lights layer.
    v.machinery(d, 66, 56, rect_mask(32, 12))
    v.ladder(d, (78, 58, 86, 66))
    for bx in (69, 90):
        v.red_block(d, bx, 58, 5, 8)
        d.fill((bx + 2, 61, bx + 3, 63), red_sh)
        lights.fill((bx + 2, 61, bx + 3, 63), glow_red)

    # Pylons: swept armour, one seam and a stepped highlight.
    v.machinery(d, 66, 70, rect_mask(32, 16, (0, 5, 0, 5)))
    d.hline(69, 77, 22, outline)
    d.dots(70, 78, 7, 3, outline)
    d.vline(69, 72, 4, step)

    # Nacelle cap: armour slab, aft at the rect's top. Ladder vent aft, a
    # capsule, riveted seams and a stepped highlight.
    v.machinery(d, 100, 2, rect_mask(16, 62, (1, 1, 3, 3)))
    v.ladder(d, (102, 6, 114, 16))
    v.capsule(d, 107, 32, 8, vertical=True)
    for sy in (20, 46):
        d.hline(102, sy, 12, outline)
        d.dots(103, sy + 1, 4, 3, outline)
    d.vline(103, 24, 20, step)
    d.put(105, 54, deep)
    d.put(110, 54, deep)

    # Nacelle stern: the R1 engine bell, glowing in the engine layer.
    v.engine_bell(d, engines, 100, 66, 16, 12)

    # Nacelle bow: intake dome, unlit.
    v.machinery(d, 100, 80, rect_mask(16, 12, (2, 2, 2, 2)))
    d.shape(105, 83, octagon_mask(3), step, line=gray_l, width=1)
    d.put(108, 86, gray_d)

    # The combined lights map is the hull layer plus the engine layer, the
    # way the R1 sheets keep an em_eng_glow alongside em_hull.
    for i, px in enumerate(engines.px):
        if px[:3] != (0, 0, 0):
            lights.px[i] = px
    return d, lights, engines


def build_mesh():
    """The cruiser, rebuilt atlas mapped. Same silhouette gen_meshes.py gave
    it, because the ship is already recognisable and this is a texturing
    change, but every face now carries a UV into the layout above."""
    o = Obj(MESH_OUT)
    # Saucer, forward and dominant.
    slab(o, disc_outline(0.0, 1.45, 1.55, 1.25, 20), 0.10, 0.46,
         R_SAUCER, R_SAUCER_RIM, TEX)
    # Bridge dome on top of it.
    slab(o, disc_outline(0.0, 1.55, 0.42, 0.36, 10), 0.46, 0.62,
         R_BRIDGE, R_BRIDGE_SIDE, TEX)
    # Neck down to the engineering body.
    slab(o, [(-0.34, 0.55), (0.34, 0.55), (0.34, -0.55), (-0.34, -0.55)],
         0.06, 0.40, R_NECK, R_NECK_SIDE, TEX)
    # Engineering body, tapering to a stern shutter.
    slab(o, [(-0.62, 0.30), (0.62, 0.30), (0.78, -0.90),
             (0.48, -2.05), (-0.48, -2.05), (-0.78, -0.90)],
         0.0, 0.50, R_BODY, R_BODY_SIDE, TEX, rect_aft=R_BODY_AFT)
    # Pylons out to the nacelles.
    slab(o, [(-1.02, -0.75), (-0.55, -0.55), (-0.55, -1.25), (-1.02, -1.45)],
         0.14, 0.34, R_PYLON, R_PYLON, TEX)
    slab(o, [(0.55, -0.55), (1.02, -0.75), (1.02, -1.45), (0.55, -1.25)],
         0.14, 0.34, R_PYLON, R_PYLON, TEX)
    # Nacelles, outboard and above the deck line.
    for side in (-1.0, 1.0):
        nx = 1.32 * side
        slab(o, [(nx - 0.24, 0.80), (nx + 0.24, 0.80),
                 (nx + 0.28, -1.90), (nx - 0.28, -1.90)],
             0.40, 0.72, R_NACELLE_TOP, R_NACELLE_SIDE, TEX,
             rect_aft=R_NACELLE_AFT, rect_fore=R_NACELLE_FORE)
    o.write("hull_cruiser.obj",
            "Federation heavy cruiser, nose at +Z, atlas mapped")


def main():
    os.makedirs(MESH_OUT, exist_ok=True)
    os.makedirs(TEX_OUT, exist_ok=True)
    build_mesh()
    for seed, (ship, prefix) in enumerate(VARIANTS):
        role, allowed = load_palette(PALETTE, ship)
        # A seed per variant, so the two ships do not share their speckle and
        # a rerun of either is still an empty diff.
        d, lights, engines = paint(role, 23 + seed * 7)
        verify(d, lights, engines, allowed, ALL_RECTS, TEX,
               background=role["base"], lit_budget=(0.0008, 0.03))
        d.save(os.path.join(TEX_OUT, prefix + "_diffuse.png"), scale=SCALE)
        lights.save(os.path.join(TEX_OUT, prefix + "_lights.png"), scale=SCALE)
        engines.save(os.path.join(TEX_OUT, prefix + "_engines.png"), scale=SCALE)


if __name__ == "__main__":
    main()
