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

# How many threads the ring is made of, and how far each runs in and out from
# the band, in fractions of the image's half width. Enough of them that the
# ring reads as continuous at a distance and as threads up close.
FILAMENTS = 340
OUT_MIN = 0.04
OUT_MAX = 0.17
IN_MIN = 0.02
IN_MAX = 0.09

# The knots: short filaments drawn far brighter than the rest, which is what
# puts cream coloured points along the band. Without them the ring is evenly
# bright and reads as printed rather than as burning.
KNOTS = 54

# The continuous glow the threads stand on, as a fraction of the half width. A
# ring of loose threads with nothing behind it reads as a dashed line.
GLOW_WIDTH = 0.035
GLOW_STRENGTH = 1.05

# How far the band wanders from a perfect circle. Two low harmonics, because
# one reads as an egg and three reads as noise.
WOBBLE_A = 0.020
WOBBLE_B = 0.013

# Below this a texel is left empty. Additive blending means a texel this faint
# adds nothing anyone can see, and leaving it out keeps the sprite's edge from
# being a visible square of almost black.
FLOOR = 0.035


def band_frac():
    """Where the bright band sits, as a fraction of the image's half width.

    Read from data/tuning.json rather than written here, because the code that
    scales the ring in the world has to agree with the art about where the band
    is or the shell will be drawn at the wrong radius. One number, one file
    (CLAUDE.md 5.4)."""
    import json
    with open(TUNING) as f:
        return float(json.load(f)["explosion"]["plasma_band_frac"])


def filaments(rng):
    """The threads: where each one sits, how far it runs, and how bright.

    Spread around the circle with the jitter smaller than the spacing, for the
    reason the fireball's billows already record: independent draws leave gaps
    often enough to be noticed, and a gap in a ring reads as a bug."""
    out = []
    span = 2.0 * math.pi / FILAMENTS
    for i in range(FILAMENTS):
        bearing = span * i + rng.uniform(-span * 0.45, span * 0.45)
        out.append({
            "bearing": bearing,
            "out": rng.uniform(OUT_MIN, OUT_MAX),
            "in": rng.uniform(IN_MIN, IN_MAX),
            # Squared, so most threads are middling and a few are bright. A
            # uniform draw gives an evenly lit fringe, which is a brush and not
            # a plasma front.
            "lit": 0.5 + 1.5 * pow(rng.random(), 2.0),
        })
    for i in range(KNOTS):
        out.append({
            "bearing": rng.uniform(0.0, 2.0 * math.pi),
            "out": rng.uniform(0.01, 0.035),
            "in": rng.uniform(0.01, 0.03),
            # Far above the threads around them, because a knot has to reach
            # the cream at the top of the ramp on its own rather than only
            # where two threads happen to cross.
            "lit": 3.4,
        })
    return out


def band_at(bearing, band):
    """The band's radius at one bearing, wandering off a perfect circle."""
    return band * (1.0
                   + WOBBLE_A * math.sin(3.0 * bearing + 0.7)
                   + WOBBLE_B * math.sin(7.0 * bearing + 2.3))


def field(size, threads, band):
    """How much light is at each texel, from 0 to about 1."""
    half = size * 0.5
    heat = [0.0] * (size * size)

    # The threads. Walked along their own radius rather than rasterised as
    # lines, which is what keeps each one exactly one texel wide however close
    # to the middle it starts.
    for f in threads:
        cs = math.cos(f["bearing"])
        sn = math.sin(f["bearing"])
        r0 = band_at(f["bearing"], band) - f["in"]
        r1 = band_at(f["bearing"], band) + f["out"]
        steps = int((r1 - r0) * half * 2.0) + 2
        for s in range(steps + 1):
            k = s / float(steps)
            r = (r0 + (r1 - r0) * k) * half
            # Brightest where the thread crosses the band and gone at both of
            # its ends, so a thread is a streak rather than a stick.
            at_band = (band_at(f["bearing"], band) * half - r) \
                / max((r1 - r0) * half * 0.5, 0.5)
            lit = f["lit"] * max(0.0, 1.0 - abs(at_band)) ** 1.4
            x = int(half + cs * r)
            y = int(half + sn * r)
            if 0 <= x < size and 0 <= y < size:
                heat[y * size + x] += lit

    # The glow the threads stand on.
    for y in range(size):
        dy = y + 0.5 - half
        for x in range(size):
            dx = x + 0.5 - half
            r = math.sqrt(dx * dx + dy * dy) / half
            if r <= 0.0:
                continue
            here = band_at(math.atan2(dy, dx), band)
            away = abs(r - here) / GLOW_WIDTH
            if away >= 3.0:
                continue
            heat[y * size + x] += GLOW_STRENGTH * math.exp(-away * away)
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
    print("%d by %d, band at %.2f, %d filaments, %d texels lit (%.1f%%)"
          % (SIZE, SIZE, band, len(threads), lit, 100.0 * lit / (SIZE * SIZE)))


if __name__ == "__main__":
    main()
