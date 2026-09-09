#!/usr/bin/env python3
"""Packs a committed `.obj` into the compact form the diorama page loads.

WHY THE PAGE STOPPED BUILDING ITS OWN SHIPS.

The page used to build all sixty hulls in JavaScript. Once the same hulls
became committed `.obj` files that the game flies, that JavaScript was a second
implementation of the fleet's geometry, which is the thing CLAUDE.md section
4.1 forbids above everything else. So the page loads what the game loads.

WHY NOT JUST EMBED THE OBJ TEXT.

An `.obj` of a thousand triangles is about eighty kilobytes of ASCII, and sixty
of them is five megabytes before base64. Quantised, the same mesh is twenty:
positions as 16 bit fixed point inside the mesh's own bounding box, texture
coordinates as 16 bit fractions, and triangles as 16 bit indices. Normals are
not sent at all, because the page shades these flat and a flat shaded surface
takes its normal from the derivative of the position rather than from a
vertex attribute.

The loss is a position error of one part in sixty five thousand of the hull's
size, which at the sizes involved is a hundredth of a texel.
"""

import base64
import struct


def read_obj(path):
    """Positions, texture coordinates and the face corners that index them."""
    verts, uvs, faces = [], [], []
    with open(path) as f:
        for line in f:
            if line.startswith("v "):
                verts.append(tuple(float(t) for t in line.split()[1:4]))
            elif line.startswith("vt "):
                uvs.append(tuple(float(t) for t in line.split()[1:3]))
            elif line.startswith("f "):
                corners = []
                for tok in line.split()[1:]:
                    bits = tok.split("/")
                    vi = int(bits[0]) - 1
                    ti = int(bits[1]) - 1 if len(bits) > 1 and bits[1] else -1
                    corners.append((vi, ti))
                for i in range(1, len(corners) - 1):
                    faces.append((corners[0], corners[i], corners[i + 1]))
    return verts, uvs, faces


def pack(path):
    """One mesh as a dict of base64 buffers and the numbers to unpack them.

    An `.obj` indexes positions and texture coordinates separately and a GPU
    cannot, so the corners are expanded into unique pairs first. A hull comes
    out with about half again as many vertices as it has positions, which is
    the seam cost of a hull whose parts do not share texture coordinates.
    """
    verts, uvs, faces = read_obj(path)
    lo = [min(v[i] for v in verts) for i in range(3)]
    hi = [max(v[i] for v in verts) for i in range(3)]
    span = [max(1e-9, hi[i] - lo[i]) for i in range(3)]

    index_of, pos, tex, tris = {}, [], [], []
    for tri in faces:
        out = []
        for (vi, ti) in tri:
            key = (vi, ti)
            if key not in index_of:
                index_of[key] = len(pos)
                v = verts[vi]
                pos.append(tuple(
                    int(round((v[i] - lo[i]) / span[i] * 65535.0))
                    for i in range(3)))
                t = uvs[ti] if 0 <= ti < len(uvs) else (0.0, 0.0)
                tex.append((int(round(min(1.0, max(0.0, t[0])) * 65535.0)),
                            int(round(min(1.0, max(0.0, t[1])) * 65535.0))))
            out.append(index_of[key])
        tris.append(out)

    if len(pos) > 65535:
        raise SystemExit("%s has %d vertices, past what 16 bit indices hold"
                         % (path, len(pos)))

    def b64(fmt, rows):
        return base64.b64encode(
            b"".join(struct.pack(fmt, *r) for r in rows)).decode("ascii")

    return {
        "lo": [round(x, 4) for x in lo],
        "span": [round(x, 4) for x in span],
        "n": len(pos),
        "pos": b64("<3H", pos),
        "uv": b64("<2H", tex),
        "idx": b64("<3H", tris),
    }


if __name__ == "__main__":
    import json
    import sys
    for arg in sys.argv[1:]:
        d = pack(arg)
        raw = len(open(arg, "rb").read())
        enc = len(json.dumps(d))
        print("%-46s %6d verts  %6d B obj  %6d B packed  %.0f%%"
              % (arg.split("/")[-1], d["n"], raw, enc, 100.0 * enc / raw))
