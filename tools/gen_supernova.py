#!/usr/bin/env python3
# Generates the committed supernova burst: assets/textures/fx_supernova.png.
#
# The heart of a capital ship's nova, in the style of the old tactical games
# this project descends from: a white hot centre inside a red and purple
# corona, with rays streaming out of it. It is billboarded, unlike the plasma
# ring, which lies on the battle plane. The two are opposite on purpose: the
# ring is a front moving THROUGH the world, so it belongs to the world's plane,
# while the burst is a point of light too bright to have a shape, and a glare
# faces every camera.
#
# THREE PARTS, hottest to coldest along one ramp:
#
#   Core    a small saturated disc, cream from edge to edge. The one part of
#           the picture allowed to be flat, because the middle of a detonation
#           is past having detail.
#   Corona  the falloff around it, rose through wine to plum. Slightly uneven,
#           two low harmonics, so the glare is not a stamped circle.
#   Rays    a few dozen radial streaks of differing length and strength, the
#           part that says LIGHT rather than ball. They start inside the
#           corona so they read as coming out of it, not as parked around it.
#
# Per CLAUDE.md section 3 an art asset is delivered as a .png, and per 5.1 a
# script may generate one only by WRITING THE FILE, never by building it at
# runtime. Every pixel is a Waldgeist entry named through the "supernova" ramp
# in data/palette.json (3.1), and verify_palette() stops the run before an off
# palette pixel can be written. ALPHA CARRIES THE BRIGHTNESS, the ramp carries
# the colour, exactly as the plasma ring does: the material adds, so a texel's
# alpha is how much light it contributes.
#
# EVERYTHING IS A CLOSED FORM OF POSITION, and the scatter comes from a seeded
# generator, so running this twice writes the same bytes.

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shiplib import Px, bayer, load_fx_ramp, ramp_index

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PALETTE = os.path.join(ROOT, "data", "palette.json")
OUT = os.path.join(ROOT, "assets", "textures", "fx_supernova.png")

SIZE = 256
SEED = 20260806

# The white heart, as a fraction of the half width, and how quickly the corona
# falls away outside it. The corona's reach is where it has faded to nothing.
CORE = 0.16
CORONA_REACH = 0.88
CORONA_POWER = 2.1
CORONA_STRENGTH = 3.6

# How far the glare wanders from a circle. Kept gentle: this is unevenness in
# a glow, not the ragged edge the plasma ring has.
WOBBLE_A = 0.05
WOBBLE_B = 0.03

# The rays. Lengths are fractions of the half width past the core; a few long
# ones carry the star shape and the short ones fill the corona with grain.
RAYS = 72
RAY_MIN = 0.18
RAY_MAX = 0.86
RAY_LIT_MIN = 0.6
RAY_LIT_MAX = 3.6

# Below this a texel is left empty, for the reason the ring records: additive
# blending means a texel this faint adds nothing anyone can see.
FLOOR = 0.035


def rays(rng):
    """The streaks: a bearing, a reach past the core, and a brightness.

    Length and brightness are drawn together from one skewed roll, so the long
    rays are also the bright ones. Independent draws produce long faint rays,
    which read as scratches across the glow rather than as light coming out of
    it."""
    out = []
    span = 2.0 * math.pi / RAYS
    for i in range(RAYS):
        bearing = span * i + rng.uniform(-span * 0.45, span * 0.45)
        # Cubed, so most rays are short and a handful carry the star shape.
        roll = pow(rng.random(), 3.0)
        out.append({
            "bearing": bearing,
            "reach": RAY_MIN + (RAY_MAX - RAY_MIN) * roll,
            "lit": RAY_LIT_MIN + (RAY_LIT_MAX - RAY_LIT_MIN) * roll
                * rng.uniform(0.7, 1.0),
        })
    return out


def corona_at(bearing):
    """The corona's reach at one bearing, wandering gently off a circle."""
    return CORONA_REACH * (1.0
                           + WOBBLE_A * math.sin(3.0 * bearing + 1.1)
                           + WOBBLE_B * math.sin(5.0 * bearing + 4.2))


def field(size, streaks):
    """How much light is at each texel, from 0 to several at the heart."""
    half = size * 0.5
    heat = [0.0] * (size * size)

    # Core and corona in one radial pass.
    for y in range(size):
        dy = y + 0.5 - half
        for x in range(size):
            dx = x + 0.5 - half
            r = math.sqrt(dx * dx + dy * dy) / half
            reach = corona_at(math.atan2(dy, dx))
            if r >= reach:
                continue
            # Flat and far past 1 inside the core, then a power falloff to the
            # corona's edge. The tone map compresses rather than clamps, so
            # only something this hot reaches the cream at the ramp's top.
            if r <= CORE:
                # Far past what the tone map can pull below the ramp's top:
                # 30 maps to 0.97, and 0.97 rounds to index 0 under any
                # dither, which is what makes the heart FLAT cream rather
                # than a stipple of cream and rose.
                heat[y * size + x] += 30.0
            else:
                k = (r - CORE) / max(reach - CORE, 0.001)
                heat[y * size + x] += CORONA_STRENGTH * pow(1.0 - k, CORONA_POWER)

    # The rays, walked outward from inside the core. Each step also feeds the
    # texel one over, perpendicular to the ray, at half strength: one texel of
    # width reads as a scratch across the glow, two read as a shaft of light,
    # and the half strength edge is what keeps the shaft from being a bar.
    for s in streaks:
        cs = math.cos(s["bearing"])
        sn = math.sin(s["bearing"])
        r0 = CORE * 0.5 * half
        r1 = (CORE + s["reach"]) * half
        steps = int(r1 - r0) + 2
        for i in range(steps + 1):
            k = i / float(steps)
            # Full strength leaving the core, gone at the tip.
            lit = s["lit"] * pow(1.0 - k, 1.6)
            r = r0 + (r1 - r0) * k
            fx = half + cs * r
            fy = half + sn * r
            for (px_, py_, share) in ((fx, fy, 1.0), (fx - sn, fy + cs, 0.5)):
                x = int(px_)
                y = int(py_)
                if 0 <= x < size and 0 <= y < size:
                    heat[y * size + x] += lit * share
    return heat


def paint(px, size, heat, ramp):
    """The light field, painted through the ramp with the strength in alpha."""
    for y in range(size):
        for x in range(size):
            v = heat[y * size + x]
            if v <= FLOOR:
                continue
            d = bayer(x, y)
            # Compressed rather than clamped, so the ramp's top is reserved
            # for the genuinely hot: the core, and where a bright ray rides
            # the inner corona.
            near = v / (v + 0.85)
            index = ramp_index(near, ramp, float(len(ramp)), d)
            if index >= len(ramp):
                continue
            px.put(x, y, ramp[index], min(255, int(v * 300.0 + 0.5)))


def verify_palette(px, allowed):
    """The same gate the ship painter passes: every painted texel is a palette
    entry, checked before the file is written rather than after."""
    for r, g, b, a in px.px:
        if a == 0:
            continue
        assert (r, g, b) in allowed, "off palette pixel %r" % ((r, g, b),)


def main():
    ramp = load_fx_ramp(PALETTE, "supernova")
    rng = random.Random(SEED)
    heat = field(SIZE, rays(rng))

    px = Px(SIZE, background=(0, 0, 0), height=SIZE, alpha=0)
    paint(px, SIZE, heat, ramp)
    verify_palette(px, set(ramp))
    px.save(OUT)
    lit = sum(1 for p in px.px if p[3] > 0)
    print("%d by %d, %d rays, %d texels lit (%.1f%%)"
          % (SIZE, SIZE, RAYS, lit, 100.0 * lit / (SIZE * SIZE)))


if __name__ == "__main__":
    main()
