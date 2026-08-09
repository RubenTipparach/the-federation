# 15. Worlds

Concept for each of the four worlds an arena can hold. What the world is, what
the player reads off it in the two seconds they will spend looking at it, what
it does to a ship, and which palette entries it is built from.

Every picture here is the real thing. `tools/shoot_worlds.gd` instances the same
`scenes/terrain/planet.tscn` a battle instances, calls the same `place()`, and
lights it with the rig copied out of `scenes/combat_world.tscn`;
`tools/gen_world_plates.py` arranges the results without resampling them. Run
`./scripts/gen-world-plates.sh` to regenerate the lot. Nothing on this page was
drawn by hand, so a page that disagrees with the game is a bug in the game, not
in the illustration.

How a world is drawn, and where the shader came from, is
[14-reference-planet-shader.md](14-reference-planet-shader.md). What terrain
does to a ship is [13-terrain-and-tractors.md](13-terrain-and-tractors.md)
sections 3 and 4. This document is the concept.

---

## 1. One world, off centre

![The four worlds](images/worlds/lineup.png)

An arena holds **exactly one** world today. `data/maps.json` gives the High
Orbit recipe a count of `[1, 1]`, and the battle seed picks which of the four
looks it wears. So a player who fights ten orbit battles sees ten worlds and one
of them at a time, never two together. That is a deliberate starting point
rather than a limit of the art: a second body would double the number of wells a
captain has to keep in their head, and the well is the whole point of the map.

**What a world does, whichever one it is.** All four are mechanically identical,
and that is on purpose for now.

| | |
|---|---|
| Body radius | 40 to 55 arena units, drawn per battle |
| Well radius | 160 to 200 arena units |
| Pull | 13.6 units per second at the surface, falling linearly to nothing at the well's edge |
| Hitting it | 45 damage, the heaviest collision in the game (a rock is 12) |

The pull is a velocity the ship acquires rather than a force integrated into its
own, which is what keeps it stable at any timestep and therefore replayable. A
captain who ignores it does not fall out of the sky; they arrive somewhere they
did not steer for, with their firing arcs pointed at nothing.

**The look carries no mechanics.** An ice world pulls exactly as hard as a gas
giant. Whether that stays true is section 6.

**What a world is made of, as data.** Four colours and six numbers, and nothing
else. `data/palette.json` `worlds` names the colours as palette roles;
`data/tuning.json` `terrain_view.planets` holds the shape. A fifth kind of world
is an entry in those two files, not a line of code and not a new scene.

| Slot | What it paints |
|---|---|
| `low` | the ground below the split: ocean, deep ice, the floor of a crater field |
| `mid` | the ground above it |
| `high` | the peaks of the ramp |
| `rim` | the atmosphere at the limb, which is emissive rather than lit |

| Number | What it changes |
|---|---|
| `distortion` | how hard the surface bands are warped. Low is banded weather, high is marbled ground. Past about 0.6 it stops making coastlines and starts making noise. |
| `split` | where low ground gives way to middle ground, so how much ocean there is |
| `band_x`, `band_y` | how many bands wrap around the world and across it |
| `rim_retraction`, `rim_brightness` | how tight and how bright the atmosphere is |
| `spin` | how fast it turns. Zero stands still. |

---

## 2. Terran

![Three terran worlds and the colours they are built from](images/worlds/terran.png)

**The concept: somebody lives here.** This is the only world of the four that
implies a reason for the battle. If two fleets are fighting in its well, they
are fighting over it. Nothing in the simulation says so yet, and the art is
doing that work on its own.

**What it reads as at a glance:** deep blue with green and pale land wrapped
through it, the most colour of any of the four. In a tactical view it is the one
world that competes with the ships for attention, which is the argument for
keeping it rare rather than making it the default.

`blue` ocean, `green` land, `olive_light` on the heights, `blue_hi` at the limb.
Its split is the highest of the four at 0.58, which is what puts most of the
surface under water.

---

## 3. Ice

![Three ice worlds and the colours they are built from](images/worlds/ice.png)

**The concept: a world that used to be terran, or never quite got there.** The
sheet is the surface, and the darker teal is what shows through where it has
thinned. It is the quietest of the four and the easiest to read a ship
silhouette against, because most of it is one bright value.

**What it reads as at a glance:** bright, cold, low contrast. A hull crossing in
front of it is a dark shape on white, which is the clearest read in the game.

`teal_deep` under, `gray_blue_light` over, `cream` on the heights, and
`shield_hi` at the limb. That last one is borrowed from the interface pool
deliberately, so a frozen world's atmosphere matches the colour a shield is
drawn in elsewhere.

---

## 4. Barren

![Three barren worlds and the colours they are built from](images/worlds/barren.png)

**The concept: nothing happened here and nothing will.** No air worth the name,
so the limb is nearly unlit: its `rim_brightness` is 0.5 where every other world
is above 1.3, and that difference alone is what makes it read as airless.

**What it reads as at a glance:** a rock. `char`, `taupe_deep` and `taupe`, no
hue in it at all. It is the only world with no bright value, so it recedes
rather than competing, which makes it the right default for a fight about
something other than the planet.

---

## 5. Gas giant

![Three gas giants and the colours they are built from](images/worlds/gas.png)

**The concept: the one world that is unmistakably not a place to land.** Banded
weather all the way down, and a ring.

![The gas giant with its ring, framed wide enough to show it](images/worlds/native/gas-ring.png)

**What it reads as at a glance:** big, striped, warm where every other world is
cool. `clay_deep` in the deep bands, `gold` and `gold_hi` above them. Its
`band_y` is 4 against terran's 8, which is what keeps its weather in wide
horizontal belts rather than breaking it into continents.

**The ring is a committed mesh, not part of the shader.** It is
`assets/meshes/planet_ring.obj`, a flat annulus written by `tools/gen_meshes.py`
like every other mesh in the game, tilted in the scene and scaled by
`terrain_view.ring_span` to nearly twice the body's radius. It takes its colour
from the world's `mid` role and its transparency from the scene, and it is
hidden on the other three worlds.

**The ring still does nothing.** The simulation knows about the body and the
well, and nothing else. A ship flies through the ring with no effect at all,
which is the one place on this page where the art promises something the rules
do not deliver. Section 6 has the options.

---

## 6. What is not built

**Worlds turn, barely.** Every variant has a `spin` between 0.002 and 0.010,
which is slow enough that a world visibly moves over a long battle and never
pulls the eye during a gun duel. It costs nothing: the shader reads the same
noise field at a different offset. If it turns out to be distracting, the number
to set to zero is in `data/tuning.json`.

**Looks carry no rules.** The four are mechanically identical, so the variant is
decoration. The obvious next step is to let each one bend one number: a gas
giant with a wider, weaker well; a barren rock with a tighter, sharper one; an
ice world whose surface is survivable where the others are not. That is a
`data/maps.json` change and a `Terrain` change, not an art change, and it wants
its own design pass rather than an implementer's guess.

**The ring does nothing.** Either it should grind like an asteroid halo, using
the rule that already exists, or the gas giant should be drawn without one.
Drawing a hazard that is not a hazard teaches a player the wrong thing.

**An arena holds one world.** Two would give a captain a choice of wells to
fight in, which is a genuinely different map rather than the same map twice. It
costs one number in `data/maps.json` and a look at whether the placement rules
still keep the starting positions clear.

**Terran does not read as terran yet.** It is the weakest of the four: the
whorley function bands everything, and warping it hard enough to break the bands
into continents also breaks it into noise. Getting real coastlines means either
a second noise term in the shader or accepting that these are weather worlds
rather than mapped ones.
