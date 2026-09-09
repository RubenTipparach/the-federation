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
from shiplib import one_piece, read_obj  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


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
