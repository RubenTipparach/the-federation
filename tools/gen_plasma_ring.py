#!/usr/bin/env python3
# Generates the committed plasma ring: assets/textures/fx_plasma_ring.png.
#
# The shell a capital ship throws when its containment lets go, seen from
# above. It lies FLAT ON THE BATTLE PLANE rather than facing the camera, which
# is the whole reason it is a texture: a front expanding through a plane is a
# ring seen in perspective, and the eye reads the ellipse it makes as the
# ship's own plane. A billboarded ring reads as a bubble instead, and a bubble
# has no plane to belong to.
#
# It is drawn as FILAMENTS rather than as a smooth band. A smooth ring is a
# range indicator, which this game already has several of and which is the last
# thing a detonation should be confused with; a ring made of a few hundred
# radial threads with bright knots along it reads as something being driven
# outward. That is the reference the ring was asked for.
#
# THE OUTER EDGE IS A TRUE CIRCLE and it is the bright one, near white, with
# everything falling away INWARD from it into the blue. That is the shape of a
# front: what is at the leading edge is what was accelerated hardest and is
# still hottest, and what is behind it is what has already begun to cool. The
# threads all start on that circle and run inward, so the ragged end of the
# ring is its trailing one and its leading edge stays clean at any radius the
# shell is drawn at.
#
# Per CLAUDE.md section 3 an art asset is delivered as a .png, and per 5.1 a
# script may generate one only by WRITING THE FILE, never by building it at
# runtime. Every pixel is a Waldgeist entry named through the "plasma" ramp in
# data/palette.json (3.1): this file asks for a ramp and only the palette file
# says what is in it, and verify_palette() stops the run before an off palette
# pixel can be written.
#
# ALPHA CARRIES THE BRIGHTNESS, the ramp carries the colour. The material draws
# it additively, so a texel's alpha is how much light it adds and a fully
# transparent texel adds nothing. That is what lets a five colour ramp paint a
# glow that fades smoothly to nothing: the colour steps, the strength does not.
#
# EVERYTHING IS A CLOSED FORM OF THE BEARING, and the scatter comes from a
# seeded generator, so running this twice writes the same bytes.

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shiplib import Px, bayer, load_fx_ramp, ramp_index

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PALETTE = os.path.join(ROOT, "data", "palette.json")
TUNING = os.path.join(ROOT, "data", "tuning.json")
OUT = os.path.join(ROOT, "assets", "textures", "fx_plasma_ring.png")

SIZE = 256
SEED = 20260805

# Where the leading edge sits, as a fraction of the image's half width. A
# little short of the rim, so the brightest texels are not the ones the sprite
# is cut off at. PERFECTLY CIRCULAR: nothing below wobbles it.
OUTER = 0.86

# How many threads the ring is made of, and how far each runs INWARD from the
# leading edge, in fractions of the half width. The spread between the two
# lengths is what makes the trailing edge ragged where the leading one is
# clean.
FILAMENTS = 340
REACH_MIN = 0.09
REACH_MAX = 0.34

# The knots: short threads drawn far brighter than the rest, which is what puts
# cream coloured points along the edge. Without them the ring is evenly bright
# and reads as printed rather than as burning.
KNOTS = 54

# The continuous glow the threads stand on, falling inward from the leading
# edge. A ring of loose threads with nothing behind it reads as a dashed line.
# TWO LOBES, not one. The hot one is narrow and strong enough at the edge
# itself to reach the CREAM at the top of the ramp, which is what "almost
# white on the outside" means when the palette has five blues and one near
# white. The cool one is wide and weak and carries the blue back behind it.
#
# One lobe cannot do both jobs. Wide enough to give the ring its thickness, it
# holds the whole outer half at the top of the ramp and the white stops being
# an edge; narrow enough to keep the white to an edge, and there is no ring
# behind it. Splitting them is what puts a hard bright line on the outside with
# a long blue wake inside it.
GLOW_HOT_WIDTH = 0.045
GLOW_HOT = 9.0
GLOW_TAIL_WIDTH = 0.115
GLOW_TAIL = 2.2

# Below this a texel is left empty. Additive blending means a texel this faint
# adds nothing anyone can see, and leaving it out keeps the sprite's edge from
# being a visible square of almost black.
FLOOR = 0.035


def band_frac():
    """Where the LEADING EDGE sits, as a fraction of the image's half width.

    Read from data/tuning.json rather than written here, because the code that
    scales the ring in the world has to agree with the art about where the band
    is or the shell will be drawn at the wrong radius. One number, one file
    (CLAUDE.md 5.4)."""
    import json
    with open(TUNING) as f:
        return float(json.load(f)["explosion"]["plasma_band_frac"])


def filaments(rng):
    """The threads: where each one sits, how far it runs inward, and how bright.

    Spread around the circle with the jitter smaller than the spacing, for the
    reason the fireball's billows already record: independent draws leave gaps
    often enough to be noticed, and a gap in a ring reads as a bug."""
    out = []
    span = 2.0 * math.pi / FILAMENTS
    for i in range(FILAMENTS):
        bearing = span * i + rng.uniform(-span * 0.45, span * 0.45)
        out.append({
            "bearing": bearing,
            "reach": rng.uniform(REACH_MIN, REACH_MAX),
            # Squared, so most threads are middling and a few are bright. A
            # uniform draw gives an evenly lit fringe, which is a brush and not
            # a plasma front.
            "lit": 0.5 + 1.5 * pow(rng.random(), 2.0),
        })
    for i in range(KNOTS):
        out.append({
            "bearing": rng.uniform(0.0, 2.0 * math.pi),
            "reach": rng.uniform(0.02, 0.07),
            # Far above the threads around them, because a knot has to reach
            # the cream at the top of the ramp on its own rather than only
            # where two threads happen to cross.
            "lit": 3.4,
        })
    return out


def field(size, threads, band):
    """How much light is at each texel, from 0 to about 1.

    Everything is measured INWARD from the leading edge, which is the one thing
    in this picture that is exactly a circle."""
    half = size * 0.5
    edge = band * half
    heat = [0.0] * (size * size)

    # The threads. Walked along their own radius rather than rasterised as
    # lines, which is what keeps each one exactly one texel wide however far in
    # it reaches.
    for f in threads:
        cs = math.cos(f["bearing"])
        sn = math.sin(f["bearing"])
        run = f["reach"] * half
        steps = int(run) + 2
        for s in range(steps + 1):
            k = s / float(steps)
            # Peaks a little way BEHIND the leading edge rather than on it.
            # On it, every thread is buried under a glow nine times its own
            # strength and the ring comes out a flat blue band; a step back,
            # they are the brightest thing in a region the glow has already
            # begun to leave, and they read as threads. The 2.4 is what it
            # takes for one to stand out against the glow still there.
            lit = f["lit"] * 2.4 * pow(k, 0.5) * pow(1.0 - k, 1.2)
            r = edge - run * k
            x = int(half + cs * r)
            y = int(half + sn * r)
            if 0 <= x < size and 0 <= y < size:
                heat[y * size + x] += lit

    # The glow the threads stand on: hottest at the edge itself, falling away
    # inward. Nothing at all outside it, which is what makes the outer boundary
    # a clean circle instead of a soft halo that reads as a smudge.
    for y in range(size):
        dy = y + 0.5 - half
        for x in range(size):
            dx = x + 0.5 - half
            r = math.sqrt(dx * dx + dy * dy) / half
            if r > band:
                continue
            back = band - r
            hot = back / GLOW_HOT_WIDTH
            tail = back / GLOW_TAIL_WIDTH
            if tail >= 3.0:
                continue
            heat[y * size + x] += GLOW_HOT * math.exp(-hot * hot) \
                + GLOW_TAIL * math.exp(-tail * tail)
    return heat


def paint(px, size, heat, ramp):
    """The light field, painted through the ramp with the strength in alpha."""
    for y in range(size):
        for x in range(size):
            v = heat[y * size + x]
            if v <= FLOOR:
                continue
            d = bayer(x, y)
            # Compressed rather than clamped, so where several threads cross
            # the texel still climbs toward the cream at the top of the ramp
            # instead of flattening at the blue below it.
            near = v / (v + 0.9)
            index = ramp_index(near, ramp, float(len(ramp)), d)
            if index >= len(ramp):
                continue
            px.put(x, y, ramp[index], min(255, int(v * 320.0 + 0.5)))


def verify_palette(px, allowed):
    """The same gate the ship painter passes: every painted texel is a palette
    entry, checked before the file is written rather than after."""
    for r, g, b, a in px.px:
        if a == 0:
            continue
        assert (r, g, b) in allowed, "off palette pixel %r" % ((r, g, b),)


def main():
    ramp = load_fx_ramp(PALETTE, "plasma")
    rng = random.Random(SEED)
    band = band_frac()
    threads = filaments(rng)
    heat = field(SIZE, threads, band)

    px = Px(SIZE, background=(0, 0, 0), height=SIZE, alpha=0)
    paint(px, SIZE, heat, ramp)
    verify_palette(px, set(ramp))
    px.save(OUT)
    lit = sum(1 for p in px.px if p[3] > 0)
    print("%d by %d, edge at %.2f, %d filaments, %d texels lit (%.1f%%)"
          % (SIZE, SIZE, band, len(threads), lit, 100.0 * lit / (SIZE * SIZE)))


if __name__ == "__main__":
    main()
