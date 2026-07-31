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
    """A pixel art painter: flat fills, hard outlines, no anti aliasing."""

    def __init__(self, size, background=(0, 0, 0)):
        self.size = size
        bg = (background[0], background[1], background[2], 255)
        self.px = [bg] * (size * size)

    def get(self, x, y):
        return self.px[y * self.size + x]

    def put(self, x, y, rgb):
        if 0 <= x < self.size and 0 <= y < self.size:
            self.px[y * self.size + x] = (rgb[0], rgb[1], rgb[2], 255)

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
        size = self.size
        snapshot = list(self.px)

        def at(x, y):
            if 0 <= x < size and 0 <= y < size:
                return snapshot[y * size + x][:3]
            return None

        for y in range(size):
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
        out = self.size * scale
        rows = []
        for y in range(out):
            row = bytearray([0])
            for x in range(out):
                row += bytes(self.px[(y // scale) * self.size + (x // scale)])
            rows.append(bytes(row))
        raw = b"".join(rows)

        def chunk(tag, data):
            return (struct.pack(">I", len(data)) + tag + data
                    + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

        png = (b"\x89PNG\r\n\x1a\n"
               + chunk(b"IHDR", struct.pack(">IIBBBBB", out, out,
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
