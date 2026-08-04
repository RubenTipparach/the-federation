#!/usr/bin/env python3
# Generates the committed burning interior: assets/textures/fx_debris_interior.png
# and its emissive map fx_debris_interior_lights.png.
#
# What the inside of a blown open ship looks like: charred structure with hot
# spots still glowing in it. ONE texture for every hull, deliberately. The
# outside of a ship is its identity and each hull paints its own; the inside
# is wreckage, and wreckage looks like wreckage whoever built the ship. If a
# hull ever wants a custom interior, this stays the default and that hull's
# generator writes its own pair.
#
# The wreck's fragment caps wear it through
# assets/materials/mat_debris_interior.tres, which pairs the two maps exactly
# the way every hull material pairs its diffuse and lights atlases: the
# diffuse carries the char, the lights map carries the glow, and the material's
# emission path does the burning. No new shader, no new system.
#
# Colours come from the "explosion" ramp in data/palette.json (CLAUDE.md 3.1):
# the burning inside of a hull and the fireball it feeds are the same heat.
# verify() stops the run before an off palette pixel is written.
#
# The heat is a field of HOT SPOTS on a char base: a few dozen blobs of
# differing size and strength, dithered through the ramp. The same three
# tricks every effect texture here uses: spots spread around rather than drawn
# independently so there are no accidental bare quarters, brightness drawn
# skewed so most spots smoulder and a few burn, and a compressed rather than
# clamped tone map so only the heart of the hottest spots reaches cream.
#
# EVERYTHING IS A CLOSED FORM OF POSITION, and the scatter comes from a seeded
# generator, so running this twice writes the same bytes.

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shiplib import Px, bayer, load_colors, load_fx_ramp, ramp_index

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PALETTE = os.path.join(ROOT, "data", "palette.json")
OUT_DIFFUSE = os.path.join(ROOT, "assets", "textures", "fx_debris_interior.png")
OUT_LIGHTS = os.path.join(ROOT, "assets", "textures",
                          "fx_debris_interior_lights.png")

SIZE = 256
SEED = 20260807

# The hot spots: how many, how large as a fraction of the image, and how
# bright. Sizes and strengths are drawn skewed so most spots smoulder dark red
# and a handful burn through to gold and cream.
SPOTS = 46
SPOT_MIN = 0.03
SPOT_MAX = 0.14
LIT_MIN = 0.5
LIT_MAX = 4.0

# Cracks: thin hot lines wandering between spots, so the burning reads as
# structure coming apart along its seams rather than as polka dots.
CRACKS = 26
CRACK_STEPS = 40
CRACK_LIT = 1.1

# How hot a texel has to be before the lights map records it as glowing.
# Everything below it is char lit only by the scene.
GLOW_FLOOR = 0.55


def spots(rng):
    """The hot spots, laid on a jittered grid rather than drawn independently:
    a bare quarter in a burning interior reads as a bug, the same reason every
    ring and fireball here spreads its pieces."""
    out = []
    cells = 7
    for gy in range(cells):
        for gx in range(cells):
            if rng.random() < 0.10:
                continue
            roll = pow(rng.random(), 2.4)
            out.append({
                "x": (gx + rng.uniform(0.2, 0.8)) / cells,
                "y": (gy + rng.uniform(0.2, 0.8)) / cells,
                "r": SPOT_MIN + (SPOT_MAX - SPOT_MIN) * pow(rng.random(), 1.6),
                "lit": LIT_MIN + (LIT_MAX - LIT_MIN) * roll,
            })
    return out[:SPOTS]


def cracks(rng):
    """Wandering hot lines: a start, a heading that drifts, and a strength."""
    out = []
    for i in range(CRACKS):
        out.append({
            "x": rng.random(),
            "y": rng.random(),
            "heading": rng.uniform(0.0, 2.0 * math.pi),
            "wander": rng.uniform(0.25, 0.7),
            "lit": CRACK_LIT * rng.uniform(0.6, 1.3),
        })
    return out


def field(size, blobs, lines, rng):
    """How much heat is at each texel. The texture TILES: distances wrap, so a
    cap whose UVs run to the edge meets the other edge without a seam."""
    heat = [0.0] * (size * size)

    for b in blobs:
        r = b["r"] * size
        cx = b["x"] * size
        cy = b["y"] * size
        span = int(r) + 1
        for dy in range(-span, span + 1):
            for dx in range(-span, span + 1):
                d = math.sqrt(dx * dx + dy * dy) / max(r, 0.5)
                if d >= 1.0:
                    continue
                x = int(cx + dx) % size
                y = int(cy + dy) % size
                heat[y * size + x] += b["lit"] * pow(1.0 - d, 2.0)

    for line in lines:
        x = line["x"] * size
        y = line["y"] * size
        heading = line["heading"]
        for _ in range(CRACK_STEPS):
            heat[(int(y) % size) * size + (int(x) % size)] += line["lit"]
            heading += rng.uniform(-line["wander"], line["wander"])
            x += math.cos(heading) * 1.6
            y += math.sin(heading) * 1.6
    return heat


def paint(size, heat, ramp, black):
    """Two maps from one field: the diffuse paints the char, and the lights
    map carries everything that glows.

    UNDER A GLOWING TEXEL THE DIFFUSE IS PALETTE BLACK, not the ramp colour.
    The material draws albedo shaded and adds emission on top, so a hot spot
    painted in both maps came out lit twice and dimmed whenever the sun was
    on the other side, which is backwards: a thing emitting light does not
    care where the sun is. With the albedo near zero there, the scene's light
    has nothing to act on and the glow is the emission alone, fully emissive
    and unlit, exact palette colour at any angle."""
    diffuse = Px(size, background=ramp[-1], height=size)
    lights = Px(size, background=(0, 0, 0), height=size)
    for y in range(size):
        for x in range(size):
            v = heat[y * size + x]
            d = bayer(x, y)
            near = v / (v + 1.1)
            index = ramp_index(near, ramp, float(len(ramp)), d)
            if index >= len(ramp):
                continue
            if v >= GLOW_FLOOR:
                diffuse.put(x, y, black)
                lights.put(x, y, ramp[index])
            else:
                diffuse.put(x, y, ramp[index])
    return diffuse, lights


def verify(px, allowed):
    for r, g, b, a in px.px:
        assert (r, g, b) in allowed, "off palette pixel %r" % ((r, g, b),)


def main():
    ramp = load_fx_ramp(PALETTE, "explosion")
    black = load_colors(PALETTE)[0]["black"]
    rng = random.Random(SEED)
    heat = field(SIZE, spots(rng), cracks(rng), rng)
    diffuse, lights = paint(SIZE, heat, ramp, black)
    verify(diffuse, set(ramp) | {black})
    verify(lights, set(ramp) | {(0, 0, 0)})
    diffuse.save(OUT_DIFFUSE)
    lights.save(OUT_LIGHTS)
    glowing = sum(1 for p in lights.px if p[:3] != (0, 0, 0))
    print("%d by %d, %d texels glowing (%.1f%%)"
          % (SIZE, SIZE, glowing, 100.0 * glowing / (SIZE * SIZE)))


if __name__ == "__main__":
    main()
