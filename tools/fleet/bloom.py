#!/usr/bin/env python3
"""The Bloom: grown rather than built. A core with lobes budded off it, nodules
on the lobes, tendrils trailing aft, and sacs on the cargo variants
(docs/17 section 8.3).

NOTHING HERE WAS MADE FOR ANYONE ELSE TO READ. Every other dialect in the fleet
is drawn by a shipwright: a Terran saucer is round because someone drew it
round, a Helion module is standard because a hundred of them have to stack. The
Bloom has no plates, no seams, no navigation lights and no axis of symmetry,
because none of those exist for the thing's own sake. It reads as a fleet only
because the same growth rules produced all ten of them.

THAT IS WHY THE PLAN BELOW IS SHORT AND THE SEED IS LONG. The other five
dialects spend a class on a different SHAPE: a Vaelith frigate is a crescent
and its dreadnought is two concentric rings. A Bloom cannot, because it never
had parts to count (docs/17 section 9), so it spends a class on how much has
grown: more lobes, and on the variants a different crop hanging off them. What
keeps a frigate from being a dreadnought at 70 percent is that each class grows
from its OWN seed, so no two of the ten put a lobe in the same place. The plan
table holds what the source derived from the class row, written out per class
so the ladder can be read at a glance beside the other five.

PORTED FROM `buildBloom` on the diorama page, so the shape a reviewer approved
is the shape the game flies. The page draws its bow at -Z and the game flies
toward +Z, so every z read from that source is negated once, at the point it is
read, and the rotations about X and Y are negated with it. Winding is computed
at emit time, so nothing here passes a normal.
"""

import math

from shipkit import CLASSES, Hull, lathe, sphere
from fleet.parts import HALF_PI, dome

# One grammar, ten crops. `core` is how long the core is as a multiple of the
# class spine, `lobes` how many buds it carries, and the last three are the
# variant crops: tendrils trailing aft on everything, spores on the skin of the
# carrier, sacs slung under the two cargo hulls. These are the source's own
# expressions evaluated per class rather than left as arithmetic in the
# builder, so the ladder reads as a table the way the other five dialects do,
# and so a class can be tuned without touching the growth rules.
#
#   core     2.2 on the cargo hulls, 1.5 on the rest: a freighter is a gut.
#   lobes    two, plus three per unit of class size, plus three when the
#            ladder doubles the body and two when it lines it with bays. That
#            is the one place a Bloom answers the ladder directly.
#   tendrils eight where the ladder asks for cranes, two where it asks for
#            cargo, three otherwise.
BLOOM_PLAN = {
    "frigate":       dict(core=1.50, lobes=4, tendrils=3, spores=0,  sacs=0),
    "destroyer":     dict(core=1.50, lobes=4, tendrils=3, spores=0,  sacs=0),
    "light_cruiser": dict(core=1.50, lobes=5, tendrils=3, spores=0,  sacs=0),
    "heavy_cruiser": dict(core=1.50, lobes=5, tendrils=3, spores=0,  sacs=0),
    "battlecruiser": dict(core=1.50, lobes=5, tendrils=3, spores=0,  sacs=0),
    "battleship":    dict(core=1.50, lobes=9, tendrils=3, spores=0,  sacs=0),
    "dreadnought":   dict(core=1.50, lobes=9, tendrils=3, spores=0,  sacs=0),
    "carrier":       dict(core=1.50, lobes=8, tendrils=3, spores=10, sacs=0),
    "freighter":     dict(core=2.20, lobes=5, tendrils=2, spores=0,  sacs=5),
    "tender":        dict(core=2.20, lobes=5, tendrils=8, spores=0,  sacs=5),
}

## The seed each class grows from, and the step between them. Both are the
## source's, because the arrangement of a hull IS these two numbers: change
## either and every lobe on all ten ships moves somewhere a reviewer has never
## seen. The ladder is read from the kit rather than copied, so a class added
## to `shipkit.CLASSES` seeds itself.
SEED = 977
SEED_STEP = 131
LADDER = tuple(c["id"] for c in CLASSES)

## How many facets each grown shape is worth. The core is flattened, so its
## rings are cheap and its SEGMENTS are what the eye reads: the waist is the
## silhouette from directly above and the profile is compressed to nothing. A
## lobe is small enough that ten sides read as round, and a nodule is a pixel
## and a half at the identification size, where its job is to break the lobe's
## edge rather than to be a dome.
##
## Every SEGMENT count here is even, which is not a detail. A lathe with an
## odd number of them does not close symmetrically about its own axis, so the
## bounding box of a lobe sits a few percent off the point the lobe was placed
## at, and a bounding box is what the attachment check, `Hull.centre` and the
## wreck's fragment cutter all measure. One more column of triangles buys a
## part that is where it says it is. Ring counts are free of this: a lathed
## profile mirrors top to bottom whatever it is cut into.
CORE_SEGS, CORE_RINGS = 14, 8
LOBE_SEGS, LOBE_RINGS = 10, 5
NODULE_SEGS, NODULE_RINGS = 6, 2
SPORE_SEGS, SPORE_RINGS = 6, 4
SAC_SEGS, SAC_RINGS = 10, 6
TENDRIL_SEGS = 6

## Nodules per lobe. Three is the source's, and it is also the count that reads
## as a cluster rather than as one bump or as a rash.
NODULES = 3

## How thick a tendril is at each end, as a fraction of the core's girth: its
## length plus its width twice, which is the closest thing a Bloom has to the
## footprint the hull is finally scaled to.
##
## The source measures both ends against the class size instead, and a tendril
## sized that way disappears on exactly the hulls that have the most of them.
## The core lengthens faster up the ladder than the class size does, so a
## dreadnought is drawn smaller for its length than a frigate, and its tendrils
## came out under a pixel wide at the identification size: not a thin line but
## a dotted one, which is section 2.1's two blobs where a hull must have one.
## Section 2.1 says the fix for that is a thicker pylon and not a note, so the
## thickness is measured against the hull rather than against the class, and
## every one of the ten now draws its tendrils about three pixels wide at
## sixty. The taper is the source's, near enough three to one root to tip.
TENDRIL_ROOT = 0.030
TENDRIL_TIP = 0.011

## How far a nodule is sunk into the lobe it grew from, as a fraction of the
## lobe's radius in that direction. Section 2.1 wants a mounted greeble
## embedded in its part rather than resting on it, and a tenth of a lobe is
## deep enough to survive the rounding in a scaled ellipsoid.
NODULE_SINK = 0.90


def _seeded(seed):
    """The diorama page's generator, reproduced draw for draw.

    It is here rather than in the kit because the Bloom is the one dialect that
    is seeded; if a second one ever needs it, lift this into `shipkit` rather
    than writing a second copy (CLAUDE.md section 4.1).

    THE ARITHMETIC IS DELIBERATELY IMPRECISE. JavaScript multiplies in a double
    and the product runs past 2**53, so the low bits of every draw after the
    first are rounded away before the mask sees them. Doing it exactly in
    Python's unbounded integers is a DIFFERENT generator: it agrees on the
    first draw and has diverged by the second, which would move every lobe on
    every hull off the arrangement that was reviewed. So the product is taken
    in a float, wrapped to 32 bits the way a JavaScript bitwise operator wraps
    it, and only then masked to the 31 bits the source divides by.
    """
    n = seed

    def rnd():
        nonlocal n
        x = n * 1103515245.0 + 12345.0
        n = int(math.fmod(x, 4294967296.0)) & 0x7fffffff
        return n / 2147483647.0

    return rnd


def _tendril(length, root_r, tip_r):
    """A tapered tube lying along Z, thick at the bow end, trailing to a point.

    Not `parts.cannon`, which is a barrel with a mouth and barely tapers, and
    not `shipkit.cone`, which comes to a point at both the wrong end and the
    wrong angle. A profile revolved by the kit's own lathe is the honest way to
    say a shape that is three times thinner at one end than the other; if a
    second dialect ever grows one, lift this into `shipkit`.
    """
    return lathe([(0.0, -length * 0.5), (tip_r, -length * 0.5),
                  (root_r, length * 0.5), (0.0, length * 0.5)],
                 TENDRIL_SEGS).rotate_x(HALF_PI)


## Where round the core a bud sits, named the way the ship systems display and
## the wreck have to say it. The Bloom has no port and starboard of its own, so
## the words are the viewer's rather than the ship's.
_BEARING = ("to starboard", "above", "to port", "below")


def _bud_name(i, angle, z, cl):
    """A name for a lobe, from where on the core it grew."""
    bearing = _BEARING[int(round(angle / HALF_PI)) % 4]
    if z > cl * 0.2:
        along = "forward"
    else:
        along = "aft" if z < -cl * 0.2 else "amidships"
    return "lobe %d, budded %s %s" % (i + 1, bearing, along)


def build(cls):
    """cls is a row of shipkit.CLASSES. Returns a shipkit.Hull."""
    h = Hull("bloom", cls["id"])
    Z = cls["size"]
    k_disc = cls["disc"] * Z if "disc" in cls else Z
    k_spine = cls["spine"] * Z
    plan = BLOOM_PLAN.get(cls["id"], BLOOM_PLAN["light_cruiser"])
    idx = LADDER.index(cls["id"]) if cls["id"] in LADDER else 0
    rnd = _seeded(SEED + idx * SEED_STEP)

    # The core: one flattened ellipsoid, and the only part of a Bloom that is
    # about the same on all ten hulls. Everything else is what grew on it.
    # `girth` is its length plus its width twice, which is what the tendrils
    # are measured against so that they survive being drawn at sixty pixels.
    cl = plan["core"] * k_spine
    cw = 0.9 * k_disc
    ch = 0.55 * Z
    girth = cl + 2.0 * cw
    h.part(sphere(1.0, CORE_SEGS, CORE_RINGS).scale(cw, ch, cl),
           "organic", "the core", (0.0, 0.0, 0.0))

    # ---- the lobes ----------------------------------------------------------
    # Each one is budded through the skin rather than stuck to it: the centre
    # sits at 0.85 of the core's half width, which is inside the surface
    # everywhere the source puts one, so a lobe is always eating into the core
    # and never resting against it. That is section 2.1's failure mode for this
    # dialect, and it is answered by the placement rather than by a check.
    for i in range(plan["lobes"]):
        a = rnd() * math.pi * 2.0
        t = rnd() * 0.7 + 0.15
        s = (0.35 + rnd() * 0.35) * Z
        sy = 0.6 + rnd() * 0.5
        sz = 0.9 + rnd() * 0.8
        turn = rnd() * 0.6
        lx = math.cos(a) * cw * 0.85
        ly = math.sin(a) * ch * 0.8
        lz = -(t - 0.5) * cl * 1.6
        name = _bud_name(i, a, lz, cl)
        h.part(sphere(1.0, LOBE_SEGS, LOBE_RINGS).scale(s, s * sy, s * sz)
               .rotate_y(-turn).translate(lx, ly, lz),
               "organic", name,
               (math.cos(a), math.sin(a) * 0.5, -0.2))

        # Nodules. The source seats them on a sphere of radius s, s * 0.8 and
        # s * 1.2, which is the lobe's average stretch rather than this lobe's:
        # on a slim bud they float off it, which is one piece too many by
        # section 2.1 and a rash of loose dots on the schematic. They are
        # seated on the lobe's OWN surface here, and sunk a tenth into it.
        for k in range(NODULES):
            b = rnd() * math.pi * 2.0
            e = rnd() * math.pi - HALF_PI
            lit = rnd() < 0.5
            nr = (0.04 + rnd() * 0.05) * Z
            if lit:
                # The source picks one of two glow ramps here. Colour is
                # paint.py's business, but the draw has to be spent or every
                # shape after this nodule grows somewhere else.
                rnd()
            dx = math.cos(b) * math.cos(e)
            dy = math.sin(e)
            dz = math.sin(b) * math.cos(e)
            g = dome(nr, NODULE_SEGS, NODULE_RINGS)
            g.rotate_y(b).rotate_x(HALF_PI - e)
            g.translate(dx * s * NODULE_SINK, dy * s * sy * NODULE_SINK,
                        -dz * s * sz * NODULE_SINK)
            g.rotate_y(-turn).translate(lx, ly, lz)
            h.part(g, "glow" if lit else "greeble",
                   "%snodule %d on %s" % ("lit " if lit else "", k + 1, name),
                   (dx, dy, -dz), glow=lit)

    # ---- the tendrils -------------------------------------------------------
    # Rooted three quarters of the way along the core so the thick end is
    # inside it, and thinning to nothing astern. They are the one thing on the
    # hull that reaches outside its own outline, which is what a Bloom is
    # recognised by from directly above.
    for i in range(plan["tendrils"]):
        a = rnd() * math.pi * 2.0
        tl = (0.6 + rnd() * 0.8) * Z
        turn = (rnd() - 0.5) * 0.5
        tilt = (rnd() - 0.5) * 0.4
        g = _tendril(tl, TENDRIL_ROOT * girth, TENDRIL_TIP * girth)
        g.rotate_y(-turn).rotate_x(-tilt)
        g.translate(math.cos(a) * cw * 0.6, math.sin(a) * ch * 0.6,
                    -(cl * 0.75 + tl * 0.45))
        h.part(g, "organic", "tendril %d, trailing aft" % (i + 1),
               (0.0, 0.0, -1.0))

    # ---- the carrier's spores -----------------------------------------------
    # Hanging on the skin, where a Terran carrier has bay mouths. The core
    # narrows aft, so each one is placed on the ellipse at its own station
    # rather than on the widest part of it, which is the source's arithmetic
    # and the reason they follow the hull instead of drifting off the stern.
    for i in range(plan["spores"]):
        a = rnd() * math.pi * 2.0
        d = (0.02 + rnd() * 0.08) * Z
        r = (0.06 + rnd() * 0.07) * Z
        sz = cl * (0.3 + rnd() * 0.55)
        f = math.sqrt(max(0.0, 1.0 - (sz / cl) * (sz / cl)))
        # A spore stood off by more than six tenths of its own radius is
        # resting on the skin rather than growing out of it, so the stand off
        # is clamped. The source could afford the gap because nothing there
        # measured whether a piece was attached.
        d = min(d, r * 0.6)
        h.part(sphere(r, SPORE_SEGS, SPORE_RINGS)
               .translate(math.cos(a) * (cw * f + d),
                          math.sin(a) * (ch * f + d), -sz),
               "glow", "spore %d, on the skin" % (i + 1),
               (math.cos(a), math.sin(a), -1.0), glow=True)

    # ---- the cargo hulls' sacs ----------------------------------------------
    # Slung under the core in a row, which is a Bloom saying the word cargo:
    # the other dialects clamp a container to a frame, this one grows a gut and
    # swallows it.
    for i in range(plan["sacs"]):
        x = (rnd() - 0.5) * cw * 0.6
        h.part(sphere(0.3 * Z, SAC_SEGS, SAC_RINGS).scale(1.0, 0.8, 1.3)
               .translate(x, -ch * 0.7, -(i / 4.0 - 0.5) * cl * 1.3),
               "organic", "sac %d, slung under the core" % (i + 1),
               (0.0, -1.0, 0.0))
    return h
