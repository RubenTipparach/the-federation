#!/usr/bin/env python3
"""The Kthaari Dominion: a narrow armoured head on a thin boom, a body deepest
aft, wings swept back with pods at their tips and a disruptor under each
(docs/17 section 8.4).

ONE GRAMMAR, TEN PLANS.

Head, boom, wings and tip pods are constant. What changes with class is the
SHAPE of each, and that is the whole job of `KTH_PLAN`: a fleet where every
hull is the same bird at a different size reads as one ship rather than as a
family, so the plan varies the head, the body, the wing outline, how many pairs
of wings are carried and how far they are tilted. The battleship crosses its
two pairs into an X, which is the one hull of the ten a player can name from
the silhouette alone.

Most of that difference lives in the wing, which is why the plans are kept as
OUTLINES rather than as one swept box with parameters. A cranked wing and a
gull wing are different shapes at sixty pixels, and a shape is all a tactical
hull has; a swept box with a sweep angle would have given ten of the same wing.

PORTED FROM THE DIORAMA PAGE under the kit's three rules. The bow is +Z here
and -Z there, so every z read from that source is negated, and it is negated
once at the point it is read rather than twice somewhere downstream. Winding is
computed at emit, so nothing here passes a normal. And the JavaScript's
`frontScale` is this kit's `prism(..., fore)` once the negation is done,
because after it both names the bow end.
"""

import math

from shipkit import Geo, Hull, box, prism, sphere
from fleet.parts import (HALF_PI, bay_housing, cannon, cargo_run, collector,
                         crane, dome, drive_drum, pod, spike)

## The Kthaari rake, from the diorama's faction table. It reaches only the
## sweep of a wing here: this dialect rakes with tilt instead, which is what
## puts the pods below the plane on the ships whose plan asks for it.
RAKE = 0.10

## The plan table, keyed by class id exactly as the source keeps it. Read a row
## as a sentence: a frigate is a narrow head on nothing, wearing one swept pair
## tilted down; a dreadnought is a bulb on an oval body under two delta pairs.
KTH_PLAN = {
    "frigate":       dict(head="narrow", body="none",  wing="swept",    pairs=1, tilt=-0.30),
    "destroyer":     dict(head="hammer", body="box",   wing="cranked",  pairs=1, tilt=-0.20),
    "light_cruiser": dict(head="narrow", body="box",   wing="swept",    pairs=1, tilt=-0.25),
    "heavy_cruiser": dict(head="bulb",   body="oval",  wing="gull",     pairs=1, tilt=0.30),
    "battlecruiser": dict(head="beak",   body="wedge", wing="forward",  pairs=1, tilt=-0.15),
    "battleship":    dict(head="hammer", body="box",   wing="swept",    pairs=2, tilt=-0.30, x=True),
    "dreadnought":   dict(head="bulb",   body="oval",  wing="delta",    pairs=2, tilt=-0.10),
    "carrier":       dict(head="hammer", body="slab",  wing="straight", pairs=1, tilt=0.0),
    "freighter":     dict(head="narrow", body="box",   wing="stub",     pairs=1, tilt=0.0),
    "tender":        dict(head="beak",   body="oval",  wing="cranked",  pairs=1, tilt=0.15),
}


def kth_wing_plan(kind, root, span, sweep):
    """A wing outline in the XZ plane for the STARBOARD side, and its tip.

    `x` runs outboard from the root, `z` toward the bow, and the outline is
    closed: it ends at the tip, where the pod goes. The z of every point is
    negated on the way out, which is this port's one rule applied in one place,
    so the numbers below still read line for line against `kthWingPlan` on the
    diorama page.
    """
    s, r, w = span, root, sweep
    plans = {
        "swept":    ([(r, -0.3), (r * 0.7, 0.5), (s, w), (s + 0.15, w - 0.35)],
                     (s + 0.07, w - 0.05)),
        "forward":  ([(r, 0.6), (r * 0.7, -0.2), (s, -w * 0.7), (s + 0.15, -w * 0.7 + 0.35)],
                     (s + 0.07, -w * 0.7 + 0.1)),
        "straight": ([(r, -0.55), (r, 0.55), (s, 0.45), (s + 0.1, -0.35)],
                     (s + 0.05, 0.05)),
        "cranked":  ([(r, -0.3), (r * 0.7, 0.45), (s * 0.55, 0.55), (s, w),
                      (s + 0.15, w - 0.35), (s * 0.55, -0.05)],
                     (s + 0.07, w - 0.05)),
        "gull":     ([(r, -0.35), (r * 0.7, 0.4), (s * 0.5, 0.75), (s, w * 0.9),
                      (s + 0.15, w * 0.9 - 0.35), (s * 0.5, 0.15)],
                     (s + 0.07, w * 0.9 - 0.05)),
        "delta":    ([(r, -0.7), (r * 0.6, 0.9), (s + 0.1, 0.9), (s, 0.4)],
                     (s + 0.05, 0.65)),
        "stub":     ([(r, -0.35), (r, 0.35), (s * 0.6, 0.3), (s * 0.6, -0.25)],
                     (s * 0.6 + 0.05, 0.02)),
    }
    pts, tip = plans[kind]
    return [(x, -z) for (x, z) in pts], (tip[0], -tip[1])


def chord_mid(pts, x):
    """The middle of the z range a wing outline covers at station `x`.

    Anything placed by this lands ON the wing whatever the plan, which is what
    lets one line dress a delta and a gull without knowing which it has. None
    where the outline does not reach that far outboard.
    """
    zs = []
    n = len(pts)
    for i in range(n):
        x0, z0 = pts[i]
        x1, z1 = pts[(i + 1) % n]
        if (x0 <= x < x1) or (x1 <= x < x0):
            zs.append(z0 + (z1 - z0) * (x - x0) / (x1 - x0))
    return (min(zs) + max(zs)) * 0.5 if zs else None


# ------------------------------------------------------------- the one shape
# the kit does not have yet. `shipkit.extrude` fans its cap from the first
# vertex, which is correct for a convex plate and wrong for the cranked and the
# gull plans: a fan thrown across a notch lays triangles outside the wing, so
# the outline the dialect is built on would be the one thing drawn wrong. The
# cap is eared here instead. Lift this into the kit when a second dialect wants
# a concave plate; until then it stays private rather than standing beside
# `extrude` as a second way to do the same thing (CLAUDE.md 4.1).

def _area2(pts):
    """Twice the signed area of a closed (x, z) outline."""
    n = len(pts)
    return sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1]
               for i in range(n))


def _in_tri(p, a, b, c):
    def side(u, v):
        return (v[0] - u[0]) * (p[1] - u[1]) - (v[1] - u[1]) * (p[0] - u[0])
    return side(a, b) >= 0.0 and side(b, c) >= 0.0 and side(c, a) >= 0.0


def _ears(pts):
    """Triangulate a simple outline given counter clockwise in (x, z)."""
    live = list(range(len(pts)))
    out = []
    guard = len(pts) * len(pts) + 8
    while len(live) > 3 and guard > 0:
        guard -= 1
        for k in range(len(live)):
            a, b, c = live[k - 1], live[k], live[(k + 1) % len(live)]
            pa, pb, pc = pts[a], pts[b], pts[c]
            if (pb[0] - pa[0]) * (pc[1] - pa[1]) - (pb[1] - pa[1]) * (pc[0] - pa[0]) <= 0.0:
                continue                       # a reflex corner is not an ear
            if any(_in_tri(pts[i], pa, pb, pc) for i in live
                   if i not in (a, b, c)):
                continue                       # something else is standing in it
            out.append((a, b, c))
            live.pop(k)
            break
        else:
            break
    if len(live) == 3:
        out.append(tuple(live))
    return out


def _plate(points, thick):
    """Extrude a closed (x, z) outline upward by `thick`, concave ones too."""
    pts = list(points)
    if _area2(pts) < 0.0:
        pts.reverse()                          # the ear clipper wants one hand
    n = len(pts)
    g = Geo()
    for (x, z) in pts:
        g.verts.append((x, thick * 0.5, z))
    for (x, z) in pts:
        g.verts.append((x, -thick * 0.5, z))
    for (a, b, c) in _ears(pts):
        g.tris.append((a, c, b))               # the top, facing +Y
        g.tris.append((n + a, n + b, n + c))   # and the underside
    for i in range(n):
        j = (i + 1) % n
        g.tris.append((i, j, n + j))
        g.tris.append((i, n + j, n + i))
    return g


# --------------------------------------------------------------- the builder

def build(cls):
    h = Hull("kthaari", cls["id"])
    Z = cls["size"]
    k_disc = cls["disc"] * Z if "disc" in cls else Z
    k_spine = cls["spine"] * Z
    plan = KTH_PLAN.get(cls["id"], KTH_PLAN["light_cruiser"])
    cargo = cls.get("cargo", 0)

    body_kind = plan["body"]
    head_kind = plan["head"]
    # The body is the only part whose LENGTH carries class here; everything
    # else grows with `size`. A doubled body on the ladder means a quarter more
    # of it rather than a second one, because a Kthaari has one spine.
    L = 0.0 if body_kind == "none" else 1.7 * Z * (1.25 if cls["body"] == 2 else 1.0)
    boom_len = 1.6 * k_spine
    boom_w, boom_h, boom_y = 0.3 * Z, 0.26 * Z, 0.05 * Z
    boom_z = L * 0.5 + boom_len * 0.5
    head_len = {"hammer": 0.6, "bulb": 1.1, "beak": 1.2}.get(head_kind, 0.9) * Z
    head_y = 0.1 * Z
    # the source's own 0.08 sinks the head onto the boom instead of butting it,
    # which is the difference between one piece and two (CLAUDE.md 2.1)
    head_z = L * 0.5 + boom_len + head_len * 0.5 - 0.08 * Z

    # ---- the head ------------------------------------------------------------
    head_w, head_h = 0.72 * Z, 0.36 * Z
    if head_kind == "hammer":
        head_w, head_h = 1.3 * Z, 0.24 * Z
        head_geo = prism(head_w, head_h, 0.6 * Z, 0.8, 1.0)
    elif head_kind == "bulb":
        head_w, head_h = 0.8 * Z, 0.5 * Z
        head_geo = sphere(1.0, 12, 8).scale(head_w * 0.5, head_h * 0.5, 0.55 * Z)
    elif head_kind == "beak":
        head_geo = prism(0.6 * Z, 0.3 * Z, 1.2 * Z, 0.3, 1.0)
    else:
        head_geo = prism(head_w, head_h, 0.9 * Z, 0.55, 1.0)
    h.part(head_geo.translate(0.0, head_y, head_z), "head",
           head_kind + " head, armoured", (0.0, 0.0, 1.0))
    # The spikes are the one head greeble every class keeps: they are what the
    # bow looks like from above, and a Kthaari is recognised head first.
    for sx in (-1.0, 1.0):
        h.part(spike(0.35 * Z, 0.03)
               .translate(sx * head_w * 0.18, head_y + 0.04 * Z,
                          head_z + head_len * 0.5 + 0.12 * Z),
               "greeble", ("port" if sx < 0 else "starboard") + " head spike",
               (sx * 0.3, 0.0, 1.0))
    if head_kind == "hammer":
        for sx in (-1.0, 1.0):
            h.part(cannon(0.5 * Z, 0.04)
                   .translate(sx * head_w * 0.42, head_y, head_z + 0.5 * Z),
                   "greeble",
                   ("port" if sx < 0 else "starboard") + " cheek disruptor",
                   (sx * 0.4, 0.0, 1.0))

    # ---- the boom ------------------------------------------------------------
    # Thin on purpose. The gap between head and body IS the dialect, so the
    # boom is drawn as narrow as the silhouette check of section 2.1 allows
    # rather than as narrow as it looks good from a metre away.
    #
    # It is also drawn a bite longer than the source makes it, and that bite is
    # spent inside the body. The source lets the two meet on exactly one plane
    # at z = L / 2, which is one piece by arithmetic and two by any measurement
    # of it: the box body classes came apart under `Hull.attachment` with no
    # tolerance to lean on. The source already spends 0.08 this way at the bow
    # end of the boom, so this is that number spent again at the other end.
    embed = 0.08 * Z if body_kind != "none" else 0.0
    h.part(box(boom_w, boom_h, boom_len + embed)
           .translate(0.0, boom_y, boom_z - embed * 0.5),
           "pylon", "boom, thin between head and body", (0.0, 1.0, 0.0))

    if cls.get("cranes"):
        for sx in (-1.0, 1.0):
            h.part(crane(0.9 * Z).rotate_y(sx * 0.5)
                   .translate(sx * 0.3 * Z, -0.05 * Z, head_z + 0.2 * Z),
                   "greeble", ("port" if sx < 0 else "starboard") + " crane",
                   (sx, 0.0, 1.0))

    # ---- the body, and where the wings root on it ----------------------------
    wing_z = boom_z - boom_len * 0.3
    wing_y = -0.15 * Z
    wing_root_x = 0.16 * Z
    if body_kind != "none":
        bw, bh = 1.1 * Z, 0.5 * Z
        name = "body, deepest aft"
        if body_kind == "oval":
            bw, bh = 1.2 * Z, 0.7 * Z
            body_geo = sphere(1.0, 14, 10).scale(bw * 0.5, bh * 0.5, L * 0.55)
            name = "oval body"
        elif body_kind == "wedge":
            bw, bh = 1.4 * Z, 0.4 * Z
            body_geo = prism(bw, bh, L * 1.15, 0.3, 1.0)
            name = "wedge body"
        elif body_kind == "slab":
            bw, bh = 1.9 * Z, 0.34 * Z
            body_geo = prism(bw, bh, L, 0.8, 1.0)
            name = "slab body, bay lined"
        else:
            body_geo = prism(bw, bh, L, 0.85, 1.0)
        h.part(body_geo, "body", name, (0.0, -1.0, 0.0))

        # How much of its full section the body still has at a station along z,
        # per shape, so a drive sits on the oval rather than on the box the
        # oval fits in. The taper is on the bow half, which is +z here.
        fore = {"wedge": 0.3, "slab": 0.8, "box": 0.85}.get(body_kind, 1.0)

        def taper(z):
            if body_kind == "oval":
                t = z / (L * 0.55)
                return math.sqrt(max(0.0, 1.0 - t * t))
            if z <= 0.0:
                return 1.0
            reach = L * (0.575 if body_kind == "wedge" else 0.5)
            return 1.0 - (1.0 - fore) * min(1.0, z / reach)

        def top_at(z):
            return bh * 0.5 * taper(z)

        def half_w(z):
            return bw * 0.5 * taper(z)

        n_ex = 3 if body_kind == "slab" else 2
        ex_z = -L * 0.5 * (0.88 if body_kind == "oval" else 1.0)
        for i in range(n_ex):
            h.part(drive_drum(0.1 * Z, 0.12)
                   .translate((i - (n_ex - 1) * 0.5) * half_w(ex_z) * 0.6,
                              0.0, ex_z),
                   "glow", "drive %d" % (i + 1), (0.0, 0.0, -1.0), glow=True)
        h.part(dome(0.12 * Z).translate(0.0, top_at(L * 0.12) - 0.02, L * 0.12),
               "greeble", "bridge dome", (0.0, 1.0, 0.0))
        if cls["body"] == 2:
            # aft of centre, where the body is deepest, so the doubled hull of
            # the ladder reads as a ship that grew a back rather than a nose
            h.part(prism(0.7 * Z, 0.3 * Z, L * 0.6, 0.8, 1.0)
                   .translate(0.0, top_at(-L * 0.1) + 0.1 * Z, -L * 0.1),
                   "body", "dorsal hull", (0.0, 1.0, 0.0))
        if cls.get("bays"):
            for sx in (-1.0, 1.0):
                for i in range(4):
                    bz = L * 0.3 - i * L * 0.2
                    h.part(bay_housing(0.2 * Z, 0.14 * Z, 0.26 * Z)
                           .rotate_y(-sx * HALF_PI)
                           .translate(sx * half_w(bz) * 0.96, -0.06 * Z, bz),
                           "bay",
                           "%s bay %d" % ("port" if sx < 0 else "starboard", i + 1),
                           (sx, 0.0, 0.0))
        wing_z = L * 0.1
        wing_root_x = half_w(L * 0.1) * 0.9

    # ---- the cargo variants ---------------------------------------------------
    if cargo:
        # The source slings the containers clear of the boom, which reads well
        # at a metre and is two pieces by the measure of section 2.1. They are
        # raised here until the top of a container is a texel inside the boom's
        # underside, which is the smallest change that makes the hull one piece.
        cargo_y = boom_y - boom_h * 0.5 - 0.13 * Z
        cargo_run(h, cargo, boom_z + boom_len * 0.3, boom_z - boom_len * 0.3,
                  cargo_y, 0.34 * Z, 0.3 * Z, 0.4 * Z)

    # ---- the wings, and the pods at their tips --------------------------------
    span = (1.35 + 0.3 * k_disc) * Z
    sweep = (1.15 + 0.5 * RAKE) * Z
    outline, tip = kth_wing_plan(plan["wing"], wing_root_x, span, sweep)
    pairs = plan["pairs"]
    crossed = bool(plan.get("x"))
    pod_len = 1.4 * Z * cls.get("pod_len", 1.0)
    pod_r = 0.17 * Z

    for pi in range(pairs):
        # A second pair is stacked above the first, or crossed through it when
        # the plan says X, which is the battleship and only the battleship.
        tilt = plan["tilt"] * (-1.0 if (crossed and pi) else 1.0)
        y0 = wing_y + ((-0.12 if crossed else 0.5) * Z if pi else 0.0)
        # The wing turns about its own origin, so its root climbs by
        # root * sin(tilt); py takes that back out and puts the root on the hull.
        py = y0 + wing_root_x * math.sin(tilt)
        pz = wing_z - (0.25 * Z if pi else 0.0)
        tier = ""
        if pairs > 1:
            tier = ("upper ", "lower ")[pi] if crossed else ("lower ", "upper ")[pi]
        pts = [(x, z * Z) for (x, z) in outline]
        tip_x, tip_z = tip[0], tip[1] * Z

        def make_wing(side, _p=pts, _t=tilt, _y=py, _z=pz):
            g = _plate(_p, 0.12 * Z)
            if side < 0:
                g.scale(-1.0, 1.0, 1.0)
            return g.rotate_z(-side * _t).translate(0.0, _y, _z)

        h.pair(make_wing, "wing", tier + plan["wing"] + " wing", (1.0, -0.3, -0.4))

        def make_ridge(side, _p=pts, _t=tilt, _y=py, _z=pz, _tx=tip_x):
            # Three armour stations down the wing, seated by `chord_mid` so
            # they land on the wing whatever its plan. One part rather than
            # three, because the wreck throws a wing's armour with the wing.
            g = Geo()
            flank = [(side * x, z) for (x, z) in _p]
            x0 = flank[0][0]
            for t in (0.3, 0.55, 0.8):
                ax = x0 + t * (side * _tx - x0)
                az = chord_mid(flank, ax)
                if az is None:
                    continue
                g.add(box(0.16 * Z, 0.04, 0.28 * Z)
                      .translate(ax, 0.06 * Z + 0.015, az))
            return g.rotate_z(-side * _t).translate(0.0, _y, _z)

        h.pair(make_ridge, "greeble", tier + "wing ridge", (1.0, 0.4, 0.0))

        px = tip_x * math.cos(tilt)
        pod_y = py - abs(tip_x) * math.sin(tilt) - 0.15 * Z
        pod_z = pz + tip_z - 0.3 * Z

        def make_pod(side, _x=px, _y=pod_y, _z=pod_z):
            return pod(pod_len, pod_r, side).translate(side * _x, _y, _z)

        h.pair(make_pod, "pod", tier + "tip pod", (1.0, -0.4, -0.5), inner=True)
        for side in (-1.0, 1.0):
            label = ("port " if side < 0 else "starboard ") + tier
            h.part(collector(pod_r * 0.8)
                   .translate(side * px, pod_y, pod_z + pod_len * 0.5 - 0.01),
                   "glow", label + "collector", (side, 0.0, 1.0), glow=True)
            # The disruptor reaches out past the pod's bow: it is the longest
            # thing on the ship from above and it is what says which way a
            # Kthaari is pointing before the head does.
            h.part(cannon(1.0 * Z, 0.045)
                   .translate(side * px, pod_y - 0.05 * Z, pod_z + 1.15 * Z),
                   "greeble", label + "disruptor", (side * 0.3, 0.0, 1.0))
    return h
