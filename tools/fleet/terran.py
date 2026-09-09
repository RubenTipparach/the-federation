#!/usr/bin/env python3
"""The Terran Concord: a dominant disc, a bladed neck, a tapered secondary hull
and paired pods above the plane on forward raked pylons (docs/17 section 8.3).

This is the worked example the other five dialects follow. Read it as: take the
class row, spend its part count in this grammar, and let `Hull.fit_length`
decide how big the result ends up. Nothing here knows what a frigate weighs.
"""

import math

from shipkit import Hull, box, cylinder, disc, prism, truss
from fleet.parts import (HALF_PI, bay_housing, bowl, cannon, cargo_run,
                         collector, crane, dome, drive_drum, fin, hoop, pod,
                         pylon)

RAKE = 0.30


def build(cls):
    h = Hull("terran", cls["id"])
    Z = cls["size"]
    k_disc = cls["disc"] * Z if "disc" in cls else Z
    k_spine = cls["spine"] * Z
    pods = cls["pods"]
    cargo = cls.get("cargo", 0)
    has_body = bool(cls["body"]) or bool(cargo)

    disc_r = 1.35 * k_disc
    disc_h = 0.30 * Z
    dome_h = 0.13 * Z
    spine = 2.2 * k_spine if has_body else 0.0
    pod_len = 2.4 * cls.get("pod_len", 1.0) * Z
    disc_z = 1.25 * k_spine if has_body else 0.0
    disc_y = 0.35 * Z

    # ---- the primary hull ----------------------------------------------------
    h.part(disc(disc_r, disc_h, dome_h).translate(0.0, disc_y, disc_z),
           "disc", "primary hull, disc", (0.0, 0.0, 1.0))
    # the impulse block on the trailing edge, which is the one warm mark a
    # Terran shows from directly astern
    h.part(box(0.55 * Z, 0.16 * Z, 0.30 * Z)
           .translate(0.0, disc_y, disc_z - disc_r + 0.05),
           "glow", "impulse block", (0.0, 0.0, -1.0), glow=True)
    # the lower sensor dome, under the saucer
    h.part(dome(0.30 * Z, 10, 3).rotate_x(math.pi)
           .translate(0.0, disc_y - disc_h * 0.5, disc_z),
           "greeble", "sensor dome", (0.0, -1.0, 0.0))
    bridge_y = disc_y + disc_h * 0.5 + dome_h + 0.05 * Z
    h.part(cylinder(0.24 * Z, 0.12 * Z, 8)
           .translate(0.0, bridge_y, disc_z + disc_r * 0.18),
           "greeble", "bridge", (0.0, 1.0, 0.0))

    # ---- neck and secondary hull ---------------------------------------------
    if cls["neck"] and has_body:
        neck = box(0.24 * Z, 0.60 * Z, 1.0 * Z).rotate_x(0.40)
        h.part(neck.translate(0.0, 0.12 * Z, 0.35 * k_spine - 0.40 * Z),
               "pylon", "neck", (0.0, 1.0, 0.0))

    body_y = -0.20 * Z
    body_z = -0.50 * k_spine
    if cls["body"]:
        twin = cls["body"] == 2
        bw = (0.90 if twin else (1.50 if cls.get("bays") else 1.10)) * Z
        xs = (-0.50 * Z, 0.50 * Z) if twin else (0.0,)
        for i, bx in enumerate(xs):
            name = "secondary hull"
            if twin:
                name = ("port " if bx < 0 else "starboard ") + name
            h.part(prism(bw, 0.70 * Z, spine, 0.90, 0.62)
                   .translate(bx, body_y, body_z),
                   "body", name, (0.0 if not twin else (1.0 if bx > 0 else -1.0),
                                  -1.0, 0.0))
            nose = body_z + spine * 0.5
            h.part(hoop(0.24 * Z, 0.035 * Z).translate(bx, body_y, nose + 0.02),
                   "greeble", name + " deflector housing", (0.0, 0.0, 1.0))
            h.part(bowl(0.20 * Z, 0.06 * Z).rotate_x(HALF_PI)
                   .translate(bx, body_y, nose + 0.01),
                   "glow", name + " deflector", (0.0, 0.0, 1.0), glow=True)
            h.part(box(0.36 * Z, 0.14 * Z, 0.34 * Z)
                   .translate(bx, body_y + 0.33 * Z, nose - 0.25 * Z),
                   "greeble", name + " torpedo launcher", (0.0, 1.0, 1.0))
            h.part(fin(0.90 * Z, 0.16 * Z).rotate_z(math.pi)
                   .translate(bx, body_y - 0.24 * Z, body_z - spine * 0.4 + 0.45 * Z),
                   "greeble", name + " keel", (0.0, -1.0, 0.0))
            if cls.get("bays"):
                for sx in (-1.0, 1.0):
                    for j in range(4):
                        bz = body_z + spine * 0.3 - j * spine * 0.2
                        h.part(bay_housing(0.22 * Z, 0.16 * Z, 0.30 * Z)
                               # 0.42 of the beam, not half of it: the
                               # hull narrows toward the bow, so a bay
                               # hung on the nominal flank overhung the
                               # real one at the forward station and
                               # measured as a loose block.
                               .translate(bx + sx * bw * 0.42,
                                          body_y - 0.05 * Z, bz),
                               "bay", "%s bay %d" % ("port" if sx < 0 else "starboard", j + 1),
                               (sx, 0.0, 0.0))

    # ---- the cargo variants ---------------------------------------------------
    if cargo:
        # The spine runs from under the saucer to the drive, so the command
        # hull sits ON it: a freighter has no neck in the ladder and this is
        # what keeps it one piece all the same (CLAUDE.md 2.1).
        spine_y = disc_y - disc_h * 0.5 - 0.11 * Z
        spine_z = disc_z - spine * 0.5 + 0.30 * Z
        h.part(truss(spine, 0.26 * Z).translate(0.0, spine_y, spine_z),
               "truss", "cargo spine", (0.0, 1.0, 0.0))
        cargo_run(h, cargo, spine_z - spine * 0.36, spine_z + spine * 0.30,
                  spine_y - 0.28 * Z, 0.50 * Z, 0.45 * Z, 0.55 * Z)
        h.part(drive_drum(0.16 * Z, 0.50 * Z)
               .translate(0.0, spine_y, spine_z - spine * 0.5 - 0.16 * Z),
               "glow", "cargo drive", (0.0, 0.0, -1.0), glow=True)
        body_y, body_z = spine_y, spine_z
    if cls.get("cranes"):
        for sx in (-1.0, 1.0):
            h.part(crane(1.1 * Z).rotate_y(sx * 0.4)
                   .translate(sx * 0.45 * Z, disc_y - disc_h * 0.45,
                              disc_z + disc_r * 0.30),
                   "greeble", ("port" if sx < 0 else "starboard") + " crane",
                   (sx, 0.0, 1.0))

    # ---- the pods -------------------------------------------------------------
    rows = ((1.25, 0.72), (0.35, 1.10)) if pods == 4 else \
           (((-0.55, 1.00),) if cls.get("low") else ((1.05, 0.95),))
    root_z = -0.60 * k_spine if has_body else 0.40 * k_spine
    root_y = 0.0 if has_body else 0.45 * Z
    for ri, (py, pxo) in enumerate(rows):
        spread = disc_r * pxo + 0.55 * Z
        pz = root_z - 0.55 * Z + RAKE * 1.2
        tier = ("upper ", "lower ")[ri] if len(rows) > 1 else ""

        def make_pod(side, _pz=pz, _spread=spread, _py=py):
            return pod(pod_len, 0.20 * Z, side).translate(
                side * _spread, root_y + _py * Z, _pz)
        made = h.pair(make_pod, "pod", tier + "pod", (1.0, 1.0 if ri == 0 else -0.5, 0.0),
                      inner=True)
        for side in (-1.0, 1.0):
            h.part(collector(0.17 * Z)
                   .translate(side * spread, root_y + py * Z, pz + pod_len * 0.5 - 0.01),
                   "glow", ("port " if side < 0 else "starboard ") + tier + "collector",
                   (side, 0.0, 1.0), glow=True)
            # The pylon roots INSIDE a hull volume, never on a point in space:
            # a cargo hull's only volume is its truss, which is why cargo is
            # tested before the body flag it also sets.
            if cargo:
                frm = (side * 0.06 * Z, body_y + 0.10 * Z, root_z - 0.10 * Z)
            elif cls["body"]:
                frm = (side * (0.85 if cls["body"] == 2 else 0.40) * Z,
                       body_y + (0.15 if ri else 0.25) * Z,
                       root_z - (0.50 if ri else 0.10) * Z)
            else:
                frm = (side * disc_r * 0.55, disc_y, disc_z - disc_r * 0.30)
            to = (side * (spread - 0.12), root_y + py * Z - 0.10 * Z,
                  pz - 0.40 * Z + RAKE * 0.6)
            h.part(pylon(frm, to, 0.08 * Z), "pylon",
                   ("port" if side < 0 else "starboard") + " " + tier + "pylon",
                   (side * 0.5, 0.0, 0.0))
    return h
