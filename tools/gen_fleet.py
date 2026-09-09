#!/usr/bin/env python3
"""Writes the fleet: sixty committed hulls, six painted atlases, and everything
the game needs to fly them.

WHAT THIS REPLACES.

The diorama page built six factions by ten classes in JavaScript so they could
be reviewed. A page cannot be the authority for a shape the game flies
(CLAUDE.md section 2), and two implementations of the same ship would diverge
(section 4.1), so the geometry moved to `tools/shipkit.py` and the dialects to
`tools/fleet/`. This is the driver that turns them into assets.

WHAT IT WRITES, per faction and class:

    assets/meshes/hull_<faction>_<class>.obj          the hull
    assets/meshes/hull_<faction>_<class>_frag_N.obj   eight pieces, for the wreck
    assets/meshes/hull_<faction>_<class>_wire.obj     the top down wireframe
    assets/graphics/hull_<faction>_<class>_*.png      the standard set, section 3.2

and per faction only, because ten hulls of one culture wear one skin:

    assets/textures/hull_<faction>_diffuse.png        the shared atlas
    assets/textures/hull_<faction>_lights.png         windows and bays
    assets/textures/hull_<faction>_engines.png        drives and collectors
    assets/materials/mat_hull_<faction>.tres

Every mesh goes through `shiplib.Obj.write`, which refuses a hull that is not
one piece by both measures of CLAUDE.md section 2.1, so a detached pod cannot
reach a commit.

Usage:
    python3 tools/gen_fleet.py                    everything
    python3 tools/gen_fleet.py --faction terran   one culture
    python3 tools/gen_fleet.py --list             what it would write
"""

import argparse
import importlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import shipkit as kit                                            # noqa: E402
from shiplib import Obj, load_palette, verify                    # noqa: E402

ROOT = os.path.dirname(HERE)
MESH_OUT = os.path.join(ROOT, "assets", "meshes")
TEX_OUT = os.path.join(ROOT, "assets", "textures")
MAT_OUT = os.path.join(ROOT, "assets", "materials")
GFX_OUT = os.path.join(ROOT, "assets", "graphics")
PALETTE = os.path.join(ROOT, "data", "palette.json")

## How many pieces a destroyed hull comes apart into. The same number every
## painter has used since the first wreck, because the wreck scene's chunk
## slots line up whatever died (src/ui/wreck.gd).
FRAGMENTS = 8


def hull_id(faction, cls_id):
    """The name every asset of one hull shares. `ship_rig.gd` derives the
    fragment and wireframe paths from it, so it is a contract, not a label."""
    return "hull_%s_%s" % (faction, cls_id)


def build_one(faction, cls):
    """One hull, built, sized and checked, ready to emit."""
    module = importlib.import_module("fleet." + faction)
    hull = module.build(cls)
    hull.fit_footprint(cls["foot"]).centre().sit(0.0)
    parts, loose = hull.attachment()
    if parts != 1:
        raise SystemExit("%s/%s is %d pieces: %s"
                         % (faction, cls["id"], parts, ", ".join(loose)))
    return hull


MATERIAL = '''[gd_resource type="StandardMaterial3D" load_steps=3 format=3]

; The %(name)s skin. One atlas dresses all ten hulls of the culture, because
; the faction IS the paint: a Terran frigate and a Terran dreadnought are the
; same plates at different part counts (docs/17 section 8). Filtering is off so
; a texel stays a chunk, and the lights map does the windows and the drives.

[ext_resource type="Texture2D" path="res://assets/textures/%(stem)s_diffuse.png" id="1"]
[ext_resource type="Texture2D" path="res://assets/textures/%(stem)s_lights.png" id="2"]

[resource]
albedo_texture = ExtResource("1")
texture_filter = 0
roughness = 0.75
metallic = 0.05
emission_enabled = true
emission_energy_multiplier = 1.4
emission_texture = ExtResource("2")
'''


def paint_faction(faction):
    """Paint and write one culture's three maps and its material."""
    from fleet import paint
    roles = load_palette(PALETTE, faction)
    diffuse, lights, engines = paint.paint_faction(faction, roles)
    verify(diffuse, lights, engines, roles, kit.ALL_RECTS, kit.TEX)
    stem = "hull_%s" % faction
    diffuse.save(os.path.join(TEX_OUT, stem + "_diffuse.png"), kit.SCALE)
    lights.save(os.path.join(TEX_OUT, stem + "_lights.png"), kit.SCALE)
    engines.save(os.path.join(TEX_OUT, stem + "_engines.png"), kit.SCALE)
    with open(os.path.join(MAT_OUT, "mat_%s.tres" % stem), "w") as f:
        f.write(MATERIAL % {"name": faction.title(), "stem": stem})
    return stem


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--faction", action="append", choices=kit.FACTIONS)
    ap.add_argument("--cls", action="append",
                    choices=[c["id"] for c in kit.CLASSES])
    ap.add_argument("--list", action="store_true", help="say what would be written")
    ap.add_argument("--no-paint", action="store_true", help="meshes only")
    ap.add_argument("--no-extras", action="store_true",
                    help="skip fragments, wireframes and the graphic set")
    args = ap.parse_args()

    factions = args.faction or list(kit.FACTIONS)
    classes = [c for c in kit.CLASSES
               if not args.cls or c["id"] in args.cls]

    for d in (MESH_OUT, TEX_OUT, MAT_OUT, GFX_OUT):
        os.makedirs(d, exist_ok=True)

    if args.list:
        for f in factions:
            for c in classes:
                print(hull_id(f, c["id"]))
        return

    written = []
    for faction in factions:
        if not args.no_paint:
            paint_faction(faction)
        for cls in classes:
            name = hull_id(faction, cls["id"])
            hull = build_one(faction, cls)
            obj = Obj(MESH_OUT)
            hull.emit(obj)
            obj.write(name + ".obj", "%s %s, from tools/gen_fleet.py"
                      % (faction.title(), cls["name"].lower()))
            if not args.no_extras:
                obj.write_fragments(name, FRAGMENTS,
                                    "%s %s" % (faction.title(), cls["name"].lower()))
            written.append((name, len(obj.v), len(obj.f), len(hull.parts)))

    if not args.no_extras:
        import gen_wireframes
        gen_wireframes.main([n for (n, _v, _f, _p) in written])
        import gen_ship_graphics
        gen_ship_graphics.main([os.path.join(MESH_OUT, n + ".obj")
                                for (n, _v, _f, _p) in written])

    print("\n%-34s %6s %6s %6s" % ("hull", "verts", "tris", "parts"))
    for (name, v, f, p) in written:
        print("%-34s %6d %6d %6d" % (name, v, f, p))
    print("\n%d hulls" % len(written))


if __name__ == "__main__":
    main()
