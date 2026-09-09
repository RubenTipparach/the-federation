#!/usr/bin/env python3
"""Build the starship diorama page from its template and the palette.

The page under docs/mockups is the review artifact for docs/17 and the
reference for the standard graphic set of CLAUDE.md section 3.2. Its only
input besides the template is data/palette.json, pasted in as the PAL table
so that a palette swap regenerates the page too (CLAUDE.md section 3.1).
Edit tools/dioramas/starship-dioramas.src.html, never the built file.
"""
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "dioramas", "starship-dioramas.src.html")
OUT = os.path.join(ROOT, "docs", "mockups", "starship-dioramas.html")


def main():
    with open(os.path.join(ROOT, "data", "palette.json")) as f:
        pal = json.load(f)
    table = dict(pal["colors"])
    table.update(pal.get("ui_colors", {}))
    with open(SRC) as f:
        src = f.read()
    if "__PALETTE__" not in src:
        raise SystemExit("template has no __PALETTE__ placeholder")
    page = src.replace("__PALETTE__", "const PAL = %s;\n" % json.dumps(table))
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w") as f:
        f.write(page)
    print("wrote %s (%d bytes)" % (os.path.relpath(OUT, ROOT), len(page)))


if __name__ == "__main__":
    main()
