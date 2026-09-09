#!/usr/bin/env python3
"""The fleet's geometry kit: one implementation of every shape a hull is made of.

WHY THIS EXISTS.

`docs/17-starship-design-bible.md` describes six dialects by ten classes, and
the diorama page showed them. A page cannot be the authority for a shape the
game flies: CLAUDE.md section 2 wants a written `.obj` on disk, and section 4.1
wants one implementation of anything two places need. So the kit moved here,
the sixty hulls are generated from it by `tools/gen_fleet.py`, and the diorama
page loads what this writes rather than building its own.

WHAT A HULL IS HERE.

A `Hull` is a list of `Part`s. A part is a `Geo`, a triangle soup in its own
local space, plus a placement. A part names a ROLE, and the role plus the
direction a triangle faces decides which rectangle of the faction's shared
atlas it is painted from (`ATLAS` below). Nothing is painted here; this file
decides shape and texture coordinates, `tools/fleet/paint.py` decides colour.

CONVENTIONS, ALL THREE OF THEM.

- **The bow is +Z.** The committed hulls already point that way (the saucer of
  `hull_cruiser.obj` sits at positive z) and `hull_view.gd` frames the ship
  with +Z up the screen. The diorama page draws its bow at -Z, so a port from
  that source negates z. Up is +Y, starboard is +X.
- **Winding is computed, never asserted.** Every triangle's normal comes from
  its own cross product at emit time, so the winding and the normal cannot
  disagree. `shiplib.slab` had to say this in a comment because it built both
  by hand; here it is true by construction.
- **One world unit is `TEXELS_PER_UNIT` texels.** Atlas rectangles are sized to
  the part they wear so that a plate is about the same size on a pod, a wing
  and a hull, which is what kept the diorama's paint from stretching.
"""

import math

# Texels to a world unit. The atlas rectangles below are sized from this, so a
# 2.4 unit pod flank gets a rectangle about 58 texels long and its plates come
# out the size the plates on a 1.1 unit body do.
TEXELS_PER_UNIT = 24.0

# The logical atlas grid. Bigger than the 128 of a single hand painted hull
# (docs/17 section 10) because ONE atlas dresses a whole faction: ten hulls
# share these rectangles, so the grid holds a dozen part roles instead of one
# ship's worth. The export is still 2x nearest, so a texel is still a chunk.
TEX = 256
SCALE = 2


# ---------------------------------------------------------------- geometry ---

class Geo:
    """A triangle soup: vertices, and triangles as index triples.

    Every primitive below returns one of these centred on its own origin with
    the bow toward +Z. Transforms return `self` so a shape can be built in one
    expression: `box(1, 1, 2).rotate_x(HALF_PI).translate(0, 0, 3)`.
    """

    __slots__ = ("verts", "tris")

    def __init__(self, verts=None, tris=None):
        self.verts = list(verts or [])
        self.tris = list(tris or [])

    def copy(self):
        return Geo(list(self.verts), list(self.tris))

    def add(self, other):
        """Merge another soup into this one, reindexed."""
        base = len(self.verts)
        self.verts.extend(other.verts)
        self.tris.extend((a + base, b + base, c + base) for (a, b, c) in other.tris)
        return self

    def _map(self, fn):
        self.verts = [fn(v) for v in self.verts]
        return self

    def translate(self, x, y, z):
        return self._map(lambda v: (v[0] + x, v[1] + y, v[2] + z))

    def scale(self, sx, sy=None, sz=None):
        if sy is None:
            sy = sz = sx
        # A negative scale mirrors, which reverses winding; flip the triangles
        # back so the outward normal stays outward.
        if sx * sy * sz < 0:
            self.tris = [(a, c, b) for (a, b, c) in self.tris]
        return self._map(lambda v: (v[0] * sx, v[1] * sy, v[2] * sz))

    def rotate_x(self, r):
        c, s = math.cos(r), math.sin(r)
        return self._map(lambda v: (v[0], v[1] * c - v[2] * s, v[1] * s + v[2] * c))

    def rotate_y(self, r):
        c, s = math.cos(r), math.sin(r)
        return self._map(lambda v: (v[0] * c + v[2] * s, v[1], -v[0] * s + v[2] * c))

    def rotate_z(self, r):
        c, s = math.cos(r), math.sin(r)
        return self._map(lambda v: (v[0] * c - v[1] * s, v[0] * s + v[1] * c, v[2]))

    def bounds(self):
        if not self.verts:
            return (0.0, 0.0, 0.0), (0.0, 0.0, 0.0)
        lo = [min(v[i] for v in self.verts) for i in range(3)]
        hi = [max(v[i] for v in self.verts) for i in range(3)]
        return tuple(lo), tuple(hi)


def _quad(g, a, b, c, d):
    """Two triangles for a quad given in outward facing order."""
    g.tris.append((a, b, c))
    g.tris.append((a, c, d))


def box(w, h, d):
    """An axis aligned box centred on the origin."""
    return prism(w, h, d, 1.0, 1.0)


def prism(w, h, d, fore=1.0, aft=1.0):
    """A box tapered toward the bow (+Z) by `fore` and toward the stern by `aft`.

    This is the workhorse: a Terran secondary hull, a Kthaari head, a pod and a
    Vaelith beak are all one of these with different taper.
    """
    hw, hh, hd = w * 0.5, h * 0.5, d * 0.5
    g = Geo()
    for sz, sc in ((1.0, fore), (-1.0, aft)):
        for sy in (-1.0, 1.0):
            for sx in (-1.0, 1.0):
                g.verts.append((sx * hw * sc, sy * hh * sc, sz * hd))
    # index: fore face 0..3 (y-,x-),(y-,x+),(y+,x-),(y+,x+), aft face 4..7
    f00, f10, f01, f11 = 0, 1, 2, 3
    a00, a10, a01, a11 = 4, 5, 6, 7
    _quad(g, f00, f10, f11, f01)          # bow, facing +Z
    _quad(g, a10, a00, a01, a11)          # stern, facing -Z
    _quad(g, f01, f11, a11, a01)          # top
    _quad(g, a00, a10, f10, f00)          # bottom
    _quad(g, a00, f00, f01, a01)          # port, facing -X
    _quad(g, f10, a10, a11, f11)          # starboard, facing +X
    return g


def lathe(profile, segs=24):
    """Revolve an (radius, y) profile around the Y axis.

    The profile runs bottom to top and is closed by the caller giving radius 0
    at either end where a cap is wanted.
    """
    g = Geo()
    ring = []
    for i in range(segs):
        a = 2.0 * math.pi * i / segs
        ring.append((math.sin(a), math.cos(a)))
    for (r, y) in profile:
        for (sx, sz) in ring:
            g.verts.append((sx * r, y, sz * r))
    for j in range(len(profile) - 1):
        r0 = profile[j][0]
        r1 = profile[j + 1][0]
        for i in range(segs):
            k = (i + 1) % segs
            a = j * segs + i
            b = j * segs + k
            c = (j + 1) * segs + k
            d = (j + 1) * segs + i
            if r0 <= 1e-9 and r1 <= 1e-9:
                continue
            if r0 <= 1e-9:
                g.tris.append((a, c, d))
            elif r1 <= 1e-9:
                g.tris.append((a, b, c))
            else:
                _quad(g, a, b, c, d)
    return g


def disc(r, h, dome):
    """The Terran saucer: flat underside, a rim, a terrace and a dome.

    The same stepped profile the diorama used, so the shape a reviewer approved
    is the shape the game flies.
    """
    prof = [
        (0.0, -h * 0.5), (r * 0.55, -h * 0.5), (r * 0.9, -h * 0.35),
        (r, -h * 0.35), (r, h * 0.5), (r * 0.9, h * 0.5),
        (r * 0.88, h * 0.5 + dome * 0.35), (r * 0.55, h * 0.5 + dome * 0.35),
        (r * 0.5, h * 0.5 + dome * 0.8), (r * 0.25, h * 0.5 + dome),
        (0.0, h * 0.5 + dome),
    ]
    # Thirty six segments, the count the diorama lathed this profile at, so the
    # sentence above is true of the shape and not only of the profile.
    #
    # This was eighteen, on the argument that a hull is identified from above at
    # about forty pixels and the two are indistinguishable there. That argument
    # is sound about the tactical camera and wrong about everything else the
    # standard graphic set feeds (CLAUDE.md 3.2): the schematic is drawn at 256
    # pixels, where an eighteen sided saucer reads as an octagon, and a saucer
    # is the one shape a Terran hull is recognised by. It costs about three
    # hundred triangles on the ten Terran hulls and nothing anywhere else,
    # because this is the only dialect that lathes a disc.
    return lathe(prof, 36)


def extrude(points, thick):
    """Extrude a closed XZ polygon upward by `thick`, centred on y.

    `points` are (x, z) wound counter clockwise seen from above. Wings, loops
    and every flat plate in the fleet are one of these.
    """
    n = len(points)
    g = Geo()
    for (x, z) in points:
        g.verts.append((x, thick * 0.5, z))
    for (x, z) in points:
        g.verts.append((x, -thick * 0.5, z))
    for i in range(1, n - 1):
        g.tris.append((0, i, i + 1))                       # top
        g.tris.append((n, n + i + 1, n + i))               # bottom
    for i in range(n):
        j = (i + 1) % n
        _quad(g, i, n + i, n + j, j)
    return g


def _ring_band(g, outer, inner, thick):
    """Top, bottom and both walls between two matching rings of (x, z)."""
    n = len(outer)
    base = len(g.verts)
    for (x, z) in outer:
        g.verts.append((x, thick * 0.5, z))
    for (x, z) in inner:
        g.verts.append((x, thick * 0.5, z))
    for (x, z) in outer:
        g.verts.append((x, -thick * 0.5, z))
    for (x, z) in inner:
        g.verts.append((x, -thick * 0.5, z))
    ot, it, ob, ib = base, base + n, base + 2 * n, base + 3 * n
    for i in range(n):
        j = (i + 1) % n
        _quad(g, ot + i, it + i, it + j, ot + j)           # top face
        _quad(g, ob + j, ib + j, ib + i, ob + i)           # bottom face
        _quad(g, ot + j, ot + i, ob + i, ob + j)           # outer wall
        _quad(g, it + i, it + j, ib + j, ib + i)           # inner wall
    return g


def annulus(R, r, thick, segs=40):
    """A flat ring: the Vaelith loop, the Sarn belt seen from above."""
    outer = [(math.sin(2 * math.pi * i / segs) * R,
              math.cos(2 * math.pi * i / segs) * R) for i in range(segs)]
    inner = [(math.sin(2 * math.pi * i / segs) * r,
              math.cos(2 * math.pi * i / segs) * r) for i in range(segs)]
    return _ring_band(Geo(), outer, inner, thick)


def egg(R, r, thick, segs=40):
    """An annulus stretched toward the stern: the Vaelith carrier's loop."""
    def rad(a):
        return R * (1.0 + 0.22 * max(0.0, -math.cos(a)))
    outer, inner = [], []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        k = rad(a)
        outer.append((math.sin(a) * k, math.cos(a) * k))
        inner.append((math.sin(a) * k * (r / R), math.cos(a) * k * (r / R)))
    return _ring_band(Geo(), outer, inner, thick)


def horseshoe(R, r, thick, gap_deg, segs=40):
    """An annulus with a bite taken out of the stern: crescent and horseshoe.

    The arc runs from one lip round to the other and the inner arc comes back,
    so the two cut ends are capped and the result is a single closed shell.
    """
    gap = math.radians(gap_deg)
    span = 2 * math.pi - gap
    n = max(4, int(segs * span / (2 * math.pi)) + 1)
    outer, inner = [], []
    for i in range(n):
        a = gap * 0.5 + span * i / (n - 1) + math.pi
        outer.append((math.sin(a) * R, math.cos(a) * R))
        inner.append((math.sin(a) * r, math.cos(a) * r))
    g = Geo()
    for (x, z) in outer:
        g.verts.append((x, thick * 0.5, z))
    for (x, z) in inner:
        g.verts.append((x, thick * 0.5, z))
    for (x, z) in outer:
        g.verts.append((x, -thick * 0.5, z))
    for (x, z) in inner:
        g.verts.append((x, -thick * 0.5, z))
    ot, it, ob, ib = 0, n, 2 * n, 3 * n
    for i in range(n - 1):
        j = i + 1
        _quad(g, ot + i, it + i, it + j, ot + j)
        _quad(g, ob + j, ib + j, ib + i, ob + i)
        _quad(g, ot + j, ot + i, ob + i, ob + j)
        _quad(g, it + i, it + j, ib + j, ib + i)
    _quad(g, ot + 0, ob + 0, ib + 0, it + 0)               # one cut end
    _quad(g, it + n - 1, ib + n - 1, ob + n - 1, ot + n - 1)  # the other
    return g


def torus(R, r, ring_segs=24, tube_segs=6, arc_deg=360.0):
    """A tube bent round the Y axis, lying flat. The Sarn ring and its arch."""
    g = Geo()
    arc = math.radians(arc_deg)
    closed = arc_deg >= 359.9
    n = ring_segs if closed else ring_segs + 1
    for i in range(n):
        a = arc * i / (ring_segs if closed else ring_segs)
        cx, cz = math.sin(a) * R, math.cos(a) * R
        for j in range(tube_segs):
            b = 2 * math.pi * j / tube_segs
            rr = math.cos(b) * r
            g.verts.append((cx + math.sin(a) * rr, math.sin(b) * r,
                            cz + math.cos(a) * rr))
    for i in range(n if closed else n - 1):
        i2 = (i + 1) % n
        for j in range(tube_segs):
            j2 = (j + 1) % tube_segs
            _quad(g, i * tube_segs + j, i2 * tube_segs + j,
                  i2 * tube_segs + j2, i * tube_segs + j2)
    if not closed:
        for (end, flip) in ((0, False), (n - 1, True)):
            base = len(g.verts)
            cx = math.sin(arc * end / ring_segs) * R
            cz = math.cos(arc * end / ring_segs) * R
            g.verts.append((cx, 0.0, cz))
            for j in range(tube_segs):
                j2 = (j + 1) % tube_segs
                a, b = end * tube_segs + j, end * tube_segs + j2
                g.tris.append((base, b, a) if flip else (base, a, b))
    return g


def sphere(r, segs=12, rings=8):
    """A UV sphere: a Kthaari bulb head, a Bloom lobe."""
    prof = []
    for i in range(rings + 1):
        t = math.pi * i / rings
        prof.append((math.sin(t) * r, -math.cos(t) * r))
    return lathe(prof, segs)


def cylinder(r, h, segs=10):
    """A drum standing on Y: sensor drums, hubs, drive bells before rotation."""
    return lathe([(0.0, -h * 0.5), (r, -h * 0.5), (r, h * 0.5), (0.0, h * 0.5)],
                 segs)


def cone(r, h, segs=6):
    """A cone standing on Y, apex up. Rotate -90 about X to point it at the bow."""
    return lathe([(0.0, -h * 0.5), (r, -h * 0.5), (0.0, h * 0.5)], segs)


def facets(radius, kind="octa"):
    """A faceted solid for the Sarn: a cut diamond, a many faceted hull, a gem.

    Built as a lathe with few segments rather than a subdivided platonic, so the
    facet count is a number a designer can read rather than a subdivision level,
    and so every one of them is a closed shell by construction.
    """
    sides = {"diamond": 4, "facet": 8, "gem": 10}.get(kind, 8)
    waist = 1.0 if kind != "gem" else 0.92
    prof = [(0.0, -radius), (radius * waist, 0.0), (0.0, radius)]
    if kind == "gem":
        prof = [(0.0, -radius), (radius * 0.62, -radius * 0.45),
                (radius, 0.0), (radius * 0.62, radius * 0.45), (0.0, radius)]
    return lathe(prof, sides)


def truss(length, w):
    """A spine, drawn as a solid box and PAINTED as an open frame.

    Real rails were the first cut and they were wrong twice over. From directly
    above, which is the only angle this game shows, four thin rails read as a
    row of disconnected blocks with the modules floating between them, and they
    cost four times the triangles of the box that reads better. The lattice is
    a mark in the atlas (`truss` role), exactly as it is on the diorama page
    that was approved, and the silhouette stays continuous.
    """
    return box(w, w, length)


# ------------------------------------------------------------------ atlas ----
#
# Which rectangle of the faction atlas a triangle is painted from, by the role
# its part named and the direction it faces. Six directions collapse to four
# keys because a hull is symmetric about its centreline and its underside is
# never the star of a top down game: 'top' also serves the bottom, 'side' both
# flanks, 'fore' the bow and 'aft' the stern.
#
# Rectangles are (x0, y0, x1, y1) in the TEX grid, half open, and none of them
# overlap: `shiplib.verify` refuses a painted pixel outside the set, which is
# what stops a painter quietly bleeding one role into another.

# The size each rectangle wants, in texels, chosen from the size of the part it
# dresses at TEXELS_PER_UNIT so a plate comes out the same size everywhere. The
# packer below turns this into coordinates, so adding a role is one line here
# and never a hand placed rectangle that quietly overlaps its neighbour: the
# first cut of this table had three such overlaps and `verify` would have
# blamed the painter for them.
ATLAS_WANT = (
    # role,      key,      w,   h
    ("disc",     "top",     84,  84),   # the Terran saucer from above
    ("disc",     "side",    96,  12),   # its rim, the window band
    ("disc",     "aft",     96,  12),   # the impulse wall
    ("body",     "top",     52,  84),
    ("body",     "side",    96,  20),
    ("body",     "fore",    32,  24),   # the deflector
    ("body",     "aft",     32,  24),   # the engine wall
    ("pod",      "top",     18,  84),
    ("pod",      "side",    96,  20),
    ("pod",      "fore",    24,  20),   # the collector
    ("pod",      "aft",     24,  20),
    ("pod",      "inner",  96,  20),   # the flank a pod turns toward its twin
    ("pylon",    "top",     16,  44),
    ("pylon",    "side",    32,  44),
    ("wing",     "top",     88,  56),
    ("wing",     "side",    96,   8),
    ("ring",     "top",     64,  16),
    ("ring",     "side",    64,   8),
    ("head",     "top",     44,  44),
    ("head",     "side",    48,  24),
    ("head",     "fore",    24,  24),   # the eye
    ("greeble",  "top",     24,  24),
    ("greeble",  "side",    24,  24),
    ("cargo",    "top",     24,  24),
    ("cargo",    "side",    24,  24),
    ("bay",      "side",    24,  16),
    ("bay",      "fore",    16,  12),   # a lit bay mouth
    ("truss",    "side",    32,  32),
    ("organic",  "top",     56,  40),
    ("organic",  "side",    56,  40),
    ("glow",     "top",     24,  24),   # any face that is only light
)

## Which key stands in for a missing one. A hull is symmetric and a top down
## game rarely shows an underside, so four keys dress six directions.
ATLAS_FALLBACK = {"fore": "side", "aft": "side", "inner": "side",
                  "side": "top", "top": "side"}


def _pack(want, size, margin=2):
    """Shelf pack the wanted rectangles into a `size` grid, tallest first.

    Deterministic, and it cannot produce an overlap, which is the whole reason
    the layout is packed rather than written out.
    """
    out = {}
    rows = sorted(range(len(want)), key=lambda i: (-want[i][3], -want[i][2], i))
    x, y, shelf = margin, margin, 0
    for i in rows:
        role, key, w, h = want[i]
        if x + w + margin > size:
            x = margin
            y += shelf + margin
            shelf = 0
        if y + h + margin > size:
            raise SystemExit("atlas overflow: %s/%s does not fit" % (role, key))
        out.setdefault(role, {})[key] = (x, y, x + w, y + h)
        x += w + margin
        shelf = max(shelf, h)
    return out


ATLAS = _pack(ATLAS_WANT, TEX)
for _role, _keys in ATLAS.items():
    for _k in ("top", "side", "fore", "aft", "inner"):
        if _k not in _keys:
            _fb = ATLAS_FALLBACK[_k]
            while _fb not in _keys:
                _fb = ATLAS_FALLBACK[_fb]
            _keys[_k] = _keys[_fb]

ROLES = tuple(ATLAS)

## Every rectangle the atlas uses, for `shiplib.verify`'s containment check.
ALL_RECTS = tuple(sorted({r for role in ATLAS.values() for r in role.values()}))


def classify(nx, ny, nz, inner_side=0):
    """Which atlas key a face pointing this way is painted from.

    `inner_side` is -1 or +1 on a part that turns one flank toward the ship's
    centreline, which is how a pod's grille faces its twin and its plating
    faces the void. Everything else leaves it 0 and both flanks paint alike.
    """
    ax, ay, az = abs(nx), abs(ny), abs(nz)
    if ay >= ax and ay >= az:
        return "top"
    if ax >= az:
        if inner_side and (nx > 0) == (inner_side > 0):
            return "inner"
        return "side"
    return "fore" if nz > 0 else "aft"


# ------------------------------------------------------------------- hull ----

class Part:
    """One placed piece of a hull, and everything the atlas needs to dress it.

    `role` picks the atlas rectangles. `name` is what the ship systems display
    and the explode view call it. `heading` is the direction the wreck throws
    this piece, which the fragment cutter uses.
    """

    __slots__ = ("geo", "role", "name", "heading", "glow", "inner_side")

    def __init__(self, geo, role, name, heading=(0.0, 0.0, 0.0), glow=False,
                 inner_side=0):
        self.geo = geo
        self.role = role
        self.name = name
        self.heading = heading
        self.glow = glow
        self.inner_side = inner_side


class Hull:
    """A ship under construction: parts, in the order they were added."""

    def __init__(self, faction, cls):
        self.faction = faction
        self.cls = cls
        self.parts = []

    def part(self, geo, role, name, heading=(0.0, 0.0, 0.0), glow=False,
             inner_side=0):
        p = Part(geo, role, name, heading, glow, inner_side)
        self.parts.append(p)
        return p

    def pair(self, make, role, name, heading=(1.0, 0.0, 0.0), inner=False):
        """Add a port and a starboard copy of the same shape.

        `make(side)` returns the geometry for side -1 or +1, so a builder
        writes the shape once and the mirror is not a second chance to get it
        wrong. The name is prefixed the way `data/ships.json` names mounts.
        """
        out = []
        for side in (-1, 1):
            label = ("port " if side < 0 else "starboard ") + name
            h = (heading[0] * side, heading[1], heading[2])
            out.append(self.part(make(side), role, label, h,
                                 inner_side=(-side if inner else 0)))
        return out

    def bounds(self):
        lo = [1e9, 1e9, 1e9]
        hi = [-1e9, -1e9, -1e9]
        for p in self.parts:
            plo, phi = p.geo.bounds()
            for i in range(3):
                lo[i] = min(lo[i], plo[i])
                hi[i] = max(hi[i], phi[i])
        return tuple(lo), tuple(hi)

    def fit_footprint(self, size):
        """Scale the hull so its widest horizontal span is `size`.

        The widest span rather than the length, because the dialects disagree
        about which way a ship is long: a Terran frigate is a disc with pods
        either side and is wider than it is deep, while a Helion freighter is
        a spine. Normalising the footprint puts them in the same box, which is
        what the tactical camera and the 60 pixel silhouette both want.

        The mesh carries only a small part of the size story on purpose. The
        tactical view already scales a hull by its tonnage (`ship_rig.gd`), so
        a dreadnought is a big ship because it weighs a lot, not because its
        `.obj` is enormous.
        """
        lo, hi = self.bounds()
        span = max(hi[0] - lo[0], hi[2] - lo[2])
        if span <= 1e-6:
            return self
        k = size / span
        for p in self.parts:
            p.geo.scale(k)
        return self

    def centre(self):
        """Move the hull so its bounding box is centred on x and z.

        The tactical view turns a ship about its origin and the wreck throws
        fragments from it, so an off centre origin reads as a ship pivoting
        around a point outside itself.
        """
        lo, hi = self.bounds()
        dx = -(lo[0] + hi[0]) * 0.5
        dz = -(lo[2] + hi[2]) * 0.5
        for p in self.parts:
            p.geo.translate(dx, 0.0, dz)
        return self

    def sit(self, floor=0.0):
        """Put the lowest point of the hull at `floor`."""
        lo, _ = self.bounds()
        for p in self.parts:
            p.geo.translate(0.0, floor - lo[1], 0.0)
        return self

    def attachment(self, grow=None):
        """Is this hull one piece, and if not, which parts came adrift?

        CLAUDE.md section 2.1: every top level piece gets a bounding box grown
        by a texel, boxes that touch are joined, and the result must be one
        component. Run here rather than only at write time so a builder can be
        debugged by name instead of by a count.
        """
        if grow is None:
            grow = 1.0 / TEXELS_PER_UNIT
        boxes = []
        for p in self.parts:
            lo, hi = p.geo.bounds()
            boxes.append(([lo[i] - grow for i in range(3)],
                          [hi[i] + grow for i in range(3)]))
        parent = list(range(len(boxes)))

        def find(i):
            while parent[i] != i:
                parent[i] = parent[parent[i]]
                i = parent[i]
            return i

        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                (alo, ahi), (blo, bhi) = boxes[i], boxes[j]
                if all(alo[k] <= bhi[k] and blo[k] <= ahi[k] for k in range(3)):
                    ri, rj = find(i), find(j)
                    if ri != rj:
                        parent[ri] = rj
        groups = {}
        for i in range(len(boxes)):
            groups.setdefault(find(i), []).append(i)
        if len(groups) <= 1:
            return 1, []
        main = max(groups.values(), key=len)
        loose = [self.parts[i].name for g in groups.values() if g is not main
                 for i in g]
        return len(groups), loose

    # ---- emit ---------------------------------------------------------------

    def emit(self, obj):
        """Write every part into a `shiplib.Obj`, with atlas texture coordinates.

        A triangle's normal is its own cross product, so the winding and the
        normal agree by construction. Its texture coordinates are a flat
        projection along the axis it faces, normalised by the PART's bounding
        box, so the paint on a pod does not depend on how long the ship it is
        bolted to happens to be.
        """
        for p in self.parts:
            lo, hi = p.geo.bounds()
            span = [max(1e-6, hi[i] - lo[i]) for i in range(3)]
            rects = ATLAS[p.role]
            # One entry per unique vertex, texture coordinate and normal in this
            # part. Without the normal cache a flat sided hull writes one `vn`
            # per TRIANGLE, which is most of a hundred kilobyte .obj file and
            # nothing a renderer wants: the six faces of a box share six.
            vi = {}
            for (a, b, c) in p.geo.tris:
                va, vb, vc = p.geo.verts[a], p.geo.verts[b], p.geo.verts[c]
                ux, uy, uz = (vb[0] - va[0], vb[1] - va[1], vb[2] - va[2])
                wx, wy, wz = (vc[0] - va[0], vc[1] - va[1], vc[2] - va[2])
                nx = uy * wz - uz * wy
                ny = uz * wx - ux * wz
                nz = ux * wy - uy * wx
                ln = math.sqrt(nx * nx + ny * ny + nz * nz)
                if ln < 1e-12:
                    continue
                nx, ny, nz = nx / ln, ny / ln, nz / ln
                key = classify(nx, ny, nz, p.inner_side)
                x0, y0, x1, y1 = rects[key]
                nk = ("n", round(nx, 4), round(ny, 4), round(nz, 4))
                if nk not in vi:
                    vi[nk] = obj.normal(nx, ny, nz)
                n = vi[nk]
                idx = []
                for v in (va, vb, vc):
                    if key in ("top",):
                        u = (v[0] - lo[0]) / span[0]
                        w = 1.0 - (v[2] - lo[2]) / span[2]
                    elif key == "side":
                        u = (v[2] - lo[2]) / span[2]
                        w = 1.0 - (v[1] - lo[1]) / span[1]
                    else:
                        u = (v[0] - lo[0]) / span[0]
                        w = 1.0 - (v[1] - lo[1]) / span[1]
                    tk = (key, round(u, 5), round(w, 5))
                    if tk not in vi:
                        vi[tk] = obj.uv((x0 + (x1 - x0) * u) / TEX,
                                        1.0 - (y0 + (y1 - y0) * w) / TEX)
                    idx.append((v, vi[tk]))
                pv = []
                for (v, t) in idx:
                    vk = ("v", round(v[0], 6), round(v[1], 6), round(v[2], 6))
                    # membership first: `setdefault` would call `obj.vert` on
                    # every hit and leak a vertex per triangle corner, which is
                    # how the first cut of this emitted three times the mesh.
                    if vk not in vi:
                        vi[vk] = obj.vert(*v)
                    pv.append((vi[vk], t))
                obj.tri(pv[0][0], pv[1][0], pv[2][0], n,
                        pv[0][1], pv[1][1], pv[2][1])
        return obj


# ------------------------------------------------------------- class ladder --
#
# docs/02 section 2 gives the ladder and docs/17 section 9 says class is part
# count. This is that table as data: every faction builder reads the same row
# and spends it in its own dialect, which is what stops a fleet from being one
# ship at ten sizes.

CLASSES = (
    dict(id="frigate", name="Frigate", size=0.70, foot=3.80, pods=2,
         body=0, neck=0, spine=0.55, windows=1, mods=1, reg="206"),
    dict(id="destroyer", name="Destroyer", size=0.80, foot=4.02, pods=2,
         body=1, neck=1, spine=0.70, windows=1, mods=2, reg="318"),
    dict(id="light_cruiser", name="Light cruiser", size=0.90, foot=4.25, pods=2,
         body=1, neck=1, spine=0.90, windows=2, mods=2, reg="17"),
    dict(id="heavy_cruiser", name="Heavy cruiser", size=1.00, foot=4.47, pods=2,
         body=1, neck=1, spine=1.10, windows=2, mods=3, reg="22", pod_len=1.15),
    dict(id="battlecruiser", name="Battlecruiser", size=1.10, foot=4.70, pods=2,
         body=1, neck=1, spine=1.30, windows=2, mods=3, reg="61", pod_len=1.30,
         low=True),
    dict(id="battleship", name="Battleship", size=1.20, foot=4.92, pods=4,
         body=2, neck=1, spine=1.30, windows=3, mods=4, reg="74"),
    dict(id="dreadnought", name="Dreadnought", size=1.35, foot=5.20, pods=4,
         body=2, neck=1, spine=1.60, windows=3, mods=6, reg="1", pod_len=1.15),
    dict(id="carrier", name="Carrier", size=1.25, foot=5.03, pods=4,
         body=1, neck=1, spine=1.60, windows=3, mods=4, reg="41", bays=True),
    dict(id="freighter", name="Freighter", size=1.00, foot=4.81, pods=2,
         body=0, neck=0, spine=1.70, windows=1, mods=0, reg="900", cargo=8),
    dict(id="tender", name="Tender", size=1.00, foot=4.53, pods=2,
         body=0, neck=1, spine=1.30, windows=1, mods=1, reg="512", cargo=4,
         cranes=True),
)

CLASS_BY_ID = {c["id"]: c for c in CLASSES}

FACTIONS = ("terran", "kthaari", "vaelith", "sarn", "helion", "bloom")
