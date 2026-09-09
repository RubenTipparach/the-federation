#!/usr/bin/env python3
"""One painter, six skins: the shared atlas that dresses every hull in a fleet.

WHY THERE IS ONLY ONE OF THESE.

`tools/gen_ship_cruiser.py` hand places every mark on a 128 grid because it
dresses one hull. Sixty hulls cannot be authored that way, and six painters
that each knew how to draw a plate would be six chances for a plate to drift
(CLAUDE.md 4.1). So `shipkit.ATLAS` maps every face of every hull into a
rectangle chosen by the part's ROLE and the direction it faces, ten hulls of a
culture share one atlas, and this file paints the thirty one rectangles once
per faction. A Terran frigate and a Terran dreadnought are then the same
plates at different part counts, which is what docs/17 section 8 says a fleet
is.

WHAT A RECTANGLE IS PAINTED WITH.

`RECIPES` below has exactly one entry per authored rectangle, and it raises if
`shipkit.ATLAS_WANT` grows a role this file has not been told how to dress.
Most entries are a dict of options for `panel()`, the shared face painter:
plates in two tones with a lit top ridge and a shadowed bottom, an aztec sub
plate in a third tone, panel lines with a lit rivet at the head, and rows of
painted greebles one to five texels across. The rest are functions, for the
faces that are a picture rather than a field: the saucer seen from above, a
glow, the field grille, an organic hide, a truss.

THE THREE MAPS, AND THE PARITY LAW.

`diffuse` is what the hull is painted; `lights` is what it emits; `engines` is
the drive layer, a strict subset of `lights` so a throttle can be dimmed on its
own. A lit pixel glows with its OWN painted colour, which is the R6 law the
raider keeps, and here it is true by construction rather than by a pass
afterwards: `Brush.lit` writes the same colour into both maps. The one
deliberate break is a window, which is dark in the diffuse map and lit in the
lights map, because an unlit pane has to read as a hole in the plate rather
than as a painted dot.

THE LIT BUDGET IS THE REASON GLOWS ARE MOSTLY NOT LIT.

`shiplib.verify` allows at most two percent of the atlas to emit, which is
about thirteen hundred texels of this grid. The glow faces alone cover four
and a half thousand, so only the hot core of a gradient reaches the lights map
and the cooler bands are painted and dark. That is also how a deflector reads
as a dish with a hot centre instead of as a lamp.

COLOUR.

Nothing here is a hex value and nothing here is a faction name deciding a
colour. Every mark names a role, `data/palette.json` `ships` says what the
role is for each of the six cultures, and a repaint is that file and nothing
else (CLAUDE.md 3.1). The three glow ramps are stored hottest entry first, the
convention `shiplib`'s effect ramps already use, and every one of them is five
bands long so a glow reads the same on every hull and the lit budget does not
move with the culture.
"""

import math
import random

import shipkit as k
from shiplib import bayer, ramp_index, Px

# How far out from the centre of a glow face the emissive core reaches, as the
# gradient's own brightness. This is the knob that keeps the lights map inside
# `verify`'s budget: raising it dims the fleet, lowering it fails the gate.
GLOW_LIT = 0.72

# The yard number each culture stencils on its hulls. One atlas dresses ten
# classes, so this cannot be the ship's own registry: it is the yard's, and a
# per ship number would need a per ship atlas, which is the thing the shared
# atlas exists to avoid (docs/17 section 5.1).
YARD = {
    "terran": "170", "kthaari": "244", "vaelith": "318",
    "sarn": "451", "helion": "506", "bloom": "677",
}

# The window is the scale bar: one kind per culture, one size on every class,
# and because a face is projected at a fixed number of texels to the world
# unit, a pane drawn here is the same size on a frigate and on a dreadnought
# (docs/17 section 10). The panes are the texels a window is made of.
WINDOW_PANES = {
    "terran": ((0, 0), (2, 0)),                    # a pair
    "kthaari": ((0, 0), (1, 0), (2, 0)),           # a slit of three
    "vaelith": ((0, 0), (0, 1)),                   # an upright oval
    "sarn": ((0, 0), (1, 0), (0, 1), (1, 1)),      # a two by two hex
    "helion": ((0, 0),),                           # a single porthole
    "bloom": ((0, 0),),                            # a pore
}

# The 3x5 face the registry is stencilled in, one string of fifteen per digit
# read three across. Small enough that a number survives the 60 pixel test as
# a smudge in the right place, which is all a registry has to do at that size.
FONT = {
    "0": "111101101101111", "1": "010110010010111", "2": "111001111100111",
    "3": "111001111001111", "4": "101101111001001", "5": "111100111001111",
    "6": "111100111101111", "7": "111001001001001", "8": "111101111101111",
    "9": "111101111001111",
}


# ------------------------------------------------------------------- canvas --

class Face:
    """One atlas rectangle, addressed in its own coordinates and clipped to it.

    `Px` paints a whole canvas and knows nothing about the atlas, so without
    this every mark below would carry the rectangle's origin and check its own
    bounds, and the first one that forgot would bleed a plate into a
    neighbouring role. `verify`'s containment gate exists to catch exactly
    that, so the offset and the clip happen once, here, and a recipe is
    written as though its face were the whole world. This delegates to `Px`
    and paints nothing itself (CLAUDE.md 4.1).
    """

    __slots__ = ("_canvas", "_x0", "_y0", "w", "h")

    def __init__(self, canvas, rect):
        x0, y0, x1, y1 = rect
        self._canvas = canvas
        self._x0, self._y0 = x0, y0
        self.w, self.h = x1 - x0, y1 - y0

    def px(self, x, y, colour):
        if 0 <= x < self.w and 0 <= y < self.h:
            self._canvas.put(self._x0 + x, self._y0 + y, colour)

    def rect(self, x, y, w, h, colour):
        for j in range(y, y + h):
            for i in range(x, x + w):
                self.px(i, j, colour)

    def hline(self, x, y, length, colour):
        self.rect(x, y, length, 1, colour)

    def vline(self, x, y, length, colour):
        self.rect(x, y, 1, length, colour)

    def fill(self, colour):
        self.rect(0, 0, self.w, self.h, colour)


class Brush:
    """The three maps, one rectangle of them, plus the skin and the dice.

    Everything a recipe needs and nothing it does not: `b.d` is the diffuse
    face, `b.l` the lights, `b.e` the engines, `b.s` the role map and `b.rng`
    a generator seeded from the rectangle so a rerun writes the same file.
    """

    __slots__ = ("s", "rng", "faction", "d", "l", "e", "w", "h")

    def __init__(self, skin, faction, rng, rect, diffuse, lights, engines):
        self.s = skin
        self.faction = faction
        self.rng = rng
        self.d = Face(diffuse, rect)
        self.l = Face(lights, rect)
        self.e = Face(engines, rect)
        self.w, self.h = self.d.w, self.d.h

    def lit(self, x, y, colour, engine=False):
        """A pixel that glows with its own painted colour: the parity law of
        the R6 sheets, kept by construction. `engine` also puts it in the
        drive layer, which `verify` requires to be a subset of the lights."""
        self.d.px(x, y, colour)
        self.l.px(x, y, colour)
        if engine:
            self.e.px(x, y, colour)

    def pane(self, x, y, colour):
        """One texel of a window: dark in the diffuse map, lit in the lights.

        The one place parity is broken on purpose. A pane painted its own glow
        colour reads as a yellow dot with the lights off, and a hull with the
        lights off is what the shipyard and the wreck both show."""
        self.d.px(x, y, self.s["window_dark"])
        if colour is not None:
            self.l.px(x, y, colour)


# -------------------------------------------------------------------- marks --
#
# The shared vocabulary. Every one of these is a few texels, because docs/17
# section 6.2 sets the limit at the 60 pixel test: marks that turn to noise at
# identification size are marks that should not have been painted.

def hatch(b, x, y, length=1):
    b.d.rect(x, y, 2, 2, b.s["machinery_shadow"])
    b.d.px(x, y, b.s["machinery_ridge"])


def lifeboat(b, x, y, length=1):
    b.d.rect(x, y, 3, 2, b.s["machinery"])
    b.d.hline(x, y, 3, b.s["machinery_ridge"])
    b.d.px(x + 1, y + 1, b.s["machinery_shadow"])


def thruster(b, x, y, length=1):
    """An attitude quad: a housing with one warm nozzle texel."""
    b.d.rect(x, y, 3, 2, b.s["machinery_shadow"])
    b.d.px(x + 1, y, b.s["machinery"])
    b.d.px(x + 1, y + 1, b.s["glow_drive"][1])


def vent(b, x, y, length=1):
    b.d.rect(x, y, 5, 3, b.s["machinery"])
    for i in (0, 2, 4):
        b.d.vline(x + i, y, 3, b.s["machinery_shadow"])


def sensor(b, x, y, length=1):
    """A sensor dome, and the one greeble that carries a lit texel."""
    b.d.rect(x, y, 3, 3, b.s["machinery"])
    b.d.px(x, y, b.s["machinery_ridge"])
    b.d.px(x + 2, y + 2, b.s["machinery_shadow"])
    b.lit(x + 1, y + 1, b.s["window"])


def port(b, x, y, length=1):
    """A docking port: a square collar with a lit lip."""
    b.d.rect(x, y, 4, 4, b.s["machinery_shadow"])
    b.d.rect(x + 1, y + 1, 2, 2, b.s["machinery"])
    b.d.px(x + 1, y + 1, b.s["machinery_ridge"])


def phaser(b, x, y, length=6):
    """A weapon strip: a dark rail with emitters spaced along it."""
    b.d.hline(x, y, length, b.s["machinery_shadow"])
    b.d.hline(x, y + 1, length, b.s["machinery"])
    for i in range(1, length, 2):
        b.d.px(x + i, y, b.s["machinery_ridge"])


def pipe(b, x, y, length=8):
    b.d.hline(x, y, length, b.s["machinery_ridge"])
    b.d.hline(x, y + 1, length, b.s["machinery_shadow"])
    for i in range(1, length, 3):
        b.d.px(x + i, y + 1, b.s["machinery"])


def scorch(b, x, y, length=8):
    """A streak aft of a vent, thinning as it runs out."""
    for i in range(length):
        if i < length // 2 or not (i & 1):
            b.d.px(x + i, y, b.s["plate_shadow"])


def tick(b, x, y, length=1):
    b.d.px(x, y, b.s["mark"])
    b.d.px(x + 1, y, b.s["mark"])


def hazard(b, x, y, length=8):
    """The diagonal warning run a working hull wears at its clamps."""
    for i in range(length):
        b.d.rect(x + i, y, 1, 2,
                 b.s["stripe"] if ((i >> 1) & 1) else b.s["machinery_shadow"])


GREEBLES = {
    "hatch": hatch, "lifeboat": lifeboat, "thruster": thruster, "vent": vent,
    "sensor": sensor, "port": port, "phaser": phaser, "pipe": pipe,
    "scorch": scorch, "tick": tick, "hazard": hazard,
}


def greebles(b, rows):
    """Paint the rows a recipe asked for.

    A row is one mark at (x, y), or a run of them from x0 to x1 at a step, so
    a lifeboat row and a single sensor are written the same way."""
    for row in rows:
        mark = GREEBLES[row["kind"]]
        length = row.get("len", 1)
        if "step" in row:
            for x in range(row["x0"], row["x1"], row["step"]):
                mark(b, x, row["y"], length)
        else:
            mark(b, row["x"], row["y"], length)


def digits(b, x, y, text):
    """The yard number, stencilled in the mark role (docs/17 section 5.1)."""
    for ch in text:
        glyph = FONT.get(ch)
        if glyph:
            for i, on in enumerate(glyph):
                if on == "1":
                    b.d.px(x + i % 3, y + i // 3, b.s["mark"])
        x += 4


def window(b, x, y):
    """One window of the culture's own kind, its panes lit, dim or dark.

    Rolled per pane rather than per window, so a run of them reads as a deck
    with people in some of it rather than as a dotted line."""
    for (dx, dy) in WINDOW_PANES[b.faction]:
        roll = b.rng.random()
        colour = b.s["window"] if roll > 0.55 else \
            (b.s["window_dim"] if roll > 0.30 else None)
        b.pane(x + dx, y + dy, colour)


def windows(b, rows):
    for row in rows:
        for i in range(row["n"]):
            window(b, row["x"] + i * row["step"], row["y"])


# ------------------------------------------------------------------- plates --

def plate_field(b, cell, aztec=True):
    """The plating: two tones, a lit top ridge, a shadowed bottom and right.

    docs/17 section 6.1 is the whole recipe. The diorama page drew the ridge
    along the bottom row because its canvas ran the other way up; here row
    zero of a rectangle is the top of the face and the bow of a top down one,
    so the ridge goes where the light is.
    """
    s, rng = b.s, b.rng
    for y in range(0, b.h, cell):
        for x in range(0, b.w, cell):
            w = min(cell, b.w - x)
            h = min(cell, b.h - y)
            b.d.rect(x, y, w, h,
                     s["plate"] if rng.random() < 0.5 else s["plate_alt"])
            b.d.hline(x, y, w, s["plate_light"])
            b.d.hline(x, y + h - 1, w, s["plate_shadow"])
            b.d.vline(x + w - 1, y, h, s["plate_shadow"])
            if not aztec or w < 5 or h < 5:
                continue
            # The aztec: a sub plate one texel inside the seam, in the third
            # tone. It is the pearlescent flip flop at the resolution we have.
            if rng.random() < 0.55:
                ay = y + 1 + int(rng.random() * (h - 3))
                ah = 1 + int(rng.random() * 2)
                ax = x + 1 + int(rng.random() * 2)
                aw = max(1, w - 3 - int(rng.random() * 3))
                b.d.rect(ax, ay, min(aw, x + w - 1 - ax),
                         min(ah, y + h - 1 - ay), s["aztec"])
            # A panel line splitting the plate, with a lit rivet at its head.
            if rng.random() < 0.35:
                lx = x + 2 + int(rng.random() * (w - 4))
                b.d.vline(lx, y + 1, h - 2, s["plate_shadow"])
                b.d.px(lx + 1, y + 1, s["plate_light"])


def panel(b, cell=8, aztec=True, band=None, stripe=None, pennant=None,
          registry=None, mark=None, rows=(), panes=()):
    """A plated face, and every option a plated face has.

    Twenty three of the thirty one rectangles are one of these. `band` is a
    machinery run across the face, `stripe` and `pennant` are the livery
    (docs/17 section 5.2) across and along it, `registry` is where the yard
    number goes, `mark` is the hazard block, `rows` are greebles and `panes`
    are windows.
    """
    s = b.s
    b.d.fill(s["base"])
    plate_field(b, cell, aztec)
    if band is not None:
        y0, height = band
        b.d.rect(0, y0, b.w, height, s["machinery"])
        b.d.hline(0, y0 + height - 1, b.w, s["machinery_ridge"])
        for x in range(1, b.w, 3):
            b.d.px(x, y0, s["machinery_shadow"])
    if stripe is not None:
        b.d.hline(0, stripe, b.w, s["stripe"])
        b.d.hline(0, stripe + 1, b.w, s["stripe"])
    if pennant is not None:
        b.d.vline(pennant, 0, b.h, s["stripe"])
        b.d.vline(pennant + 1, 0, b.h, s["stripe"])
    if mark is not None:
        b.d.rect(mark[0], mark[1], mark[2], mark[3], s["hazard"])
    greebles(b, rows)
    windows(b, panes)
    if registry is not None:
        # A third entry shortens the number. A container is twenty four texels
        # across and the whole yard number would be half of it, which at
        # identification size is not a marking, it is a texture.
        text = YARD[b.faction]
        digits(b, registry[0], registry[1],
               text[:registry[2]] if len(registry) > 2 else text)


# -------------------------------------------------------------------- glows --

def glow_square(b, ramp_role):
    """A square gradient: brightest at the centre of the face, dimming outward
    in concentric bands.

    Square rather than linear because that is what a collector, a deflector
    and a drive bell all look like head on, and because it was asked for. The
    band boundaries are ordered dithered by `shiplib.bayer`, so five colours
    come out stippled rather than as five rings. Only the hot core emits: see
    the note on the budget at the top of this file.
    """
    ramp = b.s[ramp_role]
    reach = len(ramp) - 1
    for y in range(b.h):
        for x in range(b.w):
            dx = abs((x + 0.5) / b.w - 0.5) * 2.0
            dy = abs((y + 0.5) / b.h - 0.5) * 2.0
            near = 1.0 - max(dx, dy)
            i = min(reach, ramp_index(near, ramp, reach, bayer(x, y)))
            if near >= GLOW_LIT:
                b.lit(x, y, ramp[i], engine=True)
            else:
                b.d.px(x, y, ramp[i])


def glow(ramp_role):
    """A recipe for a face that is only light."""
    return lambda b: glow_square(b, ramp_role)


def grille(b):
    """The field grille a pod turns toward its twin: dark slats, a lit core.

    The tile is eight texels tall and repeats up the flank, so the same
    rectangle dresses a short pod and a long one without stretching. Two rows
    of the eight are the core, which is the whole of what this face
    contributes to the lit budget.
    """
    s = b.s
    ramp = s["glow_bow"]
    b.d.fill(s["plate_shadow"])
    # The core is the ramp's second band rather than its first. A field is a
    # steady light along a whole flank, and painting it the same white hot the
    # collector's centre is makes the pod read as ninety texels of exhaust.
    tone = (s["plate_shadow"], ramp[3], ramp[2], ramp[1], ramp[1],
            ramp[2], ramp[3], s["machinery_shadow"])
    for y in range(b.h):
        row = y % 8
        for x in range(b.w):
            if x % 4 == 3:
                b.d.px(x, y, ramp[4])            # the slat between the fields
            elif row in (3, 4):
                b.lit(x, y, tone[row], engine=True)
            else:
                b.d.px(x, y, tone[row])


# ----------------------------------------------------------------- pictures --

def disc_top(b):
    """The saucer seen from above, bow at the top of the rectangle.

    Fitted rather than tiled: this face is a sprite, painted once, and the
    only one in the atlas that knows what shape it is on. Concentric plating
    cut by ring seams and radial seams, greebles following the rings, a bridge
    forward of centre, the yard number aft, and the impulse block warm on the
    trailing edge.
    """
    s = b.s
    size = min(b.w, b.h)
    c = size / 2.0
    radius = c - 1.0
    b.d.fill(s["base"])
    for y in range(size):
        for x in range(size):
            dx, dy = x + 0.5 - c, y + 0.5 - c
            r = math.hypot(dx, dy)
            if r > radius:
                continue
            ring = int(r / (radius / 4.0))
            ang = math.atan2(dy, dx)
            spokes = 6 + ring * 4
            turn = (ang + math.pi) / (2.0 * math.pi) * spokes
            sector = int(turn)
            colour = s["plate_alt"] if (ring * 7 + sector * 3) % 5 < 2 \
                else s["plate"]
            rf = r / (radius / 4.0) - ring
            if rf < 0.14:
                colour = s["plate_shadow"]                  # ring seam
            elif rf > 0.86:
                colour = s["plate_light"]                   # lit ring edge
            if turn - sector < 0.08 and ring > 0:
                colour = s["plate_shadow"]                  # radial seam
            elif 0.2 < rf < 0.8 and (sector * 5 + ring) % 3 == 0 \
                    and ((x >> 1) + (y >> 1) + ring) % 5 == 0:
                colour = s["aztec"]
            b.d.px(x, y, colour)

    def at(rr, deg):
        a = math.radians(deg)
        return (int(round(c + math.cos(a) * rr)),
                int(round(c + math.sin(a) * rr)))

    for deg in range(0, 360, 15):
        x, y = at(radius * 0.74, deg + 7)
        hatch(b, x - 1, y - 1)
    for (a0, a1) in ((-150, -30), (30, 150)):
        for deg in range(a0, a1 + 1, 2):
            x, y = at(radius * 0.6, deg)
            b.d.px(x, y, s["machinery_ridge"] if (deg & 2)
                   else s["machinery_shadow"])
    for deg in (45, 135, 225, 315):
        x, y = at(radius * 0.9, deg)
        thruster(b, x - 1, y - 1)
    for deg in (0, 180):
        x, y = at(radius * 0.45, deg)
        sensor(b, x - 1, y - 1)
    for deg in (60, 120):
        x, y = at(radius * 0.86, deg)
        port(b, x - 2, y - 2)
    for deg in range(15, 360, 30):
        x, y = at(radius * 0.97, deg)
        tick(b, x, y)

    # The bridge, forward of centre, with its own windows.
    by = int(round(c - radius * 0.18))
    cx = int(c)
    for y in range(-4, 5):
        for x in range(-4, 5):
            if abs(x) + abs(y) <= 6:
                b.d.px(cx + x, by + y, s["machinery"])
    for x in range(-2, 3):
        b.d.px(cx + x, by - 4, s["machinery_ridge"])
    for (x, y) in ((-3, 0), (3, 0), (0, 3), (-2, 2), (2, 2)):
        b.pane(cx + x, by + y, s["window"])

    digits(b, cx - 6, int(round(c + radius * 0.42)), YARD[b.faction])
    for sx in (1, -1):
        b.d.rect(int(round(c + sx * radius * 0.55)) - (4 if sx < 0 else 0),
                 int(round(c - radius * 0.1)), 4, 3, s["hazard"])
    # The impulse block on the trailing edge, the one warm mark a saucer shows
    # from directly astern.
    ramp = s["glow_drive"]
    for x in range(-5, 6):
        for y in range(3):
            b.lit(cx + x, int(round(c + radius * 0.93)) + y, ramp[1],
                  engine=True)


def organic(b):
    """A grown hide rather than a built plate: blotches, a vein, pores.

    The Bloom has no panels to paint (docs/17 section 5.4 gives it no plates
    and no stripe), and every other culture has a part or two that grew. The
    marks wrap, so the face tiles.
    """
    s, rng = b.s, b.rng
    b.d.fill(s["base"])
    for _ in range(12):
        x, y = rng.randrange(b.w), rng.randrange(b.h)
        r = 1 + rng.randrange(3)
        colour = s["plate"] if rng.random() < 0.5 else s["plate_alt"]
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if abs(dx) + abs(dy) <= r:
                    b.d.px((x + dx) % b.w, (y + dy) % b.h, colour)
    vx = rng.randrange(b.w)
    for vy in range(b.h):
        b.d.px(vx, vy, s["aztec"])
        vx = (vx + (-1 if rng.random() < 0.5 else 1)) % b.w
    for _ in range(6):
        b.d.px(rng.randrange(b.w), rng.randrange(b.h), s["plate_shadow"])
    for _ in range(4):
        b.lit(rng.randrange(b.w), rng.randrange(b.h),
              s["window"] if rng.random() < 0.6 else s["hazard"])


def truss_frame(b):
    """A spine painted as an open frame.

    `shipkit.truss` is a solid box on purpose: four thin rails read as a row
    of disconnected blocks from directly above and cost four times the
    triangles. The lattice is therefore a mark, and it has to read the same
    whichever way the face is projected, because this one rectangle dresses
    every direction of a truss. So it is braced both ways.
    """
    s = b.s
    cell = 8
    b.d.fill(s["plate_shadow"])
    for y in range(0, b.h, cell):
        for x in range(0, b.w, cell):
            span = min(cell, b.w - x, b.h - y)
            for i in range(span):
                b.d.px(x + i, y + i, s["machinery_shadow"])
                b.d.px(x + span - 1 - i, y + i, s["machinery_shadow"])
            b.d.hline(x, y, min(cell, b.w - x), s["machinery"])
            b.d.vline(x, y, min(cell, b.h - y), s["machinery"])
    b.d.hline(0, b.h - 1, b.w, s["machinery"])
    b.d.vline(b.w - 1, 0, b.h, s["machinery"])
    for y in range(0, b.h, cell):
        for x in range(2, b.w, 4):
            b.d.px(x, y, s["machinery_ridge"])


def nozzle(b):
    """A pod's stern plate: a framed throat, ribbed, and not lit.

    The warp field is at the collector and along the inner flank; what a pod
    shows astern is machinery, which is what keeps the cool bow and warm aft
    of docs/17 section 5.4 from cancelling out on the same part.
    """
    s = b.s
    b.d.fill(s["machinery_shadow"])
    b.d.rect(2, 2, b.w - 4, b.h - 4, s["machinery"])
    b.d.hline(2, 2, b.w - 4, s["machinery_ridge"])
    for x in range(4, b.w - 4, 3):
        b.d.vline(x, 4, b.h - 8, s["machinery_shadow"])
    b.d.rect(b.w // 2 - 3, b.h // 2 - 2, 6, 4, s["plate_shadow"])
    tick(b, 3, b.h - 3)


def bay_wall(b):
    """A run of small bay mouths along a flank, each with a lit sill.

    The Sarn are described as many small bays and everything else has one or
    two, so the rectangle carries a run and a hull spends as much of it as it
    has bays.
    """
    s = b.s
    panel(b, cell=8, aztec=False, rows=[
        {"kind": "pipe", "x": 1, "y": b.h - 3, "len": b.w - 2},
    ])
    for x in range(2, b.w - 4, 8):
        b.d.rect(x, 2, 4, 3, s["machinery_shadow"])
        for i in range(4):
            b.lit(x + i, 4, s["window"])


# ------------------------------------------------------------------ recipes --
#
# One entry per rectangle `shipkit.ATLAS_WANT` authors. A dict is a set of
# options for `panel`; a callable paints the face itself. Adding a role to the
# kit therefore fails here until somebody says how it is dressed, which is
# better than it quietly coming out as bare gutter.

RECIPES = {
    # The saucer: a picture from above, a promenade wall, an impulse wall.
    ("disc", "top"): disc_top,
    ("disc", "side"): dict(cell=8, stripe=8, rows=[
        {"kind": "hatch", "y": 1, "x0": 3, "x1": 94, "step": 16},
        {"kind": "tick", "x": 46, "y": 10},
    ], panes=[{"x": 6, "y": 4, "n": 8, "step": 11}]),
    ("disc", "aft"): glow("glow_drive"),

    # The secondary hull: the longest runs of window in the fleet, because
    # this is where a crew lives.
    ("body", "top"): dict(cell=8, registry=(4, 6), rows=[
        {"kind": "vent", "y": 20, "x0": 4, "x1": 48, "step": 16},
        {"kind": "hatch", "y": 34, "x0": 6, "x1": 48, "step": 14},
        {"kind": "phaser", "x": 8, "y": 48, "len": 36},
        {"kind": "sensor", "x": 24, "y": 58},
        {"kind": "port", "x": 6, "y": 68},
        {"kind": "port", "x": 42, "y": 68},
        {"kind": "scorch", "x": 30, "y": 78, "len": 14},
    ], panes=[{"x": 6, "y": 26, "n": 4, "step": 10},
              {"x": 6, "y": 62, "n": 4, "step": 10}]),
    ("body", "side"): dict(cell=8, band=(3, 4), stripe=13, registry=(8, 15),
                           rows=[
        {"kind": "lifeboat", "y": 9, "x0": 30, "x1": 92, "step": 8},
        {"kind": "pipe", "x": 2, "y": 17, "len": 24},
        {"kind": "thruster", "x": 90, "y": 17},
        {"kind": "scorch", "x": 60, "y": 18, "len": 20},
    ], panes=[{"x": 4, "y": 9, "n": 3, "step": 7}]),
    ("body", "fore"): glow("glow_bow"),
    ("body", "aft"): glow("glow_drive"),

    # The pods: a pennant down the top, a grille inboard, a collector forward.
    ("pod", "top"): dict(cell=6, pennant=8, rows=[
        {"kind": "hatch", "y": 4, "x0": 2, "x1": 6, "step": 20},
        {"kind": "tick", "x": 13, "y": 40},
        {"kind": "tick", "x": 3, "y": 68},
    ]),
    ("pod", "side"): dict(cell=8, stripe=4, rows=[
        {"kind": "phaser", "x": 10, "y": 16, "len": 30},
        {"kind": "hatch", "y": 9, "x0": 6, "x1": 90, "step": 20},
        {"kind": "scorch", "x": 56, "y": 14, "len": 18},
    ], panes=[{"x": 60, "y": 10, "n": 3, "step": 8}]),
    ("pod", "fore"): glow("glow_bow"),
    ("pod", "aft"): nozzle,
    ("pod", "inner"): grille,

    # Pylons and wings: quiet, because they are mostly seen edge on.
    ("pylon", "top"): dict(cell=8, pennant=7, rows=[
        {"kind": "tick", "x": 2, "y": 20},
        {"kind": "hatch", "x": 11, "y": 32},
    ]),
    ("pylon", "side"): dict(cell=8, band=(18, 4), rows=[
        {"kind": "hatch", "y": 6, "x0": 4, "x1": 28, "step": 12},
        {"kind": "tick", "x": 14, "y": 36},
    ]),
    ("wing", "top"): dict(cell=8, registry=(6, 44), mark=(64, 8, 10, 4), rows=[
        {"kind": "phaser", "x": 10, "y": 20, "len": 40},
        {"kind": "hatch", "y": 32, "x0": 8, "x1": 80, "step": 18},
        {"kind": "port", "x": 60, "y": 40},
        {"kind": "sensor", "x": 26, "y": 46},
        {"kind": "scorch", "x": 40, "y": 52, "len": 20},
    ], panes=[{"x": 8, "y": 8, "n": 4, "step": 12}]),
    ("wing", "side"): dict(cell=8, aztec=False, stripe=3, rows=[
        {"kind": "tick", "y": 6, "x0": 8, "x1": 90, "step": 24},
    ]),

    # A ring, a belt, an arch: read edge on from above, so the top face does
    # the work and the wall is a band.
    ("ring", "top"): dict(cell=8, rows=[
        {"kind": "hatch", "y": 2, "x0": 4, "x1": 60, "step": 14},
        {"kind": "phaser", "x": 20, "y": 12, "len": 24},
    ], panes=[{"x": 6, "y": 7, "n": 5, "step": 12}]),
    ("ring", "side"): dict(cell=8, aztec=False, stripe=3, rows=[
        {"kind": "hatch", "y": 5, "x0": 6, "x1": 60, "step": 18},
    ]),

    # A head: armour, a visor, and one eye.
    ("head", "top"): dict(cell=6, band=(20, 5), mark=(30, 4, 8, 3), rows=[
        {"kind": "hatch", "y": 10, "x0": 4, "x1": 40, "step": 12},
        {"kind": "sensor", "x": 20, "y": 32},
        {"kind": "tick", "x": 6, "y": 40},
        {"kind": "port", "x": 34, "y": 34},
    ], panes=[{"x": 6, "y": 28, "n": 3, "step": 9}]),
    ("head", "side"): dict(cell=6, band=(8, 4), rows=[
        {"kind": "phaser", "x": 8, "y": 18, "len": 30},
        {"kind": "hatch", "y": 2, "x0": 4, "x1": 44, "step": 14},
    ], panes=[{"x": 6, "y": 14, "n": 3, "step": 10}]),
    ("head", "fore"): glow("glow_eye"),

    # The mounted kit: a dome, a drum, a hoop, a launcher. Small parts, so the
    # rectangle is machinery rather than plating.
    ("greeble", "top"): dict(cell=8, aztec=False, band=(4, 6), rows=[
        {"kind": "vent", "x": 3, "y": 12},
        {"kind": "hatch", "x": 16, "y": 14},
        {"kind": "tick", "x": 4, "y": 20},
    ]),
    ("greeble", "side"): dict(cell=8, aztec=False, band=(12, 5), rows=[
        {"kind": "pipe", "x": 2, "y": 4, "len": 20},
        {"kind": "hatch", "x": 17, "y": 19},
        {"kind": "tick", "x": 3, "y": 20},
    ]),

    # Cargo: hazard runs, because a container is meant to be seen and clamped.
    ("cargo", "top"): dict(cell=12, aztec=False, registry=(9, 10, 1), rows=[
        {"kind": "hazard", "x": 0, "y": 0, "len": 24},
        {"kind": "hatch", "y": 5, "x0": 4, "x1": 22, "step": 10},
        {"kind": "tick", "x": 18, "y": 20},
    ]),
    ("cargo", "side"): dict(cell=12, aztec=False, rows=[
        {"kind": "hazard", "x": 0, "y": 22, "len": 24},
        {"kind": "vent", "y": 4, "x0": 2, "x1": 22, "step": 7},
        {"kind": "lifeboat", "y": 14, "x0": 3, "x1": 21, "step": 6},
    ]),

    # Bays: a wall of mouths, and a lit mouth head on.
    ("bay", "side"): bay_wall,
    ("bay", "fore"): glow("glow_drive"),

    # The spine, and the things that grew.
    ("truss", "side"): truss_frame,
    ("organic", "top"): organic,
    ("organic", "side"): organic,

    # Whatever a hull makes of pure light. This rectangle dresses every face
    # of a glow part, and on every dialect most of those parts are collectors
    # and deflectors, so it burns with the bow ramp. The drives get faces of
    # their own, which is where the warm aft of docs/17 section 5.4 lives.
    ("glow", "top"): glow("glow_bow"),
}


# -------------------------------------------------------------------- paint --

def paint_faction(faction, palette_roles):
    """The three maps for one culture: diffuse, hull lights, engine glow.

    `palette_roles` is either the role map or the `(roles, allowed)` pair that
    `shiplib.load_palette` hands back, because callers pass both and a second
    loader here would be a second answer to the same question (CLAUDE.md 4.1).

    The canvases start pure black, which `shiplib.verify` treats as unpainted
    on all three maps, so a rectangle nobody dressed shows up as a hole in the
    atlas rather than as a plausible looking mistake.
    """
    skin = palette_roles[0] if isinstance(palette_roles, tuple) \
        else palette_roles
    diffuse, lights, engines = Px(k.TEX), Px(k.TEX), Px(k.TEX)
    index = k.FACTIONS.index(faction) if faction in k.FACTIONS else 0

    for (role, key, _w, _h) in k.ATLAS_WANT:
        recipe = RECIPES.get((role, key))
        if recipe is None:
            raise SystemExit(
                "no recipe for the %s/%s rectangle: tools/fleet/paint.py has "
                "to be told how a %s face is dressed" % (role, key, role))
        rect = k.ATLAS[role][key]
        # Seeded from the rectangle and the culture, so the plating differs
        # between the six and a rerun of any of them is an empty diff.
        rng = random.Random(1009 * (index + 1) + rect[0] * 31 + rect[1])
        brush = Brush(skin, faction, rng, rect, diffuse, lights, engines)
        if callable(recipe):
            recipe(brush)
        else:
            panel(brush, **recipe)
    return diffuse, lights, engines
