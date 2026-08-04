#!/usr/bin/env python3
# Generates the committed explosion flipbook: assets/textures/fx_explosion.png.
#
# Per CLAUDE.md section 3 an art asset is delivered as a .png, and per 5.1 a
# script may generate one only by WRITING THE FILE, never by building it at
# runtime. This writes one sheet of frames that scenes/explosion.tscn plays
# back through a Sprite3D.
#
# WHY A FLIPBOOK AT ALL, when every other effect in this game is tinted
# geometry. A detonation's first moment is turbulent: fingers of burning gas
# punched out through a shell that is already breaking up, all of it in the
# tenth of a second before it becomes a fireball. Stacked discs cannot draw
# that, and the version that tried read as a cartoon starburst. Shape that
# complicated is cheaper to draw once into pixels than to assemble out of
# meshes, and a sheet has the further advantage of being a .png anyone can
# open and repaint.
#
# It is not a licence to texture everything. The billows, embers and shock
# front stay geometry, because they are simple shapes whose SIZE is the thing
# that changes, and geometry stays crisp at every zoom where a magnified pixel
# sprite does not. The flipbook covers only the first instant, drawn once at a
# size the camera rarely gets close to.
#
# Every pixel is a Waldgeist entry named through the "explosion" ramp in
# data/palette.json (CLAUDE.md 3.1): this file asks for a ramp, and only the
# palette file says what colours are in it. verify_palette() below is the same
# gate the ship painter passes, so an off palette pixel stops the run before
# anything is written.
#
# EVERYTHING IS A CLOSED FORM OF THE FRAME NUMBER, and the scatter comes from a
# seeded generator, so the sheet is reproducible: running this twice writes the
# same bytes, and a diff on the .png means somebody changed the numbers.

import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shiplib import Px, load_fx_ramp

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PALETTE = os.path.join(ROOT, "data", "palette.json")
OUT = os.path.join(ROOT, "assets", "textures", "fx_explosion.png")

# Five by five, which is 25 frames. Played over the flash's fifth of a second
# that is about 140 a second, far more than the eye needs, so the same sheet
# also serves a slower playback without going to slideshow.
COLS = 5
ROWS = 5
# Per frame, in pixels. The sheet lands at 640 square, which is the size of one
# hull atlas: a detonation is a whole ship's worth of art and it is drawn at
# several times the hull's own size.
CELL = 128

# The blobs the fireball is made of. Enough that no one of them can be picked
# out, which is the same count and the same reason the geometry billows use.
PUFFS = 44
SEED = 20260804

# How far a puff is thrown, as a fraction of the cell's half width, and how
# large it is drawn. Both are fractions rather than pixels so the cell size can
# change without every number moving.
THROW = 0.66
PUFF_MIN = 0.13
PUFF_MAX = 0.32
# An exponent above 1 on a rising quantity means it starts fast and slows,
# which is what anything thrown by a blast does once the front has passed it.
THROW_EASE = 2.4
# The core is the white hot middle: the part that is still a ball while the
# fingers are already reaching. It burns down rather than being thrown.
CORE_FROM = 0.30
CORE_TO = 0.52
# Below this a pixel is empty rather than dark. A detonation has to end as
# nothing, not as a grey disc.
FLOOR = 0.055

# The 4x4 ordered matrix every dither in this repo uses. Two jobs here: it
# picks between the two ramp entries a value falls between, which is what keeps
# a smooth field on a nine colour palette from banding into rings, and it
# stipples the rim so the sprite ends in scattered pixels rather than on a
# circle.
BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def puffs(rng):
    """The fireball's blobs: where each is thrown, how big it is drawn, when it
    lights and how long it burns.

    Spread around the circle rather than drawn at random, with the jitter
    smaller than the spacing. Independent draws leave gaps and clumps often
    enough to be noticed, and a gap in a fireball reads as a bug rather than as
    chance. The geometry fireball makes the same choice for the same reason."""
    # HOW FAR A PUFF IS THROWN IS DECORRELATED FROM WHICH WAY, and that one
    # line is the difference between a fireball and a logo. Tiered by the same
    # index that sets the bearing, the throw wound steadily around the circle
    # and every frame came out as the same comma shaped spiral, which the eye
    # reads as a drawn shape rather than as burning gas. Shuffled, the tiers
    # land in no order and the outline is ragged.
    tiers = [i / float(PUFFS - 1) for i in range(PUFFS)]
    rng.shuffle(tiers)
    out = []
    for i in range(PUFFS):
        span = 2.0 * math.pi / PUFFS
        bearing = span * i + rng.uniform(-span * 0.42, span * 0.42)
        tier = tiers[i]
        out.append({
            "dir": (math.sin(bearing), -math.cos(bearing)),
            # The inner tier stays near the middle, so the cloud is hot at its
            # heart and ragged at its edge rather than being a uniform ring.
            "reach": THROW * (0.18 + 0.82 * tier) * rng.uniform(0.72, 1.22),
            # Thrown further is drawn bigger, which is both what expanding gas
            # does and what closes the gap the throw opens.
            "size": (PUFF_MIN + (PUFF_MAX - PUFF_MIN) * tier)
                    * rng.uniform(0.78, 1.25),
            # EACH PUFF HAS ITS OWN CLOCK. Lit together and put out together,
            # forty four discs pulse as one shape and the eye finds every edge
            # in it; staggered, the same forty four read as churn.
            # Early, and all of them within the first fifth. A detonation is
            # at its most violent in its first instant, so the fingers have to
            # be out while the middle is still white: staggered over a third of
            # the life, the opening frames were a plain ball with nothing
            # coming off it.
            "born": rng.uniform(0.0, 0.17),
            "life": rng.uniform(0.55, 0.95),
        })
    return out


def field(cell, blobs, t):
    """How much fire is at each pixel of one frame, from 0 to about 1.

    A sum of blobs plus a core, which is the same model the geometry explosion
    draws with meshes. Doing it here as well is not a second implementation of
    anything: what this produces is a committed .png, and the code that plays
    it back knows only which frame to show."""
    half = cell * 0.5
    heat = [0.0] * (cell * cell)

    for b in blobs:
        k = (t - b["born"]) / b["life"]
        if k < 0.0 or k >= 1.0:
            continue
        out = 1.0 - pow(1.0 - k, THROW_EASE)
        # Lights at once, then burns down over the rest of its own life.
        lit = min(1.0, k * 7.0) * pow(1.0 - k, 1.3)
        # Swells as it goes, so the cloud thickens as it spreads instead of
        # thinning into separate dots.
        radius = (0.34 + 0.66 * math.sqrt(k)) * b["size"] * half
        cx = half + b["dir"][0] * b["reach"] * out * half
        cy = half + b["dir"][1] * b["reach"] * out * half
        x0 = max(0, int(cx - radius) - 1)
        x1 = min(cell, int(cx + radius) + 2)
        y0 = max(0, int(cy - radius) - 1)
        y1 = min(cell, int(cy + radius) + 2)
        inv = 1.0 / max(radius, 0.5)
        for y in range(y0, y1):
            dy = (y + 0.5 - cy) * inv
            for x in range(x0, x1):
                dx = (x + 0.5 - cx) * inv
                d = dx * dx + dy * dy
                if d >= 1.0:
                    continue
                heat[y * cell + x] += lit * pow(1.0 - d, 1.7)

    # The white hot middle, which is a ball while the fingers are still
    # reaching. Held at full for the first fifth and then dropped, because an
    # intensity that starts falling at once never reads as a flash.
    core_r = (CORE_FROM + (CORE_TO - CORE_FROM) * math.sqrt(t)) * half
    # Held at full for the first half and then dropped. Well above 1 on
    # purpose: the tone map below compresses rather than clamps, so the only
    # way anything reaches the top of the ramp is to be several times as hot as
    # the fire around it, which is exactly what the middle of a detonation is.
    # OUT BEFORE THE FIRE IS. Run to the full life it outlived the puffs and
    # the last frames were a smooth glowing ball with nothing in it, which is
    # the same mistake the geometry fireball's own comment records. What should
    # be left at the end is smoke.
    core_lit = 5.2 * pow(max(0.0, 1.0 - t / 0.55), 1.4)
    if core_lit > 0.0:
        inv = 1.0 / core_r
        for y in range(cell):
            dy = (y + 0.5 - half) * inv
            for x in range(cell):
                dx = (x + 0.5 - half) * inv
                d = dx * dx + dy * dy
                if d < 1.0:
                    heat[y * cell + x] += core_lit * pow(1.0 - d, 2.2)
    return heat


def paint(px, ox, oy, cell, heat, ramp, t):
    """One frame of heat, painted through the ramp.

    Hot is the front of the ramp and cold is the back, so a pixel's index is
    how far down it has cooled. The whole frame slides toward the cold end as
    it ages, which is what turns fire into smoke without a second field to
    track."""
    top = len(ramp) - 1
    # What the coldest lit pixel is allowed to be. Early it stops at the reds,
    # so nothing in a fresh detonation is ash coloured; late it reaches the
    # end, which is where the smoke lives.
    reach = 3.0 + 6.0 * pow(t, 0.7)
    for y in range(cell):
        for x in range(cell):
            v = heat[y * cell + x]
            if v <= 0.0:
                continue
            b = (BAYER[y & 3][x & 3] + 0.5) / 16.0
            # The rim ends in scattered pixels rather than on a circle: a
            # threshold that varies per pixel is a stipple, and a stipple is
            # what a hard alpha palette has instead of a soft edge.
            if v < FLOOR * (0.45 + 1.9 * b):
                continue
            # Compressed rather than clamped. A sum of overlapping blobs runs
            # well past 1 wherever several meet, and clamping it painted every
            # one of those pixels the same cream: the first cut of this was a
            # white disc with a thin orange rim, which is a lamp again. This
            # keeps climbing, slowly, so the heart of the fire still has
            # structure in it.
            near = v / (v + 0.75)
            step = (1.0 - near) * reach
            index = int(step + b)
            if index > top:
                continue
            px.put(ox + x, oy + y, ramp[index])


def verify_palette(px, allowed):
    """The same gate the ship painter passes: every painted pixel is a palette
    entry, checked before the file is written rather than after."""
    for r, g, b, a in px.px:
        if a == 0:
            continue
        assert (r, g, b) in allowed, "off palette pixel %r" % ((r, g, b),)


def main():
    ramp = load_fx_ramp(PALETTE, "explosion")
    allowed = set(ramp)
    rng = random.Random(SEED)
    blobs = puffs(rng)

    px = Px(CELL * COLS, background=(0, 0, 0), height=CELL * ROWS, alpha=0)
    frames = COLS * ROWS
    for i in range(frames):
        t = (i + 0.5) / frames
        heat = field(CELL, blobs, t)
        paint(px, (i % COLS) * CELL, (i // COLS) * CELL, CELL, heat, ramp, t)

    verify_palette(px, allowed)
    px.save(OUT)
    print("%d frames, %d by %d, %d colours"
          % (frames, CELL * COLS, CELL * ROWS, len(ramp)))


if __name__ == "__main__":
    main()
