# 15. Worlds

Concept for each of the four worlds an arena can hold. What the world is, what
the player reads off it in the two seconds they will spend looking at it, what
it does to a ship, and which palette entries it is made of.

Every picture here is the real thing. `tools/shoot_worlds.gd` draws each world
through the same scene the battle uses and writes it at native size;
`tools/gen_world_plates.py` magnifies that by a whole number and arranges it.
Run `./scripts/gen-world-plates.sh` to regenerate the lot. Nothing on this page
was drawn by hand, so a page that disagrees with the game is a bug in the game
or in the palette, never in the illustration.

How they are drawn, and why the colours are ours rather than Deep-Fold's, is
[14-reference-pixel-planets.md](14-reference-pixel-planets.md). What terrain
does to a ship is [13-terrain-and-tractors.md](13-terrain-and-tractors.md)
sections 3 and 4. This document is the concept.

---

## 1. One world, off centre

![The four worlds at a single magnification](images/worlds/lineup.png)

An arena holds **exactly one** world today. `data/maps.json` gives the High
Orbit recipe a count of `[1, 1]`, and the battle seed picks which of the four
looks it wears. So a player who fights ten orbit battles sees ten worlds and
one of them at a time, never two together. That is a deliberate starting point
rather than a limitation of the art: a second body would double the number of
wells a captain has to keep in their head, and the well is the whole point of
the map.

The lineup above is at one magnification, so the sizes are true relative to
each other. The gas giant is not a bigger planet: its body is the same 40 to 55
arena units as the others, and the extra width is ring.

**What a world does, whichever one it is.** All four are mechanically
identical, and that is on purpose for now.

| | |
|---|---|
| Body radius | 40 to 55 arena units, drawn per battle |
| Well radius | 160 to 200 arena units |
| Pull | 13.6 units per second at the surface, falling linearly to nothing at the well's edge |
| Hitting it | 45 damage, the heaviest collision in the game (a rock is 12) |

The pull is a velocity the ship acquires rather than a force integrated into
its own, which is what keeps it stable at any timestep and therefore
replayable. A captain who ignores it does not fall out of the sky; they arrive
somewhere they did not steer for, with their firing arcs pointed at nothing.

**The look carries no mechanics.** An ice world pulls exactly as hard as a gas
giant. Whether that stays true is section 6.

---

## 2. Terran

![Three terran worlds and the colours they are made of](images/worlds/terran.png)

**The concept: somebody lives here.** This is the only world of the four that
implies a reason for the battle. It is a green and blue marble with weather
across it, and if two fleets are fighting in its well, they are fighting over
it. Nothing in the simulation says so yet, and the art is doing that work on
its own.

**What it reads as at a glance:** the busiest of the four. Continents, coast,
cloud, and an obvious lit side. In a tactical view it is the one world that
competes with the ships for attention, which is the argument for keeping it
rare rather than making it the default.

Eleven colours, the widest range any world uses: ocean in three blues, land in
three greens over an olive shelf, cloud in cream and bone, and a taupe and
gray-blue shadow. Drawn by the vendored `LandMasses` shader, three layers deep
(ocean and land, cloud, then the shadow that sits over both).

---

## 3. Ice

![Three ice worlds and the colours they are made of](images/worlds/ice.png)

**The concept: a world that used to be terran, or never quite got there.** The
sheet is the surface, and the teal is meltwater showing through where it has
thinned. It is the quietest of the four and the easiest to read a ship
silhouette against, because almost all of it is one bright value.

**What it reads as at a glance:** bright, cold, low contrast. A hull crossing
in front of it is a black shape on white, which is the clearest read in the
game.

Ten role slots and seven distinct colours: cream and bone for the sheet,
`shield_hi` and teal for the lakes, gray-blue for the terminator. It borrows
`shield_hi` from the interface pool deliberately, so the meltwater matches the
colour a shield is drawn in elsewhere.

The vendored `IceWorld` scene has no shaders of its own: it is the terran
world's `PlanetUnder` and `Clouds` with different colours and different
parameters, and no landmass layer. So the difference between a living world and
a frozen one, in this art, is one layer and a palette. That is worth knowing
before anyone proposes a fifth world type, because a fifth one may well be
free.

---

## 4. Barren

![Three barren worlds and the colours they are made of](images/worlds/barren.png)

**The concept: nothing happened here and nothing will.** No air, so no cloud
layer and no soft limb: the edge of the disc is a hard line against space, and
the craters go right to it. It is the cheapest world to look at and the one
that says the arena is empty, which makes it the right default for a fight
about something other than the planet.

**What it reads as at a glance:** a rock. Five colours, all taupe through char,
no hue at all beyond a moss-grey in the crater floors. It is the only world
with no bright value in it, so it recedes rather than competing.

Drawn by the vendored `NoAtmosphere` shader, which is the only one of the four
with no atmosphere pass, and that absence is the entire design.

---

## 5. Gas giant

![Three gas giants and the colours they are made of](images/worlds/gas.png)

**The concept: the one world that is unmistakably not a place to land.** Banded
weather all the way down and a ring at three times the body's width, tilted so
it crosses the disc. It is the only world of the four with a feature that
extends past its own body, and the only one whose picture is wider than its
collision circle.

**What it reads as at a glance:** big, striped, ringed. Note what the third
draw shows: the bands vary a great deal between seeds, from an almost featureless
cream ball to a heavily marbled one, so two gas giants look less alike than two
ice worlds do.

Six colours, gold through bronze and clay into bark and plum for the night
side, warm where every other world is cool. Drawn by the vendored
`GasPlanetLayers` shader.

**The ring is a picture, not an object.** The simulation knows about the body
and the well, and nothing else. A ship flies through the ring with no effect at
all, which is the one place on this page where the art currently promises
something the rules do not deliver. Section 6 has the options.

---

## 6. What is not built

Four things are worth deciding, and none of them are started.

**Worlds do not turn.** The vendored shaders contain no `TIME` uniform at all,
so a world is drawn once when it is placed and then never again, and it is a
still picture for the whole battle. That is cheap and it is calm. Deep-Fold's
originals do rotate, and putting that back means a per frame viewport redraw
per world. Worth doing for a world that is the subject of the battle; probably
not worth it for a barren rock in the corner.

**Looks carry no rules.** The four are mechanically identical, so the variant
is decoration. The obvious next step is to let each one bend one number: a gas
giant with a wider, weaker well; a barren rock with a tighter, sharper one; an
ice world whose surface is survivable where the others are not. This is a
`data/maps.json` change and a `Terrain` change, not an art change, and it wants
its own design pass rather than an implementer's guess.

**The ring does nothing.** Either it should grind like an asteroid halo, using
the rule that already exists, or the gas giant should be drawn without one.
Drawing a hazard that is not a hazard teaches a player the wrong thing about
the map.

**An arena holds one world.** Two would give a captain a choice of wells to
fight in, which is a genuinely different map rather than the same map twice.
It costs one number in `data/maps.json` and a look at whether the placement
rules still keep the starting positions clear.

---

## 7. Where they come from

| Variant | Vendored scene | Its shader layers | Viewport | Role list |
|---|---|---|---|---|
| `terran` | `LandMasses` | `PlanetUnder`, `PlanetLandmass`, `Clouds` | 100x100 | 11 slots, 11 colours |
| `ice` | `IceWorld` | `PlanetUnder`, `Clouds` | 100x100 | 10 slots, 7 colours |
| `barren` | `NoAtmosphere` | `NoAtmosphere`, `Craters` | 100x100 | 5 slots, 5 colours |
| `gas` | `GasPlanetLayers` | `GasLayers`, `Ring` | 300x300, because the ring is three times the body | 6 slots, 6 colours |

Each is a scene under `scenes/terrain/`, placed by `src/ui/terrain_field.gd`
and configured by `src/ui/pixel_planet.gd`. The colours come from the `worlds`
role map in `data/palette.json` and nowhere else. `tools/gen_world_plates.py`
re-checks every rendered pixel against the palette before it writes a plate, so
a shader that blended two entries into a third would fail this page rather than
appear on it.
