#!/usr/bin/env python3
"""Parts every dialect shares, and the two rules about using them.

A warp pod is a warp pod on a Terran cruiser and on a Vaelith loop; only where
a culture PUTS one is dialect (docs/17 section 8). So the shapes live here once
and the faction modules place them, which is CLAUDE.md 4.1 applied to geometry.

The second rule is about detail. The diorama page hangs about forty small
meshes on a hull because a reviewer looks at it from a metre away. A tactical
hull is sixty pixels across, so what survives there is silhouette: a collector,
a deflector, a bridge, a cannon. Everything smaller is paint. These builders
therefore carry the greebles that change an outline and leave the rest to the
atlas, which is what keeps a hull near a thousand triangles instead of five.
"""

import math

from shipkit import (Geo, box, cone, cylinder, extrude, lathe, prism, sphere,
                     truss)

HALF_PI = math.pi * 0.5


def dome(r, segs=10, rings=4):
    """A hemisphere sitting on the XZ plane, pointing +Y.

    Rotate it to face the bow for a collector, leave it standing for a sensor.
    """
    prof = [(r, 0.0)]
    for i in range(1, rings + 1):
        t = HALF_PI * i / rings
        prof.append((r * math.cos(t), r * math.sin(t)))
    return lathe(prof, segs)


def bowl(r, depth, segs=10):
    """A shallow cap, for a deflector dish or a bay mouth."""
    return lathe([(r, 0.0), (r * 0.72, depth * 0.6), (0.0, depth)], segs)


def pod(length, r, side, collector=True):
    """A warp pod: a tapered body, a collector at the bow, a nozzle aft.

    `side` is -1 for port and +1 for starboard and decides nothing about the
    shape; the hull passes it to `Hull.pair` so the atlas knows which flank
    turns inboard and wears the field grille.
    """
    g = prism(r * 2.0, r * 1.6, length, 0.85, 0.72)
    # the spine rib, which is what reads as a nacelle rather than a box from
    # directly above
    g.add(box(r * 0.5, r * 0.24, length * 0.62).translate(0.0, r * 0.78, 0.0))
    # the aft nozzle plate, square on the stern
    g.add(box(r * 1.1, r * 0.9, r * 0.24)
          .translate(0.0, 0.0, -length * 0.5 * 0.72 - r * 0.1))
    return g


def collector(r):
    """The warm eye at a pod's bow. Its own part, because it is only light."""
    return dome(r, 10, 3).rotate_x(HALF_PI)


def pylon(frm, to, thick):
    """A blade from `frm` to `to`, its broad faces vertical whatever the sweep.

    Sheared rather than rotated, the same fix the diorama needed: a rotated
    blade turns its painted face under the hull and reads as a black bar.
    """
    dx, dy, dz = (to[0] - frm[0], to[1] - frm[1], to[2] - frm[2])
    g = box(thick, 1.0, thick * 3.2)
    out = []
    for (x, y, z) in g.verts:
        t = y + 0.5
        out.append((x + t * dx + frm[0], t * dy + frm[1], z + t * dz + frm[2]))
    g.verts = out
    return g


def container(w, h, d):
    """One cargo box. A freighter's silhouette is a row of these."""
    return box(w, h, d)


def crane(length, r=0.09):
    """A slew ring, an arm and a hook, reaching toward the bow.

    The one part nothing else in the fleet has, which is what makes a tender
    read as a tender from above (docs/17 section 9).
    """
    g = cylinder(r * 1.2, r * 0.9, 8)
    g.add(box(r * 0.8, r * 0.8, length).translate(0.0, r * 0.6, length * 0.5))
    g.add(box(r * 0.6, r * 1.8, r * 0.6)
          .translate(0.0, -r * 0.4, length - r * 0.4))
    return g


def bay_housing(w, h, d):
    """A hangar mouth: a block with its opening toward the bow."""
    return box(w, h, d)


def drive_drum(r, length, segs=8):
    """A drive bell lying along Z, lit at the stern."""
    return cylinder(r, length, segs).rotate_x(HALF_PI)


def cannon(length, r, segs=6):
    """A barrel pointing at the bow. Kthaari disruptors, Vaelith spade guns."""
    return lathe([(0.0, -length * 0.5), (r * 1.35, -length * 0.5),
                  (r, length * 0.5 * 0.7), (r * 0.8, length * 0.5)],
                 segs).rotate_x(HALF_PI)


def spike(length, r, segs=4):
    """A four sided spike pointing at the bow."""
    return cone(r, length, segs).rotate_x(HALF_PI)


def fin(length, height, thick=0.05):
    """A raked blade standing on its long edge, in the XZ plane."""
    pts = [(0.0, -length * 0.5), (0.0, length * 0.5),
           (height, length * 0.2), (height, -length * 0.3)]
    g = extrude([(p[0], p[1]) for p in pts], thick)
    return g.rotate_z(HALF_PI)


def hoop(R, r, segs=16, tube=5):
    """A thin ring standing upright, for a deflector housing."""
    from shipkit import torus
    return torus(R, r, segs, tube).rotate_x(HALF_PI)


def cargo_run(hull, count, z0, z1, y, w, h, d, role="cargo"):
    """`count` containers two abreast between two stations, port and starboard.

    Returns nothing: it adds the parts, because a cargo run is a row of pieces
    rather than one shape, and the wreck wants them thrown separately.
    """
    cols = max(1, (count + 1) // 2)
    for i in range(count):
        col = i // 2
        sx = 1.0 if (i % 2) else -1.0
        z = (z0 + z1) * 0.5 if cols == 1 else z0 + (z1 - z0) * col / (cols - 1)
        hull.part(container(w, h, d).translate(sx * w * 0.55, y, z), role,
                  ("starboard" if sx > 0 else "port") + " container %d" % (col + 1),
                  (sx * 0.6, -0.4, 0.0))
