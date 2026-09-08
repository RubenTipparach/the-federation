#!/usr/bin/env python3
"""Run the one piece checks of CLAUDE.md section 2.1 over the committed hulls.

Reads assets/meshes/hull_*.obj, skipping wreck fragments and wireframes, and refuses any that is more than one mesh
component or leaves more than one blob in its 60 px top down silhouette, so a
hand edit in Blender is caught the same way a generator's output is.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from shiplib import one_piece  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def read_obj(path):
    verts, faces = [], []
    with open(path) as f:
        for line in f:
            if line.startswith("v "):
                verts.append(tuple(float(t) for t in line.split()[1:4]))
            elif line.startswith("f "):
                corners = []
                for tok in line.split()[1:]:
                    corners.append(tuple(int(t) if t else 0 for t in tok.split("/")))
                for i in range(1, len(corners) - 1):
                    faces.append((corners[0], corners[i], corners[i + 1]))
    return verts, faces


def main():
    # Wreck fragments are meant to be pieces and wireframes are line art, so
    # neither is a hull here.
    paths = sorted(p for p in glob.glob(os.path.join(ROOT, "assets", "meshes", "hull_*.obj"))
                   if "_frag_" not in p and "_wire" not in p)
    if not paths:
        raise SystemExit("no hulls found under assets/meshes")
    for path in paths:
        verts, faces = read_obj(path)
        one_piece(verts, faces, os.path.basename(path))


if __name__ == "__main__":
    main()
