#!/usr/bin/env python3
"""The Vaelith Ascendancy: a downturned beak with one warm eye, and a flat
hollow loop with the drives standing inside it (docs/17 section 8.4).

THE HOLE IS THE SILHOUETTE. Everything else in the grammar is there to keep it
readable at sixty pixels. The head sits on the centreline ahead of the ring and
nothing else does; the drives stand INSIDE the ring rather than outboard of it,
so the ship's outline stays a closed curve with a hole in the middle. There are
no wings in this dialect, and there is never a second loop beside the first:
both were tried on the diorama page and both were rejected, because a pair of
loops reads as two ships flying in formation and a wing fills in the hole that
is the whole point.

CLASS IS THE LOOP'S SHAPE, which is why the plan below is a table and not a few
multipliers. A crescent, a horseshoe open aft, a circle, an ellipse pinched
across, an ellipse pinched fore and aft, a wheel with two spokes and a hub, an
egg fuller at the stern, a pair of concentric rings. A frigate and a
dreadnought therefore differ in OUTLINE and not only in size, which is the
thing two earlier cuts of this fleet got wrong.

Ported from `buildVaelith` on the diorama page, so the shape a reviewer
approved is the shape the game flies. The page draws its bow at -Z and the game
flies toward +Z, so every z here is the negative of the one in the source and
the rotations about X and Y are negated with it.
"""

import math

from shipkit import Hull, annulus, box, egg, horseshoe, lathe, prism
from fleet.parts import (bay_housing, cannon, cargo_run, collector, crane,
                         dome, pod, spike)

# One grammar, ten plans. `loop` is the shape of the ring, `gap` the size of the
# bite a horseshoe has taken out of its stern in degrees, `head` which of the
# three heads is on the centreline, and `sx`/`sz` stretch the ring across and
# fore and aft. Keyed by class id the way the source keys it, so the two tables
# can be read side by side.
VAE_PLAN = {
    "frigate":       dict(loop="horseshoe",  gap=180, head="beak",  sx=1.00, sz=1.00),
    "destroyer":     dict(loop="horseshoe",  gap=70,  head="beak",  sx=1.00, sz=1.00),
    "light_cruiser": dict(loop="round",      gap=0,   head="beak",  sx=1.00, sz=1.00),
    "heavy_cruiser": dict(loop="oval",       gap=0,   head="spade", sx=0.85, sz=1.30),
    "battlecruiser": dict(loop="oval",       gap=0,   head="lance", sx=1.15, sz=0.85),
    "battleship":    dict(loop="wheel",      gap=0,   head="spade", sx=1.00, sz=1.05),
    "dreadnought":   dict(loop="concentric", gap=0,   head="lance", sx=1.00, sz=1.10),
    "carrier":       dict(loop="egg",        gap=0,   head="spade", sx=1.10, sz=1.20),
    "freighter":     dict(loop="horseshoe",  gap=70,  head="beak",  sx=1.00, sz=1.15),
    "tender":        dict(loop="oval",       gap=0,   head="beak",  sx=0.90, sz=1.10),
}

## What each head is called on the ship systems display and in the wreck. The
## eye is a part of its own rather than a face of the head, because it is only
## light and the atlas paints light from its own rectangle.
HEAD_NAME = {"beak": "the beak, downturned", "spade": "the spade head",
             "lance": "the lance"}

## How long each head is, as a multiple of the class size. The lance is twice
## the spade because the two heads are saying opposite things: a spade is a
## broad ram with guns on its shoulders, a lance is a needle.
HEAD_LEN = {"spade": 0.9, "lance": 1.8, "beak": 1.2}

## Where the spikes sit on the ring, in degrees from the bow. A crescent is
## open behind the beam so its pair moves forward to stay on the arc.
SPIKES = (120.0, 240.0)
CRESCENT_SPIKES = (70.0, 290.0)

## The angle a ring is cut open at: dead astern. Both the shape and every mount
## that has to skip the bite measure from here.
STERN = math.pi

## Facets round the ring. Eight more than the kit's default, which is what the
## page asked for and what this dialect in particular is worth spending them
## on: the hole is the silhouette, so the one curve a player reads this faction
## by is the one curve that should not show its corners. The concentric class's
## second ring keeps the default, being small and inside the first.
RING_SEGS = 48


def _ellipse_r(a, rx, rz):
    """The radius of an ellipse `rx` across and `rz` fore and aft, at angle `a`.

    Angles run the way the kit's ring primitives wind: x is sin(a) and z is
    cos(a), so zero is the bow and pi is the stern. Every mount on a ring is
    placed through this rather than through the ring's own vertices, so studs,
    spikes and bays follow whichever of the eight shapes the class asked for.
    """
    return rx * rz / math.sqrt((rz * math.sin(a)) ** 2 + (rx * math.cos(a)) ** 2)


def _egg_k(a):
    """How much fuller than a circle the carrier's ring is at this angle.

    The same expression `shipkit.egg` builds its outline from, so a bay placed
    through it lands on the ring rather than beside it.
    """
    return 1.0 + 0.22 * max(0.0, -math.cos(a))


def _in_gap(a, gap):
    """Is this angle inside a horseshoe's bite, plus about eight degrees?

    The margin is what keeps a mount off a cut end, where it would hang half in
    space and read as a piece coming adrift from one camera angle.
    """
    if gap <= 0.0:
        return False
    d = (a - STERN) % (2.0 * math.pi)
    if d > math.pi:
        d -= 2.0 * math.pi
    return abs(d) < gap * 0.5 + 0.15


def build(cls):
    """cls is a row of shipkit.CLASSES. Returns a shipkit.Hull."""
    h = Hull("vaelith", cls["id"])
    Z = cls["size"]
    k_disc = cls["disc"] * Z if "disc" in cls else Z
    k_spine = cls["spine"] * Z
    plan = VAE_PLAN.get(cls["id"], VAE_PLAN["light_cruiser"])
    sx, sz = plan["sx"], plan["sz"]
    gap = math.radians(plan["gap"])

    # The ring, and the hole inside it. `hole_x` and `hole_z` are where the
    # drives and the cargo rails have to reach to be attached to anything.
    ring_r = 1.75 * k_disc
    hole_r = ring_r * 0.66
    rx, rz = ring_r * sx, ring_r * sz
    hole_x, hole_z = hole_r * sx, hole_r * sz
    thick = 0.14 * Z
    # The ring lies on the origin. The other five dialects rake their pylons and
    # carry the ring back with them; this one was given no rake at all, so the
    # term is left out instead of written as a multiplication by nothing.
    ring_y = -0.07 * Z

    # ---- the head ------------------------------------------------------------
    #
    # It hangs off the front of the ring, or off the core when the class has a
    # neck, and it is the only thing forward of the ring.
    head_len = HEAD_LEN[plan["head"]] * Z
    if plan["head"] == "spade":
        head_geo = prism(1.00 * Z, 0.22 * Z, head_len, 0.45, 0.80)
    elif plan["head"] == "lance":
        # Blunter at the point than the page drew it. The page tapered a lance
        # to fifteen percent, and the last three pixels of that point are
        # narrower than one pixel at the identification size, so the tip came
        # away as a blob of its own on both classes that carry a lance. Section
        # 2.1 asks for a thicker piece rather than a note, and a lance nearly
        # five times as long as it is wide still reads as a needle beside a
        # spade.
        head_geo = prism(0.36 * Z, 0.22 * Z, head_len, 0.45, 1.00)
    else:
        head_geo = prism(0.50 * Z, 0.26 * Z, head_len, 0.35, 1.00)
    head_z = (rz + (0.9 * k_spine if cls["neck"] else 0.3 * Z)
              + (head_len - 1.2 * Z) * 0.5)

    def on_head(g):
        """Put a shape into the head's frame, tip and all."""
        return g.rotate_x(-0.10).translate(0.0, 0.06 * Z, head_z)

    h.part(on_head(head_geo), "head", HEAD_NAME[plan["head"]], (0.0, 0.0, 1.0))
    h.part(on_head(collector(0.06 * Z).translate(0.0, 0.0, head_len * 0.5 - 0.02 * Z)),
           "glow", "the one warm eye", (0.0, 0.0, 1.0), glow=True)
    if plan["head"] == "spade":
        # Inboard of where the page hung them: the kit's prism tapers all the
        # way from stern to bow where the page's kept a full width rib at the
        # middle, so a barrel on the old shoulder line would have floated.
        for side in (-1.0, 1.0):
            h.part(on_head(cannon(0.6 * Z, 0.035 * Z)
                           .translate(side * 0.32 * Z, 0.0, head_len * 0.3)),
                   "greeble",
                   ("port" if side < 0 else "starboard") + " spade cannon",
                   (side * 0.3, 0.0, 1.0))
    if cls.get("cranes"):
        for side in (-1.0, 1.0):
            h.part(crane(0.9 * Z).rotate_y(side * 0.45)
                   .translate(side * 0.28 * Z, -0.05 * Z, head_z - 0.2 * Z),
                   "greeble", ("port" if side < 0 else "starboard") + " crane",
                   (side, 0.0, 1.0))

    # ---- the core ------------------------------------------------------------
    #
    # A plain beam bridging beak to ring, on the classes that have a neck. It is
    # what makes a cruiser longer than a frigate without the ring growing.
    if cls["neck"]:
        core_len = 1.1 * k_spine + 0.6 * Z
        h.part(box(0.62 * Z, 0.34 * Z, core_len)
               .translate(0.0, 0.02 * Z, rz - 0.15 * Z + 0.3 * k_spine),
               "body", "core, bridging beak to loop", (0.0, 1.0, 0.0))

    # ---- the loop ------------------------------------------------------------

    def add_loop(name, geo, rad_at, inner_at, spikes):
        """Place a ring and everything that rides on it.

        `rad_at` and `inner_at` give the outer and inner edge at an angle, so
        the same code dresses a crescent, an ellipse and an egg.
        """
        h.part(geo.translate(0.0, ring_y, 0.0), "ring", name, (0.0, -1.0, -0.2))
        if cls.get("bays"):
            # Every eighth of the ring but the bow, which is kept clear for
            # the head. The mouths face into the hole rather than out of it, so
            # a carrier launches through its own middle.
            for deg in range(45, 360, 45):
                a = math.radians(deg)
                if _in_gap(a, gap):
                    continue
                rm = (rad_at(a) + inner_at(a)) * 0.5
                h.part(bay_housing(0.22 * Z, 0.14 * Z, 0.30 * Z)
                       .rotate_y(a + math.pi)
                       .translate(math.sin(a) * rm, ring_y + 0.12 * Z,
                                  math.cos(a) * rm),
                       "bay", "bay at %d degrees" % deg,
                       (math.sin(a), 0.3, math.cos(a)))
        for deg in spikes:
            a = math.radians(deg)
            if _in_gap(a, gap):
                continue
            # Rooted at 97 percent of the outer edge, so the base is buried in
            # the ring and only the point is outside it.
            rr = rad_at(a) * 0.97
            h.part(spike(0.5 * Z, 0.05 * Z).rotate_y(a)
                   .translate(math.sin(a) * rr, ring_y, math.cos(a) * rr),
                   "greeble", "spike at %d degrees" % int(deg),
                   (math.sin(a), 0.0, math.cos(a)))

    if plan["loop"] == "horseshoe":
        crescent = plan["gap"] >= 150
        geo = horseshoe(ring_r, hole_r, thick, plan["gap"], RING_SEGS).scale(sx, 1.0, sz)
        add_loop("the crescent, half an arc" if crescent else "the loop, open aft",
                 geo,
                 lambda a: _ellipse_r(a, rx, rz),
                 lambda a: _ellipse_r(a, hole_x, hole_z),
                 CRESCENT_SPIKES if crescent else SPIKES)
    elif plan["loop"] == "egg":
        geo = egg(ring_r, hole_r, thick, RING_SEGS).scale(sx, 1.0, sz)
        add_loop("the loop, fuller aft", geo,
                 lambda a: _ellipse_r(a, rx, rz) * _egg_k(a),
                 lambda a: _ellipse_r(a, hole_x, hole_z) * _egg_k(a),
                 SPIKES)
    else:
        geo = annulus(ring_r, hole_r, thick, RING_SEGS).scale(sx, 1.0, sz)
        add_loop("the loop, feather banded underneath", geo,
                 lambda a: _ellipse_r(a, rx, rz),
                 lambda a: _ellipse_r(a, hole_x, hole_z),
                 SPIKES)

    if plan["loop"] == "concentric":
        # A second ring inside the first and raised above its plane. It hangs on
        # the drives rather than on the outer ring, which is why its rim reaches
        # out to where they stand.
        h.part(annulus(hole_r * 0.82, hole_r * 0.5, 0.10 * Z)
               .scale(sx, 1.0, sz).translate(0.0, 0.12 * Z, 0.0),
               "ring", "inner loop, raised", (0.0, 1.0, 0.0))

    if plan["loop"] == "wheel":
        # Two spokes across the hole and a hub where they cross. Each spoke runs
        # a little past the hole's edge so its ends are buried in the ring.
        for (w, d, name) in ((hole_x * 2.04, 0.16 * Z, "athwartships spoke"),
                             (0.16 * Z, hole_z * 2.04, "fore and aft spoke")):
            h.part(box(w, 0.10 * Z, d).translate(0.0, -0.02 * Z, 0.0),
                   "pylon", name, (0.0, 1.0, 0.0))
        # Slightly wider at the bottom than the top, the way the page drew it, so
        # the hub reads as seated on the spokes rather than balanced on them.
        h.part(lathe([(0.0, -0.10 * Z), (0.34 * Z, -0.10 * Z),
                      (0.30 * Z, 0.10 * Z), (0.0, 0.10 * Z)], 10)
               .translate(0.0, 0.03 * Z, 0.0),
               "body", "hub", (0.0, 1.0, 0.0))
        h.part(dome(0.12 * Z).translate(0.0, 0.11 * Z, 0.0),
               "greeble", "hub dome", (0.0, 1.0, 0.0))

    # ---- the cargo variants ---------------------------------------------------
    if cls.get("cargo"):
        # Two rails fore and aft across the hole with their ends buried in the
        # ring, and the containers hung between them. Without the rails the load
        # is eight boxes floating in the hole, which is exactly the failure
        # CLAUDE.md 2.1 counts.
        for side in (-1.0, 1.0):
            h.part(box(0.07 * Z, 0.07 * Z, hole_z * 2.08)
                   .translate(side * hole_x * 0.45, ring_y, 0.0),
                   "truss", ("port" if side < 0 else "starboard") + " cargo rail",
                   (side, -0.5, 0.0))
        # A container wider than the page's, so its outboard face reaches its
        # rail instead of stopping a texel short of it.
        cargo_run(h, cls["cargo"], -hole_z * 0.6, hole_z * 0.6, -0.12 * Z,
                  0.50 * Z, 0.36 * Z, 0.45 * Z)

    # ---- the drives -----------------------------------------------------------
    #
    # Standing inside the ring, which is the one thing about this dialect a
    # player has to be able to read at a glance: a Vaelith ship carries its
    # engines in the hole, not on pylons outboard.
    drive_x = hole_x - 0.22 * Z
    pod_len = 1.6 * cls.get("pod_len", 1.0) * Z
    rows = ((0.12, "lower "), (0.50, "upper ")) if cls["pods"] == 4 \
        else ((0.12, ""),)
    for tier, (dy, label) in enumerate(rows):

        def make_drive(side, _dy=dy):
            return pod(pod_len, 0.15 * Z, side).translate(
                side * drive_x, _dy * Z, 0.0)

        h.pair(make_drive, "pod", label + "drive, inside the loop",
               (0.4, 0.8, 0.0), inner=True)
        for side in (-1.0, 1.0):
            prefix = "port " if side < 0 else "starboard "
            h.part(collector(0.12 * Z).translate(
                       side * drive_x, dy * Z, pod_len * 0.5 - 0.02 * Z),
                   "glow", prefix + label + "collector", (side, 0.0, 1.0),
                   glow=True)
            if tier == 0:
                # A short beam outboard into the ring wall. It reaches down into
                # the ring's own thickness rather than resting on its top face,
                # because a joint that only touches is a joint that shows a seam
                # of sky through it from a low camera.
                h.part(box(0.34 * Z, 0.16 * Z, 0.30 * Z)
                       .translate(side * (drive_x + 0.25 * Z),
                                  dy * Z - 0.06 * Z, 0.0),
                       "pylon", prefix + "strut, drive to the loop",
                       (side, 0.5, 0.0))
            else:
                # The upper drive stands on a post off the lower one, so the two
                # tiers are a stack inside the hole and not a floating pair.
                h.part(box(0.08 * Z, dy * Z + 0.10 * Z, 0.30 * Z)
                       .translate(side * (drive_x + 0.12 * Z),
                                  dy * Z * 0.5 - 0.05 * Z, 0.0),
                       "pylon", prefix + "post, upper drive",
                       (side, 0.5, 0.0))
    return h
