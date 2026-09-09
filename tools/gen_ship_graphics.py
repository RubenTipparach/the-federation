#!/usr/bin/env python3
"""Writes the standard graphic set of CLAUDE.md section 3.2 for every hull.

Per hull, into assets/graphics/:

    <hull>_schematic.png   256 px, one palette role on transparent
    <hull>_icon.png         64 px, white on transparent, the solid silhouette
    <hull>_outline.png     128 px, white on transparent, the icon's contour

They are drawn from the committed .obj and never by hand, so the SSD, the
fleet roster, the target readout, the shipyard listing, the map blip and the
post battle report all show the same ship, and none of them can disagree with
the mesh. Regenerate when a mesh changes; never edit the PNGs.

Usage:
    python3 tools/gen_ship_graphics.py              every hull in assets/meshes
    python3 tools/gen_ship_graphics.py <obj> ...    the hulls named

WHY THE SCHEMATIC IS DRAWN FROM IDS AND NOT FROM EDGES.

Tracing the mesh edges draws every plate, every bevel and every triangle of a
sphere. That is a wireframe, tools/gen_wireframes.py already writes one, and it
is not what a schematic is. So every PART is rastered in its own flat id and a
line goes wherever the id changes between neighbouring samples, plus the outer
silhouette. What that leaves is exactly the three things section 3.2 asks for:
the silhouette, the seam where one part meets another, and each greeble's
outline. Nothing else. A faint grid inside the silhouette is on the diorama
page as a test and is not part of the standard, so none is drawn here.

WHERE THE PART IDS COME FROM.

The committed .obj carries no g or o lines and must not grow any: Godot's
importer and the fragment writer both read these files. It does not need them.
`shipkit.Hull.emit` builds a fresh vertex table per PART, so no two parts ever
share a vertex INDEX, and a union find over the raw indices recovers the parts
exactly. This is deliberately NOT the position based aliasing that
`shiplib.mesh_components` does: that one is asking "is this hull one piece", so
it wants two coincident positions to merge, and this one is asking "which part
is this triangle", where merging them would weld the seam it is looking for.

WHY THE PROJECTION IS WHAT IT IS.

Top down, because that is the camera the game plays on and the size a hull is
identified at. Bow up, because a chart is read with the ship pointing away from
the reader. The bow is +z in game space (src/ui/hull_view.gd looks straight
down with up = (0, 0, 1)), and bow up on a page means the page runs the other
way, so page_x = +x and page_y = -z: the raster is turned over once, below,
and every graphic is measured from the turned buffer.

Fitted, not at fleet scale: the hull is normalised by the larger of its x and z
spans, so a frigate's icon fills its box exactly as a dreadnought's does and
class is read from the roster's render column or the SSD instead. The sixty
pixel silhouette check of section 2.1 is the one that runs at fleet scale.

WHY THERE IS ONE MASTER RASTER.

All three graphics come from a single id buffer at 1024 px, box filtered down.
That is 4x supersampling for the schematic, 8x for the outline and 16x for the
icon, which is what section 6.6 wants of a coverage mask, and it is also what
stops the three from drifting: they are three readings of one drawing rather
than three drawings. The rasteriser is `shiplib.raster_top_down`, the same one
the one piece check draws its silhouette with (CLAUDE.md 4.1).
"""

import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from shiplib import Px, load_role_map, raster_top_down, read_obj  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MESH_DIR = os.path.join(ROOT, "assets", "meshes")
GFX_OUT = os.path.join(ROOT, "assets", "graphics")
PALETTE = os.path.join(ROOT, "data", "palette.json")

## The three sizes of CLAUDE.md section 3.2.
SCHEMATIC_PX = 256
ICON_PX = 64
OUTLINE_PX = 128

## Supersampling for the largest of them. The master raster is that product,
## 1024, which is a whole multiple of all three sizes: 4 x 256, 8 x 128 and
## 16 x 64. Every graphic is a box filter of the one buffer.
SUPER = 4
MASTER_PX = SCHEMATIC_PX * SUPER

## The eight percent margin, as a fraction of the square. Fitted inside it.
MARGIN = 0.08

## The icon and the outline are masks rather than art: white and transparent,
## tinted by whatever screen draws them, so they name no palette role and
## section 3.1 has nothing to say about them.
WHITE = (255, 255, 255)

## Neighbourhoods for growing a line. Alternating between them approximates the
## octagon distance: growing only by the four makes a diagonal line a third
## thinner than an axis aligned one, and only by the eight makes it half again
## as thick, and a drawing wants one weight everywhere.
OFF4 = ((1, 0), (-1, 0), (0, 1), (0, -1))
OFF8 = OFF4 + ((1, 1), (1, -1), (-1, 1), (-1, -1))


def part_ids(verts, faces):
    """One part id per face, numbered from 1, and how many parts there are.

    Union find over the RAW vertex indices, joining the three corners of every
    triangle. See the module comment: parts do not share vertex indices, so
    this recovers them exactly, and it must not be replaced by the position
    based merge in `shiplib.mesh_components`, which would weld the seams."""
    parent = list(range(len(verts)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for face in faces:
        a = face[0][0] - 1
        for corner in face[1:]:
            ra, rb = find(a), find(corner[0] - 1)
            if ra != rb:
                parent[ra] = rb
    label = {}
    ids = []
    for face in faces:
        root = find(face[0][0] - 1)
        ids.append(label.setdefault(root, len(label) + 1))
    return ids, len(label)


def turn_over(grid, px):
    """page_y = -z. The rasteriser draws +z down the page and the bow is +z,
    so the buffer is turned over once and read bow up from here on."""
    out = []
    for y in range(px - 1, -1, -1):
        out.extend(grid[y * px:(y + 1) * px])
    return out


def seeds(grid, px):
    """The two one pixel wide seed sets a schematic line starts from.

    `edge` is the inside of the silhouette's contour, and `seam` is the pixels
    either side of a boundary between two parts. They are separate because
    they thicken differently: a seam is seeded on both sides and grows into a
    line centred on the join, while the contour is seeded on one side only and
    grows inward, which is what keeps every graphic strictly inside the fitted
    square that section 3.2's margin measures."""
    edge, seam = [], []
    for i, a in enumerate(grid):
        if not a:
            continue
        y, x = divmod(i, px)
        open_side = False
        other_part = False
        for dx, dy in OFF4:
            nx, ny = x + dx, y + dy
            b = grid[ny * px + nx] if (0 <= nx < px and 0 <= ny < px) else 0
            if b == 0:
                open_side = True
            elif b != a:
                other_part = True
        if open_side:
            edge.append(i)
        elif other_part:
            seam.append(i)
    return edge, seam


def thicken(seed, grid, px, steps):
    """Grow a seed set `steps` times, staying inside the hull, and return every
    pixel reached. Staying inside is the point: ink never leaves the fitted
    square, and the contour reads as the hull's own edge rather than as a halo
    around it."""
    mask = bytearray(px * px)
    reached = list(seed)
    for i in seed:
        mask[i] = 1
    frontier = list(seed)
    for step in range(steps):
        offs = OFF4 if step % 2 == 0 else OFF8
        nxt = []
        for i in frontier:
            y, x = divmod(i, px)
            for dx, dy in offs:
                nx, ny = x + dx, y + dy
                if 0 <= nx < px and 0 <= ny < px:
                    j = ny * px + nx
                    if grid[j] and not mask[j]:
                        mask[j] = 1
                        nxt.append(j)
        reached.extend(nxt)
        frontier = nxt
    return reached


def coverage(indices, px, factor):
    """Box filter a supersampled mask down. `indices` is every set pixel of
    the master raster; the result is one coverage value in 0..1 per finished
    pixel, which is the anti-aliasing of section 6.6: nothing is snapped to
    the pixel grid, a partly covered pixel is partly opaque."""
    out = px // factor
    hits = [0] * (out * out)
    for i in indices:
        y, x = divmod(i, px)
        hits[(y // factor) * out + x // factor] += 1
    weight = 1.0 / (factor * factor)
    return [n * weight for n in hits], out


def write_mask(path, cov, px, rgb):
    """A coverage mask as RGBA: one flat colour everywhere, coverage in alpha.

    The colour is written into the transparent pixels too. A filtered draw
    blends the colours of neighbouring texels whatever their alpha, so a mask
    that left them black would fringe every edge with a dark line."""
    art = Px(px, background=rgb, alpha=0)
    for i, c in enumerate(cov):
        if c > 0.0:
            art.put(i % px, i // px, rgb, alpha=int(round(255.0 * c)))
    art.save(path)
    return sum(1 for c in cov if c > 0.0)


def write_set(obj_path, line_rgb, out_dir=GFX_OUT):
    """The three graphics of one hull. Returns a line of counts, for the log."""
    name = os.path.splitext(os.path.basename(obj_path))[0]
    verts, faces = read_obj(obj_path)
    ids, parts = part_ids(verts, faces)
    grid = raster_top_down(verts, faces, MASTER_PX, ids=ids,
                           margin=MARGIN * MASTER_PX)
    grid = turn_over(grid, MASTER_PX)

    filled = [i for i, v in enumerate(grid) if v]
    edge, seam = seeds(grid, MASTER_PX)

    # The icon: the silhouette, solid.
    icon_cov, icon_px = coverage(filled, MASTER_PX, MASTER_PX // ICON_PX)
    icon_ink = write_mask(os.path.join(out_dir, name + "_icon.png"),
                          icon_cov, icon_px, WHITE)

    # The outline: the same contour, one finished pixel wide. One master pixel
    # of seed plus the rest of the width grown inward.
    wide = MASTER_PX // OUTLINE_PX
    ring = thicken(edge, grid, MASTER_PX, wide - 1)
    out_cov, out_px = coverage(ring, MASTER_PX, wide)
    out_ink = write_mask(os.path.join(out_dir, name + "_outline.png"),
                         out_cov, out_px, WHITE)

    # The schematic: that contour plus the seams, at 256. A seam is seeded on
    # both sides, so it needs half as many steps to reach the same width.
    ink = bytearray(MASTER_PX * MASTER_PX)
    for i in thicken(edge, grid, MASTER_PX, SUPER - 1):
        ink[i] = 1
    for i in thicken(seam, grid, MASTER_PX, SUPER // 2 - 1):
        ink[i] = 1
    lines = [i for i, v in enumerate(ink) if v]
    sch_cov, sch_px = coverage(lines, MASTER_PX, SUPER)
    sch_ink = write_mask(os.path.join(out_dir, name + "_schematic.png"),
                         sch_cov, sch_px, line_rgb)
    return (name, parts, icon_ink, out_ink, sch_ink)


def main(paths=None):
    """Write the set for every hull named, or for every hull on disk.

    Called by tools/gen_fleet.py with the hulls it has just written, and run on
    its own to redraw the lot. Wreck fragments are meant to be pieces and a
    wireframe is line art, so neither is a hull here, which is the same rule
    tools/check_hulls.py picks its files by."""
    if paths is None:
        paths = sorted(p for p in glob.glob(os.path.join(MESH_DIR, "hull_*.obj"))
                       if "_frag_" not in p and "_wire" not in p)
    if not paths:
        raise SystemExit("no hulls to draw")
    os.makedirs(GFX_OUT, exist_ok=True)
    roles, _palette = load_role_map(PALETTE, "graphics")
    line_rgb = roles["schematic_line"]
    rows = []
    for path in paths:
        rows.append(write_set(path, line_rgb))
    print("\n%-34s %6s %8s %8s %10s" % ("hull", "parts", "icon", "outline",
                                        "schematic"))
    for (name, parts, icon_ink, out_ink, sch_ink) in rows:
        print("%-34s %6d %8d %8d %10d" % (name, parts, icon_ink, out_ink,
                                          sch_ink))
    print("\n%d hulls, %d graphics" % (len(rows), 3 * len(rows)))
    return rows


if __name__ == "__main__":
    # Arguments are hull paths, so a flag is a mistake rather than an option.
    # Say the usage instead of failing inside the OBJ reader on a file called
    # "--help", which is what a bare pass through did.
    if any(a.startswith("-") for a in sys.argv[1:]):
        print(__doc__.strip())
        sys.exit(0 if {"-h", "--help"} & set(sys.argv[1:]) else 2)
    main(sys.argv[1:] or None)
