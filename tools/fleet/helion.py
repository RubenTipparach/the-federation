#!/usr/bin/env python3
"""The Helion Combine: a truss spine, a command block forward, standard modules
clamped along it and an engine cluster on outriggers aft (docs/17 section 8.5).

NOTHING IS HIDDEN. Every other dialect wraps its machinery in a hull; this one
bolts the machinery to a frame and leaves it in the open, so what a Helion is
made of is what a Helion looks like. There is no saucer, no wing and no warp
pod in the grammar: the drives are drums held off the spine on arms, and the
gap between them and the frame is the dialect. `shipkit.truss` draws the frame
as a box wearing the lattice as paint, which is what the diorama page does and
what reads at the identification size, so a spine here is one part and the
lattice is a mark in the atlas.

ONE TRUSS, TEN PLANS. The parts never change, so class cannot be spent on
having more KINDS of thing, the way a Kthaari spends it on a different wing.
It is spent instead on how the modules are clamped on, which is what `HEL_PLAN`
is for: a belly run under the spine, a run that alternates over and under it, a
pair at every station, a pair on the flanks, or all four sides filled. Add the
three command blocks (a cube, a wide bridge, a tall tower) and the two engine
clusters, and a frigate and a battlecruiser are different ships rather than one
ship at two sizes. The dreadnought alone ties a second truss under the first,
which is the one hull of the ten a player can name from its side view.

PORTED FROM `buildHelion` on the diorama page under the kit's three rules. The
page draws its bow at -Z and the game flies toward +Z, so every z read from
that source is negated once, at the point it is read. Winding is computed at
emit, so nothing here passes a normal. And the source's outrigger arrives as a
three axis Euler in ZYX order whose whole effect is to lay the arm along the
bearing of its drum, so it is written here as the single rotation about Z that
it amounts to.

WHERE THIS DEVIATES FROM THE SOURCE, and why. Three joins that read as solid
from a metre away are measurably two pieces under CLAUDE.md section 2.1, and
section 2.1 says to fix the placement rather than to drop the piece:

- Every module was seated to land exactly ON the spine's flank, which is a
  touch and not an overlap: a hull one arithmetic hair from being two pieces.
  The clamp distance is computed from the spine's own half width here instead,
  so a module always bites into it, and the containers of the cargo hulls are
  raised for the same reason.
- The tender's cranes hung clear under the bridge with daylight between. They
  are seated into its underside.
- The dreadnought's ties ran from the lower frame up the middle of the upper
  one and passed clean through a belly module on the way. They stop inside the
  module run instead, which is already clamped to the spine.
"""

import math

from shipkit import Hull, box, truss
from fleet.parts import (HALF_PI, bay_housing, cargo_run, crane, dome,
                         drive_drum, hoop)

## The plan table, keyed by class id exactly as the source keys it, so the two
## can be read side by side. `cmd` is which command block sits at the bow,
## `layout` how the modules clamp to the spine, `drums` how many drives hang
## off the outriggers, and `twin` is the dreadnought's second truss.
HEL_PLAN = {
    "frigate":       dict(cmd="cube",  layout="belly", drums=2),
    "destroyer":     dict(cmd="wide",  layout="belly", drums=2),
    "light_cruiser": dict(cmd="cube",  layout="alt",   drums=2),
    "heavy_cruiser": dict(cmd="tower", layout="pair",  drums=2),
    "battlecruiser": dict(cmd="wide",  layout="side",  drums=2),
    "battleship":    dict(cmd="tower", layout="quad",  drums=4),
    "dreadnought":   dict(cmd="tower", layout="quad",  drums=4, twin=True),
    "carrier":       dict(cmd="wide",  layout="side",  drums=4),
    "freighter":     dict(cmd="cube",  layout="none",  drums=2),
    "tender":        dict(cmd="wide",  layout="alt",   drums=2),
}

## The command block, as (width, height, depth) in class sizes, and what the
## ship systems display calls it. A cube is a freight hull's wheelhouse, a wide
## bridge is a working ship's, a tower is a flagship's.
CMD = {
    "cube":  ((0.80, 0.55, 0.80), "command block"),
    "wide":  ((1.50, 0.35, 0.60), "bridge, wide"),
    "tower": ((0.70, 1.10, 0.70), "command tower"),
}

## Where a module clamps on at station `i`, as (x, y) offsets in units of the
## clamp distance. This is the whole difference between two Helion hulls of the
## same length, which is why it is a table and not a flag: a belly run reads as
## a freight hull, a quad run as an armoured one, and a flank run as a ship
## built around whatever it is carrying on its sides.
SEATS = {
    "none":  lambda i: (),
    "belly": lambda i: ((0, -1),),
    "alt":   lambda i: ((0, -1 if i % 2 else 1),),
    "pair":  lambda i: ((0, 1), (0, -1)),
    "side":  lambda i: ((1, 0), (-1, 0)),
    "quad":  lambda i: ((0, 1), (0, -1), (1, 0), (-1, 0)),
}

## Half a module across the axis it is clamped on, in class sizes. The module
## is drawn on its side when it rides a flank, so this is the same number
## whichever seat it takes, and the clamp distance below is derived from it.
MOD_HALF = 0.275


def seat_name(ox, oy):
    """What a station is called once it is known which side it hangs on."""
    if ox:
        return "starboard" if ox > 0 else "port"
    return "dorsal" if oy > 0 else "belly"


def build(cls):
    h = Hull("helion", cls["id"])
    Z = cls["size"]
    k_spine = cls["spine"] * Z
    plan = HEL_PLAN.get(cls["id"], HEL_PLAN["light_cruiser"])
    cargo = cls.get("cargo", 0)

    length = 2.4 * k_spine + 1.0 * Z
    spine_w = 0.30 * Z
    # Half the spine, which is how far in anything clamped to it has to reach,
    # and a bite past that, which is how much further. Every clamped part is
    # placed from these two rather than from a number of its own: the source
    # writes one 0.43 that happens to land a module flush on the frame, and one
    # place to get the join right is better than six (CLAUDE.md 4.1).
    half = spine_w * 0.5
    bite = 0.025 * Z

    h.part(truss(length, spine_w), "truss", "truss spine", (0.0, 1.0, 0.0))

    # ---- the command block ---------------------------------------------------
    (cw, ch, cd), cmd_name = CMD[plan["cmd"]]
    cw, ch, cd = cw * Z, ch * Z, cd * Z
    # The tower stands on the spine rather than straddling it; the other two
    # are hung on the centreline. Either way the block swallows the bow end of
    # the truss by a tenth of its depth, which is the source's own overlap and
    # is what makes the two one piece.
    cmd_y = 0.20 * Z if plan["cmd"] == "tower" else 0.0
    cmd_z = length * 0.5 + cd * 0.4
    h.part(box(cw, ch, cd).translate(0.0, cmd_y, cmd_z), "head", cmd_name,
           (0.0, 0.0, 1.0))
    # The cheek blocks are the one piece of block furniture that changes the
    # outline from directly above, so they are the one that survives the
    # tactical budget. They are pulled in a bite from where the source hangs
    # them, which had them meeting the block on exactly one plane.
    for sx in (-1.0, 1.0):
        h.part(box(0.10 * Z, 0.10 * Z, 0.10 * Z)
               .translate(sx * (cw * 0.5 + 0.05 * Z - bite), cmd_y - 0.10 * Z,
                          cmd_z),
               "greeble", ("port" if sx < 0 else "starboard") + " cheek block",
               (sx, 0.0, 0.0))
    h.part(dome(0.10 * Z, 8, 3)
           .translate(-cw * 0.25, cmd_y + ch * 0.5 - 0.01 * Z, cmd_z + 0.20 * Z),
           "greeble", "bridge dome", (0.0, 1.0, 0.0))

    if cls.get("cranes"):
        # Seated into the underside of the bridge rather than slung below it:
        # the source's 0.32 leaves a tenth of a unit of daylight, which reads
        # as one piece and measures as two.
        for sx in (-1.0, 1.0):
            h.part(crane(1.0 * Z).rotate_y(sx * 0.4)
                   .translate(sx * 0.30 * Z, cmd_y - ch * 0.5 + 0.04 * Z,
                              cmd_z + 0.10 * Z),
                   "greeble", ("port" if sx < 0 else "starboard") + " crane",
                   (sx, 0.0, 1.0))

    # ---- the modules ---------------------------------------------------------
    # Stations run from the bow end of the spine aft. A module bites into the
    # frame rather than resting against it, because a module that stops at the
    # rail is a module that has come off.
    z0, z1 = length * 0.38, -length * 0.32
    clamp = half + MOD_HALF * Z - bite
    n = 0 if plan["layout"] == "none" else cls["mods"]
    for i in range(n):
        z = (z0 + z1) * 0.5 if n == 1 else z0 + (z1 - z0) * i / (n - 1)
        for (ox, oy) in SEATS[plan["layout"]](i):
            where = seat_name(ox, oy)
            if cls.get("bays"):
                geo = bay_housing(0.95 * Z, 0.55 * Z, 0.70 * Z)
                # the mouth is on the bow face, so the housing is turned until
                # it opens away from the spine
                if ox:
                    geo.rotate_y(HALF_PI if ox > 0 else -HALF_PI)
                else:
                    geo.rotate_y(-HALF_PI if i % 2 else HALF_PI)
                role, kind = "bay", "hangar"
            else:
                geo = box(MOD_HALF * 2.0 * Z if ox else 0.90 * Z,
                          0.90 * Z if ox else MOD_HALF * 2.0 * Z, 0.70 * Z)
                role, kind = "body", "module"
            h.part(geo.translate(ox * clamp, oy * clamp, z), role,
                   "%s %s %d" % (where, kind, i + 1), (ox, oy, 0.0))

    # ---- the dreadnought's second truss --------------------------------------
    if plan.get("twin"):
        lower_y = -0.95 * Z
        h.part(truss(length * 0.70, 0.20 * Z)
               .translate(0.0, lower_y, -length * 0.05),
               "truss", "second truss", (0.0, -1.0, 0.0))
        # The source's tie is a strut as thin as an outrigger running from the
        # lower frame up through the upper one, and through a belly module on
        # the way. It is two changes from that: wide enough to grip what it
        # crosses, and stopped a bite inside the module run rather than driven
        # through it. The module is already clamped to the spine, so the chain
        # still ends at the spine.
        top = -(clamp + MOD_HALF * Z) + bite
        for sz in (1.0, -1.0):
            h.part(box(0.40 * Z, top - lower_y, 0.10 * Z)
                   .translate(0.0, (top + lower_y) * 0.5, sz * length * 0.22),
                   "truss", ("forward" if sz > 0 else "after") + " tie",
                   (0.0, -1.0, 0.0))

    # ---- the cargo variants ---------------------------------------------------
    if cargo:
        cargo_h = 0.45 * Z
        cargo_run(h, cargo, z0, z1, bite - half - cargo_h * 0.5,
                  0.50 * Z, cargo_h, 0.55 * Z)

    # ---- the engine cluster ---------------------------------------------------
    # Two drums on outriggers, or four in a square. The arms root inside the
    # spine and end inside their drum, so the cluster hangs off the frame the
    # way the modules clamp to it, and nothing in the cluster is held by a
    # neighbour that is itself held by nothing.
    eng_z = -length * 0.5 + 0.20 * Z
    drum_r, drum_len = 0.20 * Z, 0.80 * Z
    rows = (0.40, -0.40) if plan["drums"] == 4 else (0.0,)
    for ri, ey in enumerate(rows):
        tier = ("upper ", "lower ")[ri] if len(rows) > 1 else ""
        y = ey * Z

        def make_drum(side, _y=y):
            return drive_drum(drum_r, drum_len).translate(side * 0.55 * Z, _y,
                                                          eng_z)

        h.pair(make_drum, "pod", tier + "drive drum", (1.0, ey, -0.5),
               inner=True)
        for side in (-1.0, 1.0):
            label = ("port " if side < 0 else "starboard ") + tier
            bearing = math.atan2(y, side * 0.55 * Z)
            h.part(box(0.50 * Z, 0.08 * Z, 0.08 * Z).rotate_z(bearing)
                   .translate(side * 0.275 * Z, y * 0.5, eng_z),
                   "truss", label + "outrigger", (side * 0.5, ey, 0.0))
            # The collar is the one round thing on a Helion and the only
            # curve in the dialect, which is why it is worth its triangles on
            # a hull that is otherwise boxes: it is what tells a drive drum
            # from a container at sixty pixels.
            h.part(hoop(drum_r, 0.035 * Z)
                   .translate(side * 0.55 * Z, y, eng_z),
                   "ring", label + "drum collar", (side * 0.5, ey, 0.0))
            # The bell mouth: the one warm mark a Helion shows from astern,
            # and a part of its own because it is only light.
            h.part(drive_drum(drum_r * 0.92, 0.10 * Z)
                   .translate(side * 0.55 * Z, y,
                              eng_z - drum_len * 0.5 + 0.02 * Z),
                   "glow", label + "bell mouth", (0.0, 0.0, -1.0), glow=True)
    return h
