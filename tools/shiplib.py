# Shared library for the painted ship generators.
#
# One implementation of the pixel painter, the atlas mask helpers, the OBJ
# writer, the slab extruder, and the verification gates, used by every
# gen_ship_*.py script per CLAUDE.md section 4.1. The per ship scripts own
# their palette roles, atlas layout, painting, and silhouette; everything
# mechanical lives here.
#
# Color comes from data/palette.json, the project palette (CLAUDE.md 3.1).
# Generators name roles, the file says what those roles are painted in, and
# verify() fails the build on any pixel that is not a palette entry, so a
# color cannot drift in unnoticed. The painting vocabulary still comes from
# the author's sheets in docs/examples/ship-art; only the color does not.

import json
import math
import struct
import zlib

# ---- the project palette ----------------------------------------------------


def load_colors(path):
    """The palette itself: every name mapped to its RGB tuple."""
    with open(path) as f:
        data = json.load(f)
    colors = {}
    for name, value in data["colors"].items():
        text = value.lstrip("#")
        colors[name] = (int(text[0:2], 16), int(text[2:4], 16),
                        int(text[4:6], 16))
    return colors, data


def load_palette(path, ship):
    """One ship's role map plus the whole palette, read from the committed
    config file. Returns (roles, palette): roles maps a role name to an RGB
    tuple (or a tuple of them, for ramps), palette is every allowed color.

    A role naming a color the palette does not have raises here rather than
    painting something off palette, which is the point of the indirection."""
    colors, data = load_colors(path)

    def resolve(name):
        assert name in colors, "%r is not a palette color" % (name,)
        return colors[name]

    roles = {}
    for role, value in data["ships"][ship].items():
        # Underscore keys are the comment convention every data file in this
        # repo uses. They are prose, not colours.
        if role.startswith("_"):
            continue
        if isinstance(value, list):
            roles[role] = tuple(resolve(n) for n in value)
        else:
            roles[role] = resolve(value)
    return roles, set(colors.values())


def load_ramps(path):
    """The named lookup ramps, as lists of RGB tuples. Every ramp must be the
    same length so they bake into one rectangular texture whose rows the
    shader can index by number."""
    colors, data = load_colors(path)
    ramps = {}
    width = None
    for name, entries in data["ramps"].items():
        if width is None:
            width = len(entries)
        assert len(entries) == width, \
            "ramp %r is %d long, expected %d" % (name, len(entries), width)
        for entry in entries:
            assert entry in colors, "%r is not a palette color" % (entry,)
        ramps[name] = [colors[entry] for entry in entries]
    return ramps


def load_fx_ramp(path, name):
    """One effect ramp from data/palette.json, hottest entry first, as a list
    of RGB tuples.

    Resolves against colors AND ui_colors together, which the ship role map
    does not do. That is deliberate rather than sloppy: the hot end of a fire
    is the same orange every critical readout and collision chip in the
    interface already wears, so a burning ship and the damage report line
    about it are one colour. Naming a second one would be inventing a colour,
    which CLAUDE.md 3.1 forbids.

    A ramp naming a colour neither table has raises here, rather than writing
    an off palette pixel."""
    colors, data = load_colors(path)
    for entry_name, value in data.get("ui_colors", {}).items():
        text = value.lstrip("#")
        colors[entry_name] = (int(text[0:2], 16), int(text[2:4], 16),
                              int(text[4:6], 16))
    entries = data["fx"][name]
    for entry in entries:
        assert entry in colors, "%r is not a palette color" % (entry,)
    return [colors[entry] for entry in entries]


# ---- ordered dithering ------------------------------------------------------

# The 4x4 ordered matrix every dither in this repo uses.
BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def bayer(x, y):
    """The ordered dither threshold at a pixel, from 0 to just under 1."""
    return (BAYER[y & 3][x & 3] + 0.5) / 16.0


def ramp_index(near, ramp, reach, dither):
    """Which entry of a hottest first ramp a brightness lands on.

    `near` is 1 at the brightest and 0 where the effect has run out. `reach` is
    how far down the ramp the coldest lit pixel is allowed to go, so a value
    below len(ramp) keeps an effect off the cold end entirely; sliding it with
    age is how fire turns into smoke without a second field to track.

    `dither` is the pixel's bayer() threshold. It is added before truncating, so
    a value falling between two entries lands on the nearer one more often than
    the further one, and a smooth field on a handful of colours comes out
    stippled rather than banded into rings.

    Returns an index past the end of the ramp for anything too cold to paint,
    so callers test against len(ramp) rather than being handed a colour they
    then have to decide about."""
    return int((1.0 - near) * reach + dither)


# ---- masks ------------------------------------------------------------------


def rect_mask(w, h, cuts=(0, 0, 0, 0)):
    """A rectangle with 45 degree corner cuts (top left, top right, bottom
    left, bottom right), the panel shape the sheets are built from."""
    tl, tr, bl, br = cuts
    m = [[True] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if (x + y < tl or (w - 1 - x) + y < tr
                    or x + (h - 1 - y) < bl or (w - 1 - x) + (h - 1 - y) < br):
                m[y][x] = False
    return m


def octagon_mask(r):
    size = 2 * r + 1
    m = [[False] * size for _ in range(size)]
    for y in range(-r, r + 1):
        w = r if abs(y) <= r // 2 else r - (abs(y) - r // 2)
        for x in range(-w, w + 1):
            m[y + r][x + r] = True
    return m


def circle_mask(r):
    size = 2 * r + 1
    return [[math.hypot(x - r, y - r) <= r + 0.4 for x in range(size)]
            for y in range(size)]


def rings(mask, width):
    """Boundary depth per pixel: 1 on the outermost ring, up to width; 0 for
    anything deeper. Drives the constant width outlines."""
    h, w = len(mask), len(mask[0])
    depth = [[0] * w for _ in range(h)]
    ring = []
    for y in range(h):
        for x in range(w):
            if not mask[y][x]:
                continue
            if (x == 0 or y == 0 or x == w - 1 or y == h - 1
                    or not mask[y][x - 1] or not mask[y][x + 1]
                    or not mask[y - 1][x] or not mask[y + 1][x]):
                depth[y][x] = 1
                ring.append((x, y))
    for level in range(2, width + 1):
        grown = []
        for (x, y) in ring:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and mask[ny][nx] \
                        and depth[ny][nx] == 0:
                    depth[ny][nx] = level
                    grown.append((nx, ny))
        ring = grown
    return depth


# ---- painter ----------------------------------------------------------------


class Px:
    """A pixel art painter: flat fills, hard outlines, no anti aliasing.

    Square by default, because the ship sheets are square atlases. Pass a
    height for the oblong canvases the UI plates need; everything else on the
    class works the same either way, which is why this grew a second dimension
    rather than the UI getting a painter of its own (CLAUDE.md 4.1)."""

    def __init__(self, size, background=(0, 0, 0), height=None, alpha=255):
        self.size = size
        self.height = size if height is None else height
        bg = (background[0], background[1], background[2], alpha)
        self.px = [bg] * (self.size * self.height)

    def get(self, x, y):
        return self.px[y * self.size + x]

    def put(self, x, y, rgb, alpha=255):
        """Alpha is opaque unless asked otherwise. The ship sheets never use
        it; the UI plates do, because a notched corner has to let the wall
        behind it show rather than painting a black triangle over it."""
        if 0 <= x < self.size and 0 <= y < self.height:
            self.px[y * self.size + x] = (rgb[0], rgb[1], rgb[2], alpha)

    def fill(self, rect, rgb):
        x0, y0, x1, y1 = rect
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, rgb)

    def shape(self, x0, y0, mask, fill, line, width=1):
        """A filled mask with a constant width outline."""
        depth = rings(mask, width)
        for y, row in enumerate(mask):
            for x, on in enumerate(row):
                if on:
                    self.put(x0 + x, y0 + y, line if depth[y][x] else fill)

    def frame(self, x0, y0, mask, line, width=1):
        """Only the outline ring of a mask; the fill underneath shows."""
        depth = rings(mask, width)
        for y, row in enumerate(mask):
            for x, on in enumerate(row):
                if on and depth[y][x]:
                    self.put(x0 + x, y0 + y, line)

    def stamp(self, x0, y0, mask, rgb):
        for y, row in enumerate(mask):
            for x, on in enumerate(row):
                if on:
                    self.put(x0 + x, y0 + y, rgb)

    def hline(self, x, y, length, rgb, t=1):
        self.fill((x, y, x + length, y + t), rgb)

    def vline(self, x, y, length, rgb, t=1):
        self.fill((x, y, x + t, y + length), rgb)

    def dots(self, x, y, count, step, rgb, vertical=False, w=1, h=1):
        for i in range(count):
            dx = x + (0 if vertical else i * step)
            dy = y + (i * step if vertical else 0)
            self.fill((dx, dy, dx + w, dy + h), rgb)

    def rivet_row(self, x, y, count, step, rgb, vertical=False):
        """Single pixel rivet dots along a plate edge, the R1 signature."""
        self.dots(x, y, count, step, rgb, vertical=vertical)

    def dash(self, x, y, length, rgb, vertical=False, on=2, off=2):
        """A dashed 1px border run, the stitched edge on the R1 red parts."""
        i = 0
        while i < length:
            seg = min(on, length - i)
            if vertical:
                self.fill((x, y + i, x + 1, y + i + seg), rgb)
            else:
                self.fill((x + i, y, x + i + seg, y + 1), rgb)
            i += on + off

    def ribs(self, rect, a, b, period=2, vertical=False):
        """Ladder of alternating bars: engine blocks and vents in the sheets.
        Horizontal bars by default; vertical=True gives columns."""
        x0, y0, x1, y1 = rect
        for y in range(y0, y1):
            for x in range(x0, x1):
                k = (x - x0) if vertical else (y - y0)
                self.put(x, y, a if (k // period) % 2 == 0 else b)

    def dither(self, rect, a, b):
        """Checkerboard mix of two colors: the R6 glow falloff."""
        x0, y0, x1, y1 = rect
        for y in range(y0, y1):
            for x in range(x0, x1):
                self.put(x, y, a if (x + y) % 2 == 0 else b)

    def dither_mask(self, x0, y0, mask, a, b):
        for y, row in enumerate(mask):
            for x, on in enumerate(row):
                if on:
                    self.put(x0 + x, y0 + y, a if (x0 + x + y0 + y) % 2 == 0 else b)

    def speckle(self, rect, pairs, density, rng):
        """Single pixel wear: nudge pixels whose color has a partner one step
        away in the palette (R1's 76 to 75 grays). pairs maps color to its
        worn variant; both must be palette colors."""
        x0, y0, x1, y1 = rect
        for _ in range(int((x1 - x0) * (y1 - y0) * density)):
            x = rng.randint(x0, x1 - 1)
            y = rng.randint(y0, y1 - 1)
            worn = pairs.get(self.get(x, y)[:3])
            if worn:
                self.put(x, y, worn)

    def bevel(self, dark, light_by_fill, shade_by_fill=None):
        """Top lit bevel, the way all the sheets shade: a fill pixel with a
        dark line above or to its left takes the light ridge color for that
        fill; one with a dark line below or to its right takes the shade.
        One pass after all lines are drawn; fills stay flat elsewhere."""
        shade_by_fill = shade_by_fill or {}
        size, height = self.size, self.height
        snapshot = list(self.px)

        def at(x, y):
            if 0 <= x < size and 0 <= y < height:
                return snapshot[y * size + x][:3]
            return None

        for y in range(height):
            for x in range(size):
                fill = snapshot[y * size + x][:3]
                lit = light_by_fill.get(fill)
                if lit and (at(x, y - 1) in dark or at(x - 1, y) in dark):
                    self.put(x, y, lit)
                    continue
                shaded = shade_by_fill.get(fill)
                if shaded and (at(x, y + 1) in dark or at(x + 1, y) in dark):
                    self.put(x, y, shaded)

    def save(self, path, scale=1):
        """Write the canvas as PNG, optionally nearest-neighbour upscaled.
        The sheets are authored at their reference resolution (128) and
        exported 2x so every logical pixel stays a fat 2x2 block, the chunk
        the R1 and R6 sheets are built from."""
        out_w = self.size * scale
        out_h = self.height * scale
        rows = []
        for y in range(out_h):
            row = bytearray([0])
            for x in range(out_w):
                row += bytes(self.px[(y // scale) * self.size + (x // scale)])
            rows.append(bytes(row))
        raw = b"".join(rows)

        def chunk(tag, data):
            return (struct.pack(">I", len(data)) + tag + data
                    + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", struct.pack(">IIBBBBB", out_w, out_h,
                                            8, 6, 0, 0, 0))
               + chunk(b"IDAT", zlib.compress(raw, 9))
               + chunk(b"IEND", b""))
        with open(path, "wb") as f:
            f.write(png)
        import os
        print("wrote %s" % os.path.basename(path))

    def parity(self, diffuse):
        """Make every lit pixel equal its diffuse pixel, the R6 law that a
        glowing pixel glows with its own painted color. Run after the
        diffuse's bevel pass so ridges carry into the glow."""
        for i, px in enumerate(self.px):
            if px[:3] != (0, 0, 0):
                self.px[i] = diffuse.px[i]


# ---- verification -----------------------------------------------------------


def verify(diffuse, lights, engines, palette, rects, tex,
           background=(0, 0, 0), lit_budget=(0.0008, 0.02)):
    """The gates every painted ship passes before anything is written:
    palette exactness against data/palette.json, the lit pixel budget, the
    engine layer being a subset of the combined lights map, and every
    painted pixel sitting inside its atlas rect.

    Pure black is allowed on the emissive maps because it is their empty
    value, not a painted color."""

    def offenders(canvas, allowed):
        return {px[:3] for px in canvas.px if px[:3] not in allowed}

    bad = offenders(diffuse, palette | {background})
    assert not bad, "off palette diffuse colors: %r" % (bad,)
    bad = offenders(lights, palette | {(0, 0, 0)})
    bad |= offenders(engines, palette | {(0, 0, 0)})
    assert not bad, "off palette light colors: %r" % (bad,)

    lit = sum(1 for px in lights.px if px[:3] != (0, 0, 0))
    ratio = lit / float(tex * tex)
    assert lit_budget[0] < ratio < lit_budget[1], \
        "lights budget off: %d px (%.3f%%)" % (lit, ratio * 100)

    for i, px in enumerate(engines.px):
        if px[:3] != (0, 0, 0):
            assert lights.px[i] == px, "engine map is not a subset of lights"

    def contained(canvas, name, empty):
        for i, px in enumerate(canvas.px):
            if px[:3] == empty:
                continue
            x, y = i % tex, i // tex
            if not any(x0 <= x < x1 and y0 <= y < y1
                       for (x0, y0, x1, y1) in rects):
                raise AssertionError(
                    "%s pixel (%d, %d) outside every atlas rect" % (name, x, y))

    contained(diffuse, "diffuse", background)
    contained(lights, "lights", (0, 0, 0))
    contained(engines, "engines", (0, 0, 0))
    print("verified: %d colors, %d lit px (%.2f%% of atlas)" % (
        len({px[:3] for px in diffuse.px}), lit, ratio * 100))


# ---- mesh -------------------------------------------------------------------


class Obj:
    """OBJ writer with texture coordinates."""

    def __init__(self, mesh_dir):
        self.mesh_dir = mesh_dir
        self.v = []
        self.vt = []
        self.vn = []
        self.f = []

    def vert(self, x, y, z):
        self.v.append((x, y, z))
        return len(self.v)

    def uv(self, u, w):
        self.vt.append((u, w))
        return len(self.vt)

    def normal(self, x, y, z):
        self.vn.append((x, y, z))
        return len(self.vn)

    def tri(self, a, b, c, n, ta, tb, tc):
        self.f.append(((a, ta, n), (b, tb, n), (c, tc, n)))

    def write(self, name, comment):
        import os
        one_piece(self.v, self.f, name)
        path = os.path.join(self.mesh_dir, name)
        with open(path, "w") as f:
            f.write("# %s\n# Generated by tools. Edit the generator script.\n"
                    % comment)
            for v in self.v:
                f.write("v %.6f %.6f %.6f\n" % v)
            for t in self.vt:
                f.write("vt %.6f %.6f\n" % t)
            for n in self.vn:
                f.write("vn %.6f %.6f %.6f\n" % n)
            for face in self.f:
                f.write("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % (
                    face[0][0], face[0][1], face[0][2],
                    face[1][0], face[1][1], face[1][2],
                    face[2][0], face[2][1], face[2][2]))
        print("wrote %s  (%d verts, %d tris)" % (name, len(self.v), len(self.f)))

    # ---- fragmentation ------------------------------------------------------

    def _face_centroid(self, face):
        xs = [self.v[c[0] - 1] for c in face]
        return tuple(sum(p[i] for p in xs) / 3.0 for i in range(3))

    def write_fragments(self, stem, count, comment):
        """Split this hull into `count` committed fragment meshes.

        This is what makes a wreck the wreck of THAT ship. The pieces are cut
        out of the hull's own triangles, so they carry its own atlas mapping and
        its own paint, and because each fragment keeps the hull's coordinates
        rather than being recentred, instancing all of them at the ship's
        transform reassembles the ship exactly. Flying them apart is then a
        matter of pushing each one away from where it already was, and the view
        can read that direction off the mesh itself.

        Faces are grouped by k means on their centroids, which gives contiguous
        lumps: a nacelle, a section of saucer, the stern. Slicing along an axis
        instead would cut every piece across the whole hull and the wreck would
        read as sawn rather than blown apart.

        Seeds are placed deterministically down the long axis and the iteration
        is fixed, so this writes the same files every run. A generator that
        rolled dice would churn the committed .obj files in every diff
        (CLAUDE.md section 2: the file on disk is the deliverable).
        """
        if not self.f:
            return []
        centroids = [self._face_centroid(face) for face in self.f]
        lo = [min(c[i] for c in centroids) for i in range(3)]
        hi = [max(c[i] for c in centroids) for i in range(3)]
        # Seeds spread along Z, which is the length of every hull here, nudged
        # alternately in X and Y so the clusters straddle the centreline
        # instead of stacking into slices.
        seeds = []
        for k in range(count):
            t = (k + 0.5) / count
            side = 1.0 if k % 2 == 0 else -1.0
            lift = 1.0 if (k // 2) % 2 == 0 else -1.0
            seeds.append([
                (lo[0] + hi[0]) * 0.5 + side * (hi[0] - lo[0]) * 0.28,
                (lo[1] + hi[1]) * 0.5 + lift * (hi[1] - lo[1]) * 0.22,
                lo[2] + (hi[2] - lo[2]) * t,
            ])
        groups = [[] for _ in range(count)]
        for _pass in range(12):
            groups = [[] for _ in range(count)]
            for index, c in enumerate(centroids):
                best, best_d = 0, None
                for k, s in enumerate(seeds):
                    d = sum((c[i] - s[i]) ** 2 for i in range(3))
                    if best_d is None or d < best_d:
                        best, best_d = k, d
                groups[best].append(index)
            for k, members in enumerate(groups):
                if not members:
                    continue
                for i in range(3):
                    seeds[k][i] = sum(centroids[m][i] for m in members) / len(members)

        written = []
        for k, members in enumerate(groups):
            if not members:
                continue
            written.append(self._write_group(
                "%s_frag_%d.obj" % (stem, len(written)), members,
                "%s, fragment %d of %d" % (comment, len(written), count)))
        return written

    def _write_group(self, name, face_indices, comment):
        """One fragment: the skin faces re indexed onto only the vertices they
        use, and the tear CAPPED so the piece is a closed chunk rather than a
        bent sheet of exterior paint.

        Two materials, split with usemtl so Godot's OBJ importer makes two
        surfaces: "skin" is the hull's own triangles and wears the ship's
        paint, "interior" is the caps and wears the shared burning interior
        (assets/materials/mat_debris_interior.tres). Uncapped, a tumbling
        plate vanished whenever its open side faced the camera, because the
        hull materials cull back faces; capped, there is no open side, and
        the inside of a blown open ship reads as something rather than as the
        absence the cut left behind.

        Caps are fanned from each boundary loop's centroid, and their UVs are
        the loop flattened onto its own dominant plane and spread over the
        interior texture, so every cap samples a patch of it rather than one
        texel. A loop from a k means group can be ragged; a fan from the
        centroid tolerates that, and debris is the one place a fold or a
        sliver reads as damage rather than as a bug."""
        import os
        vmap, tmap, nmap = {}, {}, {}
        verts, uvs, norms, faces = [], [], [], []

        def take(table, mapping, source, index):
            if index not in mapping:
                table.append(source[index - 1])
                mapping[index] = len(table)
            return mapping[index]

        for fi in face_indices:
            corners = []
            for c in self.f[fi]:
                corners.append((
                    take(verts, vmap, self.v, c[0]),
                    take(uvs, tmap, self.vt, c[1]),
                    take(norms, nmap, self.vn, c[2])))
            faces.append(corners)

        cap_faces = self._cap(verts, uvs, norms, faces)

        path = os.path.join(self.mesh_dir, name)
        with open(path, "w") as f:
            f.write("# %s\n# Generated by tools. Edit the generator script.\n" % comment)
            for v in verts:
                f.write("v %.6f %.6f %.6f\n" % v)
            for t in uvs:
                f.write("vt %.6f %.6f\n" % t)
            for n in norms:
                f.write("vn %.6f %.6f %.6f\n" % n)
            f.write("usemtl skin\n")
            for face in faces:
                f.write("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % (
                    face[0][0], face[0][1], face[0][2],
                    face[1][0], face[1][1], face[1][2],
                    face[2][0], face[2][1], face[2][2]))
            if cap_faces:
                f.write("usemtl interior\n")
                for face in cap_faces:
                    f.write("f %d/%d/%d %d/%d/%d %d/%d/%d\n" % (
                        face[0][0], face[0][1], face[0][2],
                        face[1][0], face[1][1], face[1][2],
                        face[2][0], face[2][1], face[2][2]))
        print("wrote %s  (%d verts, %d skin + %d cap tris)"
              % (name, len(verts), len(faces), len(cap_faces)))
        return name

    def _cap(self, verts, uvs, norms, faces):
        """Close every tear in a fragment: find the boundary loops, fan each
        from its centroid, and give the fans UVs across the interior texture.

        Appends the vertices, UVs and normals it needs to the caller's tables
        and returns the cap faces. DOUBLE SIDED: each fan is emitted in both
        windings, so however a plate tumbles, its torn face is drawn. The two
        copies are coplanar but only one passes back face culling at a time,
        so they never fight."""
        import collections
        edges = collections.Counter()
        for face in faces:
            trio = [c[0] for c in face]
            for a, b in ((trio[0], trio[1]), (trio[1], trio[2]),
                         (trio[2], trio[0])):
                edges[(min(a, b), max(a, b))] += 1
        boundary = [e for e, count in edges.items() if count == 1]
        if not boundary:
            return []

        # Walk the boundary edges into loops. Greedy: from any unused edge,
        # keep taking an unused edge that continues the chain. A ragged group
        # can leave a vertex on more than two boundary edges; taking any
        # continuation still closes A loop, and a closed wrong loop caps as
        # well as a right one.
        near = collections.defaultdict(list)
        for a, b in boundary:
            near[a].append((a, b))
            near[b].append((a, b))
        unused = set(boundary)
        loops = []
        while unused:
            first = unused.pop()
            loop = [first[0], first[1]]
            while True:
                step = None
                for e in near[loop[-1]]:
                    if e in unused:
                        step = e
                        break
                if step is None:
                    break
                unused.discard(step)
                loop.append(step[1] if step[0] == loop[-1] else step[0])
            # A walked loop ends back at its start; drop the repeat. A chain
            # that never closed is degenerate and is skipped below.
            if loop[0] == loop[-1]:
                loop = loop[:-1]
            if len(loop) >= 3:
                loops.append(loop)

        cap_faces = []
        for loop in loops:
            pts = [verts[i - 1] for i in loop]
            centre = tuple(sum(p[k] for p in pts) / len(pts) for k in range(3))
            ci = len(verts) + 1
            verts.append(centre)

            # The loop flattened onto its dominant plane, normalised to fill
            # the interior texture with a margin. Which plane is dominant
            # comes from the loop's own extents, so a cap through a deck is
            # mapped across the deck and a cap through a wall down the wall.
            lo = [min(p[k] for p in pts) for k in range(3)]
            hi = [max(p[k] for p in pts) for k in range(3)]
            spans = [hi[k] - lo[k] for k in range(3)]
            axes = sorted(range(3), key=lambda k: spans[k], reverse=True)[:2]

            def flat(p):
                out = []
                for k in axes:
                    span = max(spans[k], 1e-6)
                    out.append(0.06 + 0.88 * (p[k] - lo[k]) / span)
                return (out[0], out[1])

            uv_centre = len(uvs) + 1
            uvs.append(flat(centre))
            uv_ring = []
            for p in pts:
                uvs.append(flat(p))
                uv_ring.append(len(uvs))

            # One flat normal per side of the fan. Not accurate for a bent
            # loop and deliberately so: a torn edge lit as one plane reads as
            # a surface, and the interior texture carries the detail.
            n_up = len(norms) + 1
            norms.append((0.0, 1.0, 0.0))
            n_down = len(norms) + 1
            norms.append((0.0, -1.0, 0.0))

            count = len(loop)
            for i in range(count):
                a = loop[i]
                b = loop[(i + 1) % count]
                ta = uv_ring[i]
                tb = uv_ring[(i + 1) % count]
                cap_faces.append(((ci, uv_centre, n_up), (a, ta, n_up),
                                  (b, tb, n_up)))
                cap_faces.append(((ci, uv_centre, n_down), (b, tb, n_down),
                                  (a, ta, n_down)))
        return cap_faces


def uv_in(o, rect, u, w, tex):
    x0, y0, x1, y1 = rect
    return o.uv((x0 + (x1 - x0) * u) / tex, 1.0 - (y0 + (y1 - y0) * w) / tex)


def slab(o, outline, y0, y1, rect_top, rect_side, tex, rect_aft=None,
         rect_fore=None, aft_dot=-0.9, fore_dot=0.9):
    """Extrude an XZ polygon. Caps map planar into rect_top with the bow at
    the rect's bottom; walls map the rect_side strip, except walls facing
    aft or forward past the aft_dot / fore_dot thresholds, which take
    rect_aft and rect_fore when given, so engines can glow from behind and
    intakes read from the front. Swept trailing edges want a looser aft_dot.

    Winding: every triangle's cross product agrees with its outward vn, the
    OBJ convention every DCC tool writes. Anything else renders inside out
    in Godot: the SSD's directional light proved it, lighting the hull only
    once the winding matched the normals."""
    xs = [p[0] for p in outline]
    zs = [p[1] for p in outline]
    minx, maxx = min(xs), max(xs)
    minz, maxz = min(zs), max(zs)
    span_x = (maxx - minx) or 1.0
    span_z = (maxz - minz) or 1.0

    top, bot, tuv = [], [], []
    for (x, z) in outline:
        top.append(o.vert(x, y1, z))
        bot.append(o.vert(x, y0, z))
        tuv.append(uv_in(o, rect_top, (x - minx) / span_x,
                         (z - minz) / span_z, tex))

    up = o.normal(0, 1, 0)
    down = o.normal(0, -1, 0)
    for i in range(1, len(outline) - 1):
        o.tri(top[0], top[i], top[i + 1], up, tuv[0], tuv[i], tuv[i + 1])
        o.tri(bot[0], bot[i + 1], bot[i], down, tuv[0], tuv[i + 1], tuv[i])

    for i in range(len(outline)):
        j = (i + 1) % len(outline)
        (ax, az), (bx, bz) = outline[i], outline[j]
        ex, ez = bx - ax, bz - az
        ln = math.hypot(ex, ez) or 1.0
        # Outlines are wound clockwise seen from above, so the outward wall
        # normal is the edge direction rotated the other way.
        nz = ex / ln
        n = o.normal(-ez / ln, 0, nz)
        wall_rect = rect_side
        if rect_aft is not None and nz < aft_dot:
            wall_rect = rect_aft
        elif rect_fore is not None and nz > fore_dot:
            wall_rect = rect_fore
        ua = uv_in(o, wall_rect, 0.0, 1.0, tex)
        ub = uv_in(o, wall_rect, 1.0, 1.0, tex)
        uc = uv_in(o, wall_rect, 1.0, 0.0, tex)
        ud = uv_in(o, wall_rect, 0.0, 0.0, tex)
        o.tri(top[i], bot[i], bot[j], n, ud, ua, ub)
        o.tri(top[i], bot[j], top[j], n, ud, ub, uc)


def disc_outline(cx, cz, rx, rz, steps):
    return [(cx + math.sin(2 * math.pi * i / steps) * rx,
             cz + math.cos(2 * math.pi * i / steps) * rz) for i in range(steps)]


# ---- the R1 painting vocabulary ----------------------------------------------


class R1:
    """The R1 sheets' painting vocabulary, shared by every Federation hull.

    The frigate authored these marks and the cruiser needs the same ones, so
    they live here rather than being copied into a second painter
    (CLAUDE.md 4.1). Every colour is a role read from data/palette.json
    through the role map handed in, so a hull repaints by editing that map and
    nothing else: this class holds no hex values and never will.

    Construct one per painter, with that painter's role map and its seeded
    RNG, so the speckle stays deterministic and a rerun is an empty diff."""

    def __init__(self, roles, rng):
        self.r = roles
        self.rng = rng

    def erode(self, mask):
        depth = rings(mask, 1)
        return [[on and depth[y][x] == 0 for x, on in enumerate(row)]
                for y, row in enumerate(mask)]

    def two_tone(self, p, x0, y0, mask, fill, light, shadow, spark=None,
                 spark_prob=0.25):
        """The R1 blue-on-blue panel: no outline, a lit ridge on edges open to
        the top or left, a shadow on edges open to the bottom or right."""
        h, w = len(mask), len(mask[0])

        def inside(x, y):
            return 0 <= x < w and 0 <= y < h and mask[y][x]

        for y, row in enumerate(mask):
            for x, on in enumerate(row):
                if not on:
                    continue
                if not inside(x, y - 1) or not inside(x - 1, y):
                    c = light
                    if spark is not None and self.rng.random() < spark_prob:
                        c = spark
                elif not inside(x, y + 1) or not inside(x + 1, y):
                    c = shadow
                else:
                    c = fill
                p.put(x0 + x, y0 + y, c)

    def plate_island(self, p, x0, y0, mask):
        """A hull island: black silhouette outline, then the R1 ridge and
        shadow just inside it."""
        r = self.r
        p.shape(x0, y0, mask, r["plate"], line=r["outline"])
        self.two_tone(p, x0, y0, self.erode(mask), r["plate"],
                      r["plate_light"], r["plate_shadow"],
                      spark=r["accent"], spark_prob=0.08)

    def plate_panel(self, p, x0, y0, mask):
        """A plate-on-plate panel with no outline at all."""
        r = self.r
        self.two_tone(p, x0, y0, mask, r["plate"], r["plate_light"],
                      r["plate_shadow"], spark=r["accent"])

    def machinery(self, p, x0, y0, mask, dots=True):
        """R1 gray machinery: mid fill, black outline with rivet dots, a light
        top ridge and a dark bottom shadow inside."""
        r = self.r
        p.shape(x0, y0, mask, r["machinery"], line=r["outline"])
        self.two_tone(p, x0, y0, self.erode(mask), r["machinery"],
                      r["machinery_ridge"], r["machinery_shadow"])
        if dots:
            h, w = len(mask), len(mask[0])
            for x in range(2, w - 2, 3):
                if mask[0][x]:
                    p.put(x0 + x, y0 + 1, r["outline"])
                if mask[h - 1][x]:
                    p.put(x0 + x, y0 + h - 2, r["outline"])

    def ridge_ring(self, p, cx, cy, rad, light=None, shadow=None):
        """A raised ring seam on a plate: lit on its upper left arc, shaded on
        its lower right."""
        light = self.r["plate_light"] if light is None else light
        shadow = self.r["plate_shadow"] if shadow is None else shadow
        mask = octagon_mask(rad)
        depth = rings(mask, 1)
        for y, row in enumerate(mask):
            for x, on in enumerate(row):
                if on and depth[y][x]:
                    p.put(cx - rad + x, cy - rad + y,
                          light if (x - rad) + (y - rad) < 0 else shadow)

    def rivet_ring(self, p, cx, cy, rad, count, offset=0.0):
        """Silver rivet dots following a circular seam, one in four pale."""
        r = self.r
        for i in range(count):
            a = offset + 2.0 * math.pi * i / count
            color = r["rivet_pale"] if i % 4 == 3 else r["machinery_ridge"]
            p.put(int(cx + math.cos(a) * rad), int(cy + math.sin(a) * rad), color)

    def rivet_row(self, p, x, y, count, step=3, vertical=False):
        r = self.r
        for i in range(count):
            color = r["rivet_pale"] if i % 4 == 3 else r["machinery_ridge"]
            p.put(x + (0 if vertical else i * step),
                  y + (i * step if vertical else 0), color)

    def capsule(self, p, x, y, length, vertical=False):
        """A bright capsule strip with lighter end caps, the R1 accent."""
        r = self.r
        if vertical:
            p.vline(x, y, length, r["accent"])
            p.put(x, y, r["plate_light"])
            p.put(x, y + length - 1, r["plate_light"])
        else:
            p.hline(x, y, length, r["accent"])
            p.put(x, y, r["plate_light"])
            p.put(x + length - 1, y, r["plate_light"])

    def ladder(self, p, rect):
        """Light rungs on dark rails, the R1 vent block."""
        r = self.r
        x0, y0, x1, y1 = rect
        p.fill(rect, r["outline"])
        step = 0
        for y in range(y0 + 1, y1 - 1, 2):
            p.hline(x0 + 1, y, x1 - x0 - 2,
                    r["machinery_ridge"] if step % 2 == 0 else r["step"])
            step += 1

    def red_block(self, p, x0, y0, w, h):
        """R1 red machinery: red fill, alternating black dot border ON the
        red, dark red shading on the lower right."""
        r = self.r
        p.fill((x0, y0, x0 + w, y0 + h), r["red"])
        p.fill((x0 + w // 2, y0 + h // 2, x0 + w, y0 + h), r["red_dark"])
        p.fill((x0 + 1, y0 + h - 2, x0 + w, y0 + h), r["red_shadow"])
        p.fill((x0 + w - 2, y0 + 1, x0 + w, y0 + h), r["red_shadow"])
        for x in range(x0, x0 + w, 2):
            p.put(x, y0, r["outline"])
            p.put(x + 1 if (x + 1) < x0 + w else x, y0 + h - 1, r["outline"])
        for y in range(y0, y0 + h, 2):
            p.put(x0, y, r["outline"])
            p.put(x0 + w - 1, y + 1 if (y + 1) < y0 + h else y, r["outline"])

    def window_run(self, d, lights, x, y, count=2):
        """A short vertical run of window pixels, all lit."""
        for i in range(count):
            d.put(x, y + i, self.r["window"])
            lights.put(x, y + i, self.r["glow_window"])

    def engine_bell(self, d, layer, x0, y0, w, h):
        """The R1 engine bell: dashed red housing, silver ringed bell with a
        white plus specular, and the layered glow with its wide dark halo."""
        r = self.r
        self.red_block(d, x0, y0, w, h)
        cx, cy = x0 + w // 2, y0 + h // 2
        d.shape(cx - 4, cy - 4, octagon_mask(4), r["silver"],
                line=r["machinery_ridge"], width=1)
        d.put(cx, cy - 1, r["specular"])
        d.put(cx, cy + 1, r["specular"])
        d.put(cx - 1, cy, r["specular"])
        d.put(cx + 1, cy, r["specular"])
        d.put(cx, cy, r["machinery"])
        layer.stamp(x0 + 1, y0 + 1, rect_mask(w - 2, h - 2, (2, 2, 2, 2)),
                    r["glow_halo"])
        layer.stamp(cx - 4, cy - 4, octagon_mask(4), r["glow_mid"])
        layer.stamp(cx - 2, cy - 2, octagon_mask(2), r["glow_light"])
        layer.fill((cx - 1, cy - 1, cx + 1, cy + 1), r["glow_core"])


# ------------------------------------------------------------- one piece
# CLAUDE.md section 2.1. A hull is one piece, and that is measured rather than
# eyeballed: once as connectivity of the mesh, once as the silhouette it leaves
# at the identification size. Both run on every OBJ the tools write and, via
# tools/check_hulls.py, on every OBJ that is committed.

SILHOUETTE_PX = 60


def mesh_components(verts, faces, tol=1e-4, grow=0.01):
    """How many connected pieces a triangle list is.

    Triangles that share a vertex position (within `tol`) form a shell. A
    kitbashed hull is many shells that interpenetrate without sharing a
    vertex, so shells are then joined when their bounding boxes, grown by
    `grow` of the hull's largest extent (about one texel), touch. The count
    of what is left is the number of pieces."""
    keyed = {}
    alias = []
    for x, y, z in verts:
        k = (round(x / tol), round(y / tol), round(z / tol))
        alias.append(keyed.setdefault(k, len(keyed)))
    parent = list(range(len(keyed)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for face in faces:
        a = alias[face[0][0] - 1]
        for corner in face[1:]:
            b = alias[corner[0] - 1]
            ra, rb = find(a), find(b)
            if ra != rb:
                parent[ra] = rb
    boxes = {}
    for i, v in enumerate(verts):
        r = find(alias[i])
        lo, hi = boxes.setdefault(r, ([v[0], v[1], v[2]], [v[0], v[1], v[2]]))
        for k in range(3):
            lo[k] = min(lo[k], v[k])
            hi[k] = max(hi[k], v[k])
    if not boxes:
        return 0
    extent = max(max(hi[k] for _, hi in boxes.values()) - min(lo[k] for lo, _ in boxes.values()) for k in range(3))
    eps = extent * grow
    shells = list(boxes)
    sp = list(range(len(shells)))

    def sfind(i):
        while sp[i] != i:
            sp[i] = sp[sp[i]]
            i = sp[i]
        return i

    for i in range(len(shells)):
        lo_i, hi_i = boxes[shells[i]]
        for j in range(i + 1, len(shells)):
            lo_j, hi_j = boxes[shells[j]]
            if all(lo_i[k] - eps <= hi_j[k] and lo_j[k] - eps <= hi_i[k] for k in range(3)):
                ri, rj = sfind(i), sfind(j)
                if ri != rj:
                    sp[ri] = rj
    return len({sfind(i) for i in range(len(shells))})


def silhouette_blobs(verts, faces, px=SILHOUETTE_PX, min_blob=3):
    """How many separate blobs the hull leaves when its triangles are drawn
    from directly above into a px by px grid. Blobs under `min_blob` pixels are
    noise and ignored; anything else is a piece the eye will see as loose."""
    xs = [v[0] for v in verts]
    zs = [v[2] for v in verts]
    if not xs:
        return 0
    span = max(max(xs) - min(xs), max(zs) - min(zs)) or 1.0
    cx, cz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
    scale = (px - 2) / span

    def to_px(v):
        return ((v[0] - cx) * scale + px / 2, (v[2] - cz) * scale + px / 2)

    grid = bytearray(px * px)
    for face in faces:
        pts = [to_px(verts[c[0] - 1]) for c in face]
        x0, x1 = int(min(p[0] for p in pts)), int(max(p[0] for p in pts)) + 1
        y0, y1 = int(min(p[1] for p in pts)), int(max(p[1] for p in pts)) + 1
        (ax, ay), (bx, by), (qx, qy) = pts
        area = (bx - ax) * (qy - ay) - (qx - ax) * (by - ay)
        for y in range(max(0, y0), min(px, y1)):
            for x in range(max(0, x0), min(px, x1)):
                sx, sy = x + 0.5, y + 0.5
                w0 = (bx - sx) * (qy - sy) - (qx - sx) * (by - sy)
                w1 = (qx - sx) * (ay - sy) - (ax - sx) * (qy - sy)
                w2 = (ax - sx) * (by - sy) - (bx - sx) * (ay - sy)
                inside = (w0 >= 0 and w1 >= 0 and w2 >= 0) if area >= 0 else (w0 <= 0 and w1 <= 0 and w2 <= 0)
                if inside or abs(area) < 1e-9:
                    grid[y * px + x] = 1
    seen = bytearray(px * px)
    blobs = 0
    for start in range(px * px):
        if seen[start] or not grid[start]:
            continue
        stack = [start]
        seen[start] = 1
        size = 0
        while stack:
            i = stack.pop()
            size += 1
            x, y = i % px, i // px
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < px and 0 <= ny < px:
                        j = ny * px + nx
                        if grid[j] and not seen[j]:
                            seen[j] = 1
                            stack.append(j)
        if size >= min_blob:
            blobs += 1
    return blobs


def one_piece(verts, faces, name):
    """Refuse a hull that is not one piece, by either measure."""
    parts = mesh_components(verts, faces)
    blobs = silhouette_blobs(verts, faces)
    if parts != 1 or blobs != 1:
        raise SystemExit("%s is not one piece: %d mesh component(s), %d silhouette blob(s) at %d px"
                         % (name, parts, blobs, SILHOUETTE_PX))
    print("%s: one piece (%d px silhouette)" % (name, SILHOUETTE_PX))
