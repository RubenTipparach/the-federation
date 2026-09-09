#!/usr/bin/env python3
"""The Sarn Concordance: a faceted amber body with its bay mouths in rows, and
a ring aft for the tractor web with the drives standing on it (docs/17).

THE CIRCLE IS THE SILHOUETTE. Everything else in the grammar exists to make
that circle readable at sixty pixels. The body is a solid of revolution with
few enough facets to count, the prow is one piece on the centreline, and a pair
of struts runs from inside the hull out to the ring, because a hoop that only
looks attached reads as a second ship flying in close formation. There are no
pods and no wings in this dialect: the drives stand on the ring itself, which
is what makes the circle structural rather than decorative.

CLASS IS THE BODY AND THE RING TOGETHER, which is why the plan below is a table
and not a few multipliers. A cut diamond, a many faceted hull, a long spindle,
a wide flat diamond, a twenty sided gem or two of them stacked; a ring aft, a
belt round the waist, an arch over the stern, both at once, or twice. A frigate
and a dreadnought therefore differ in OUTLINE and not only in size, which is
the thing two earlier cuts of this fleet got wrong.

Ported from `buildSarn` on the diorama page, so the shape a reviewer approved
is the shape the game flies. That page draws its bow at -Z and the game flies
toward +Z, so every z read from it is negated once, at the point it is read,
and rotations about X and Y are negated with it. Rotations about Z survive
unchanged, because negating z commutes with them.
"""

import math

from shipkit import Hull, box, cone, facets, prism, torus
from fleet.parts import (HALF_PI, bay_housing, bowl, cargo_run, crane,
                         drive_drum, fin, spike)

## The Sarn rake, from the diorama's faction table. It reaches one thing here,
## the standoff between the body's tail and the ring, which is why the ring
## sits a little further aft than the hull ends rather than round its stern.
RAKE = 0.20

## One grammar, ten plans, keyed by class id the way the source keys it so the
## two tables can be read side by side. `body` is which faceted solid, `ring`
## where the tractor web is carried, `prow` what is on the point, and w/h/l
## stretch the body across, up and fore and aft.
SARN_PLAN = {
    "frigate":       dict(body="diamond", ring="aft",      prow="cone",    w=1.00, h=1.00, l=1.00),
    "destroyer":     dict(body="flat",    ring="arch",     prow="blade",   w=1.50, h=0.60, l=1.00),
    "light_cruiser": dict(body="facet",   ring="aft",      prow="cone",    w=1.00, h=1.00, l=1.00),
    "heavy_cruiser": dict(body="spindle", ring="belt",     prow="cone",    w=0.85, h=1.00, l=1.30),
    "battlecruiser": dict(body="gem",     ring="aft",      prow="trident", w=1.10, h=1.10, l=1.10),
    "battleship":    dict(body="double",  ring="double",   prow="blade",   w=1.10, h=1.00, l=1.10),
    "dreadnought":   dict(body="spindle", ring="belt+aft", prow="trident", w=1.00, h=1.10, l=1.35),
    "carrier":       dict(body="flat",    ring="aft",      prow="blade",   w=1.60, h=0.70, l=1.10),
    "freighter":     dict(body="spindle", ring="aft",      prow="cone",    w=0.80, h=0.90, l=1.40),
    "tender":        dict(body="gem",     ring="arch",     prow="cone",    w=0.90, h=0.90, l=0.90),
}

## Which of the kit's three faceted solids each plan asks for. Six plan words
## share three shapes because the plan also carries w/h/l: a spindle and a flat
## diamond are the same eight facets stretched the opposite way, and saying so
## here is cheaper than eight more entries in `shipkit.facets`.
BODY_KIND = {"diamond": "diamond", "gem": "gem", "facet": "facet",
             "spindle": "facet", "flat": "facet", "double": "facet"}

## What the ship systems display and the wreck call each body.
BODY_NAME = {"diamond": "cut diamond body", "gem": "twenty sided body",
             "spindle": "spindle body", "flat": "flat diamond body, bays in rows",
             "double": "lower body", "facet": "faceted body, bays in rows"}

## Where the drives stand on the host ring, in degrees from starboard, and what
## each one is called. Two classes carry four, and the second pair goes on the
## quarters rather than above the first, because this dialect stacks nothing.
DRIVE_SEAT = {0: "starboard", 180: "port", 60: "starboard quarter",
              120: "port quarter"}


def _along(path, t):
    """The point `t` of the way along a polyline, measured by length.

    Bay rows and dorsal spikes are spread over a body whose proportions change
    with every class, so they are placed by walking the hull's own outline. A
    z coordinate instead, which is what the source used, falls off the end of a
    short hull and sinks into the middle of a long one.
    """
    segs = [math.hypot(path[i + 1][0] - path[i][0], path[i + 1][1] - path[i][1])
            for i in range(len(path) - 1)]
    want = max(0.0, min(1.0, t)) * sum(segs)
    for i, s in enumerate(segs):
        if want <= s or i == len(segs) - 1:
            f = want / s if s > 1e-12 else 0.0
            return (path[i][0] + (path[i + 1][0] - path[i][0]) * f,
                    path[i][1] + (path[i + 1][1] - path[i][1]) * f)
        want -= s
    return path[-1]


def _meridian(unit):
    """The body's half profile as (y, radius) pairs, read back off the mesh.

    `shipkit.facets` decides how many facets a diamond, a hull and a gem have
    and where a gem's girdle sits. Restating those numbers here would be a
    second place for them to change (CLAUDE.md 4.1), so everything mounted on a
    Sarn hull measures the solid it is being mounted on.
    """
    top = {}
    for (x, y, z) in unit.verts:
        k = round(y, 9)
        top[k] = max(top.get(k, 0.0), math.hypot(x, z))
    return sorted(top.items())


def _waist(unit, bw, bl):
    """The starboard half of the body's widest outline, bow first, as (x, z).

    The waist is a polygon and not an ellipse. A mount placed on the ellipse
    through its vertices would stop short of the hull anywhere along a flat and
    hang a texel off it, which is exactly the detachment section 2.1 counts.
    """
    pts = [(v[0], v[2]) for v in unit.verts
           if abs(v[1]) < 1e-9 and v[0] > -1e-9]
    pts.sort(key=lambda p: math.atan2(p[0], p[1]))
    return [(x * bw, z * bl) for (x, z) in pts]


def _ridge(mer, bh, bl):
    """The body's top line, bow tip over the apex to stern tip, as (z, y)."""
    fore = [(r * bl, y * bh) for (y, r) in mer if y > -1e-9]
    return fore + [(-z, y) for (z, y) in reversed(fore[:-1])]


def _girth(mer, ty):
    """How much of its waist the body still has at height `ty` of its own half.

    A solid of revolution has the same outline at every height, scaled by this,
    so the carrier's lower row of bays follows the hull down rather than being
    inset by a guess the way the source inset it.
    """
    for i in range(len(mer) - 1):
        (y0, r0), (y1, r1) = mer[i], mer[i + 1]
        if y0 - 1e-9 <= ty <= y1 + 1e-9:
            f = 0.0 if y1 - y0 < 1e-12 else (ty - y0) / (y1 - y0)
            return r0 + (r1 - r0) * f
    return 0.0


def build(cls):
    """cls is a row of shipkit.CLASSES. Returns a shipkit.Hull."""
    h = Hull("sarn", cls["id"])
    Z = cls["size"]
    k_disc = cls["disc"] * Z if "disc" in cls else Z
    k_spine = cls["spine"] * Z
    plan = SARN_PLAN.get(cls["id"], SARN_PLAN["light_cruiser"])

    # ---- the body ------------------------------------------------------------
    #
    # One faceted solid, stretched by the plan. The unit shape is kept whole so
    # that the mounts below can read their seats off it before it is scaled.
    bl = 1.8 * k_spine * plan["l"]
    bw = 1.0 * k_disc * plan["w"]
    bh = 0.36 * Z * plan["h"]
    body_z = 0.2 * Z

    unit = facets(1.0, BODY_KIND[plan["body"]])
    mer = _meridian(unit)
    waist = _waist(unit, bw, bl)
    ridge = _ridge(mer, bh, bl)

    body = unit.copy().scale(bw, bh, bl).translate(0.0, 0.0, body_z)
    h.part(body, "body", BODY_NAME[plan["body"]], (0.0, 0.0, 1.0))

    # The dorsal spikes, walked along the hull's own top line so they follow a
    # flat diamond's low ridge and a spindle's long one without a second table.
    for i in range(6):
        rz, ry = _along(ridge, 0.22 + 0.56 * i / 5.0)
        h.part(cone(0.07 * Z, 0.18 * Z, 4)
               .translate(0.0, ry + 0.05 * Z, body_z + rz),
               "greeble", "dorsal spike %d" % (i + 1), (0.0, 1.0, 0.0))

    def bay_row(count, t0, t1, ty, dims, tag):
        """A row of bay mouths down each flank, seated on the waist outline.

        The mouths turn OUTBOARD. The source turned them inboard, where the one
        thing a bay is for, a lit opening a player can see launching, faces its
        own hull; that is paint rather than shape, so it is corrected here
        instead of being carried across.
        """
        g = _girth(mer, ty)
        for side in (-1.0, 1.0):
            for i in range(count):
                t = t0 if count < 2 else t0 + (t1 - t0) * i / (count - 1)
                x, z = _along(waist, t)
                h.part(bay_housing(*dims).rotate_y(side * HALF_PI)
                       .translate(side * x * g, ty * bh, body_z + z * g),
                       "bay", "%s %s %d" % ("port" if side < 0 else "starboard",
                                            tag, i + 1),
                       (side, 0.0, 0.0))

    bay_row(5 if cls.get("bays") else (3 if cls["body"] else 2), 0.25, 0.75,
            0.0, (0.10 * Z, 0.16 * Z, 0.24 * Z), "bay")
    if cls.get("bays"):
        bay_row(4, 0.32, 0.68, -0.30, (0.10 * Z, 0.12 * Z, 0.20 * Z), "lower bay")

    if plan["body"] == "double" or (cls["body"] == 2 and plan["body"] != "spindle"):
        # A second, smaller solid sitting on the first. Its lower apex is deep
        # inside the hull below it, so the pair reads as one stacked body and
        # not as a gem balanced on a point.
        h.part(unit.copy().scale(bw * 0.6, bh * 0.8, bl * 0.65)
               .translate(0.0, bh * 0.9, body_z),
               "body", "upper body", (0.0, 1.0, 0.0))

    if cls.get("cargo"):
        # Slung under the belly, high enough that the top of a container is
        # inside the hull's own box rather than a texel under it.
        cargo_run(h, cls["cargo"], body_z - bl * 0.4, body_z + bl * 0.4,
                  -bh - 0.16 * Z, 0.40 * Z, 0.36 * Z, 0.45 * Z)

    # ---- the ring, or the rings -----------------------------------------------
    ring_r = 1.35 * k_disc
    ring_z = -bl * 0.8 - 0.3 * RAKE
    rings = []

    def add_ring(kind, z, rr, name, tag):
        """Place a ring and the web nodes that ride on it.

        An arch is the same tube stood on end: the kit's torus lies flat, so it
        is turned about Y and then about X, which puts its half arc over the
        stern with both feet on the ring's own plane.
        """
        if kind == "arch":
            geo = torus(rr, 0.08 * Z, 14, 6, 180.0)
            geo.rotate_y(HALF_PI).rotate_x(HALF_PI)
            y = -bh * 0.2
            nodes = (30, 90, 150)
        else:
            geo = torus(rr, 0.08 * Z, 24, 6)
            y = 0.0
            nodes = (30, 90, 150, 210, 270, 330)
        h.part(geo.translate(0.0, y, z), "ring", name, (0.0, 0.0, -1.0))
        for deg in nodes:
            a = math.radians(deg)
            # A node is a cube proud of the tube rather than flush with it. The
            # source made it smaller than the tube it sat on, which is a stud:
            # invisible at the identification size and paid for in triangles.
            if kind == "arch":
                seat = (math.cos(a) * rr, y + math.sin(a) * rr, z)
            else:
                seat = (math.cos(a) * rr, y, z - math.sin(a) * rr)
            h.part(box(0.20 * Z, 0.20 * Z, 0.20 * Z).translate(*seat),
                   "greeble", "%s node at %d degrees" % (tag, deg),
                   (math.cos(a), 0.0, -math.sin(a)))
        return dict(kind=kind, z=z, rr=rr, y=y)

    if plan["ring"] in ("aft", "belt+aft"):
        rings.append(add_ring("flat", ring_z, ring_r,
                              "the ring, for the tractor web", "ring"))
    if plan["ring"] in ("belt", "belt+aft"):
        rings.append(add_ring("flat", body_z, max(bw, ring_r * 0.8) + 0.12 * Z,
                              "the belt ring, round the waist", "belt"))
    if plan["ring"] == "arch":
        rings.append(add_ring("arch", ring_z + 0.3 * Z, ring_r * 0.9,
                              "the arch, over the stern", "arch"))
    if plan["ring"] == "double":
        rings.append(add_ring("flat", ring_z, ring_r, "the aft ring", "aft ring"))
        rings.append(add_ring("flat", ring_z - 0.55 * Z, ring_r * 0.8,
                              "the second ring", "second ring"))

    # ---- the drives ------------------------------------------------------------
    #
    # They stand on the aft most FLAT ring, which is what a Sarn player reads
    # the class from at a glance: a heavy cruiser wears its belt amidships and
    # therefore carries its drives amidships too, and an arch class hangs them
    # under the arch's feet.
    host = next((r for r in rings if r["kind"] == "flat" and r["z"] < 0.0),
                rings[0])
    seats = (0, 180, 60, 120) if cls["pods"] == 4 else (0, 180)
    for i, deg in enumerate(seats):
        a = math.radians(deg)
        if host["kind"] == "arch":
            seat = (math.cos(a) * host["rr"], host["y"],
                    host["z"] - 0.15 * Z - (0.3 * Z if i > 1 else 0.0))
        else:
            seat = (math.cos(a) * host["rr"], 0.0,
                    host["z"] - math.sin(a) * host["rr"] - 0.1 * Z)
        label = DRIVE_SEAT[deg]
        h.part(drive_drum(0.16 * Z, 0.70 * Z).translate(*seat), "pod",
               label + " drive, on the ring", (math.cos(a), 0.0, -0.5))
        h.part(bowl(0.13 * Z, 0.05 * Z, 8).rotate_x(-HALF_PI)
               .translate(seat[0], seat[1], seat[2] - 0.32 * Z),
               "glow", label + " drive bell", (math.cos(a), 0.0, -1.0),
               glow=True)

    # Two struts from the hull out to the host ring. They start on the
    # centreline rather than a fixed distance off it, because a spindle is
    # narrow where the ring meets it and a flat diamond is wide, and a strut
    # that starts outboard of the hull is a strut holding nothing.
    strut_w = host["rr"] + 0.04 * Z
    strut_z = host["z"] + 0.3 * Z

    def make_strut(side):
        return box(strut_w, 0.12 * Z, 0.26 * Z).translate(
            side * strut_w * 0.5, host["y"], strut_z)

    h.pair(make_strut, "pylon", "ring strut", (1.0, 0.0, -0.5))

    # ---- the prow ---------------------------------------------------------------
    #
    # A gem's facets do not reach its scaled extent the way a diamond's do, so
    # the prow roots in the body's real tip rather than in an arithmetic one.
    tip_z = body.bounds()[1][2]
    prow_len = (0.7 if plan["prow"] == "trident" else 0.9) * Z
    # Seated 0.26 deep, not 0.12. A spindle tapers to a point, so at a
    # twelfth of a unit the prow met the body where the body was already
    # thinner than a pixel and the two measured as separate blobs.
    prow_z = tip_z + prow_len * 0.5 - 0.26 * Z
    if plan["prow"] == "blade":
        prow_geo = prism(0.9 * Z, 0.12 * Z, prow_len, 0.15, 1.0)
        prow_name = "the blade prow"
    elif plan["prow"] == "trident":
        prow_geo = spike(prow_len, 0.20 * Z, 6)
        prow_name = "the trident prow"
    else:
        prow_geo = spike(prow_len, 0.28 * Z, 6)
        prow_name = "the prow, a cone"
    h.part(prow_geo.translate(0.0, 0.0, prow_z), "head", prow_name,
           (0.0, 0.0, 1.0))

    if plan["prow"] == "trident":
        # Inboard of where the source hung them. Their roots sat clear of the
        # cone's base there, so the three points of a trident were three
        # separate pieces at sixty pixels rather than one fork.
        for side in (-1.0, 1.0):
            h.part(spike(0.9 * Z, 0.06 * Z)
                   .translate(side * 0.22 * Z, 0.0, prow_z - 0.1 * Z),
                   "greeble",
                   ("port" if side < 0 else "starboard") + " tine",
                   (side * 0.3, 0.0, 1.0))
    elif plan["prow"] == "cone":
        for deg in (0, 120, 240):
            rz = math.radians(deg)
            h.part(fin(0.5 * Z, 0.12 * Z).translate(0.0, 0.12 * Z, -0.1 * Z)
                   .rotate_z(rz).translate(0.0, 0.0, prow_z),
                   "greeble", "prow fin at %d degrees" % deg,
                   (-math.sin(rz), math.cos(rz), 0.3))

    if cls.get("cranes"):
        for side in (-1.0, 1.0):
            h.part(crane(0.9 * Z).rotate_y(side * 0.5)
                   .translate(side * 0.3 * Z, -0.1 * Z, prow_z - 0.5 * Z),
                   "greeble", ("port" if side < 0 else "starboard") + " crane",
                   (side, 0.0, 1.0))
    return h
