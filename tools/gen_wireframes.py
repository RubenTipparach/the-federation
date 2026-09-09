#!/usr/bin/env python3
# Generates a top down wireframe of every playable hull, as a committed .obj.
#
# Per CLAUDE.md section 2 a script may generate a model but its output has to be
# a written .obj on disk, committed, never geometry built at runtime. Run this
# after tools/gen_ship_*.py, then commit what it writes.
#
# WHY THIS IS RIBBONS AND NOT LINES.
#
# The obvious way to draw a wireframe is a mesh of line primitives. Two things
# rule that out. Godot's .obj importer reads faces and ignores the "l" element
# entirely, so a line mesh could not be delivered as an .obj at all. And OpenGL
# line width above one pixel is unsupported on most modern drivers, so even a
# glTF line mesh would come out as hairlines whatever thickness it asked for,
# which on a 1080p pixel art readout is invisible. Every edge here is therefore
# a flat quad of an authored width, which is a normal triangle mesh that draws
# the same everywhere.
#
# WHY IT IS FLAT.
#
# The display this feeds looks straight down and never tilts, so the wireframe
# only has to be right from above. Projecting to the XZ plane before extruding
# collapses the top and bottom of a hull onto one outline, which is what makes
# the result read as a drawing of the ship rather than as a cage around it.
#
# WHICH EDGES SURVIVE.
#
# All of them is a mess: a hull is 190 triangles and most of their edges are
# interior seams that say nothing about the shape. Kept are the boundary edges
# and the creases, meaning the ones where the two faces either side turn by
# more than CREASE degrees. That is the standard feature edge test and it
# leaves the silhouette plus the structure a captain would recognise.
#
# Usage: python3 tools/gen_wireframes.py

import math
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
from gen_meshes import Obj, OUT  # noqa: E402
from shiplib import read_obj as shiplib_read_obj  # noqa: E402

## Hulls to trace. Named rather than globbed, because assets/meshes also holds
## the debris fragments and every overlay shape, and a wireframe of a beam is
## not a thing anybody wants.
HULLS = ["hull_cruiser", "hull_frigate", "hull_raider", "hull_placeholder"]

## Half the width of a drawn edge, in mesh units. The hulls are about 6 units
## long and the readout draws them 180 pixels wide, so this lands near two
## pixels, which is one block of the skin's art (tools/gen_ui_plates.B).
HALF_WIDTH = 0.035

## Degrees the surface has to turn across an edge before it counts as a crease.
## Twenty keeps panel lines and hull steps and drops the diagonals inside a
## quad that was triangulated.
CREASE = 20.0

## Endpoints closer than this in the XZ plane are the same point. The projection
## puts the top and the bottom of a slab on top of each other, and without a
## snap they stay two edges and paint twice.
SNAP = 0.02

## Shorter than this, projected, and an edge is a dot rather than a line.
MIN_LEN = 0.06


def read_obj(path):
    """Vertices and triangles from one of our own .obj files, as zero based
    index triples. The parsing is `shiplib.read_obj`, which is the only reader
    in the project (CLAUDE.md 4.1); this is the corner shape the edge tracing
    below wants, and it is the whole of the difference."""
    verts, faces = shiplib_read_obj(path)
    return verts, [tuple(c[0] - 1 for c in f) for f in faces]


def face_normal(verts, tri):
    a, b, c = (verts[i] for i in tri)
    u = (b[0] - a[0], b[1] - a[1], b[2] - a[2])
    v = (c[0] - a[0], c[1] - a[1], c[2] - a[2])
    n = (u[1] * v[2] - u[2] * v[1],
         u[2] * v[0] - u[0] * v[2],
         u[0] * v[1] - u[1] * v[0])
    ln = math.sqrt(sum(t * t for t in n)) or 1.0
    return tuple(t / ln for t in n)


def feature_edges(verts, tris):
    """Boundary edges and creases, as pairs of vertex indices."""
    faces = {}
    for tri in tris:
        n = face_normal(verts, tri)
        for i in range(3):
            a, b = tri[i], tri[(i + 1) % 3]
            faces.setdefault((min(a, b), max(a, b)), []).append(n)
    cos_limit = math.cos(math.radians(CREASE))
    out = []
    for (a, b), normals in faces.items():
        if len(normals) == 1:
            out.append((a, b))
            continue
        keep = False
        for i in range(len(normals)):
            for j in range(i + 1, len(normals)):
                if sum(x * y for x, y in zip(normals[i], normals[j])) < cos_limit:
                    keep = True
        if keep:
            out.append((a, b))
    return out


def flatten(verts, edges):
    """Project to XZ and drop the duplicates the projection creates."""
    def snap(p):
        return (round(p[0] / SNAP) * SNAP, round(p[2] / SNAP) * SNAP)

    seen, out = set(), []
    for a, b in edges:
        p, q = snap(verts[a]), snap(verts[b])
        if math.dist(p, q) < MIN_LEN:
            continue
        key = (p, q) if p <= q else (q, p)
        if key in seen:
            continue
        seen.add(key)
        out.append((p, q))
    return out


def ribbon(o, p, q):
    """One edge as a flat quad in the XZ plane, facing up."""
    dx, dz = q[0] - p[0], q[1] - p[1]
    ln = math.hypot(dx, dz) or 1.0
    # Perpendicular in the plane, scaled to half the drawn width.
    ox, oz = -dz / ln * HALF_WIDTH, dx / ln * HALF_WIDTH
    n = o.normal(0.0, 1.0, 0.0)
    a = o.vert(p[0] - ox, 0.0, p[1] - oz)
    b = o.vert(p[0] + ox, 0.0, p[1] + oz)
    c = o.vert(q[0] + ox, 0.0, q[1] + oz)
    d = o.vert(q[0] - ox, 0.0, q[1] - oz)
    # Wound so the cross product agrees with the declared normal, which is the
    # convention gen_meshes.py sets and the one Godot's lighting expects.
    o.tri(a, c, b, n)
    o.tri(a, d, c, n)


def main(names=None):
    """Trace `names`, or the hulls this file lists when called with none.

    The fleet driver hands in sixty names, which is why this takes a list at
    all: a second copy of the edge tracer for the generated hulls would be the
    divergence CLAUDE.md section 4.1 forbids.
    """
    for name in (names if names is not None else HULLS):
        src = os.path.join(OUT, name + ".obj")
        if not os.path.exists(src):
            print("skipped %s, no source mesh" % name)
            continue
        verts, tris = read_obj(src)
        edges = flatten(verts, feature_edges(verts, tris))
        o = Obj()
        for p, q in edges:
            ribbon(o, p, q)
        o.write(name + "_wire.obj",
                "Top down wireframe of %s.obj, %d edges" % (name, len(edges)))


if __name__ == "__main__":
    main()
