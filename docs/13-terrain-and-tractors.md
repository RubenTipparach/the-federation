# 13. Terrain and tractor beams

Two systems that arrive together, because they answer the same question: what is in
the arena besides the two ships, and what can a ship do to another ship's position
without shooting it.

Terrain gives a skirmish a *place*. An empty box rewards exactly one behaviour, which
is to circle at the range your best weapon likes. A nebula, a rock field, and a planet
each break that circle in a different way, so the same fit plays differently depending
on where the fight happens.

Tractors give a ship leverage over another ship's position. Federation Commander does
not print its tractor rules in the free preview, which
[09-reference-federation-commander.md](09-reference-federation-commander.md) section 6
records in detail. What follows is ours, built on the two things the source does say:
a tractor holds at a distance or pulls closer and cannot tear a ship apart (5D), and
it is dead when the control boxes are (5A2c). The index entry named "Tractor Auctions"
(5D6a) is why this is an auction rather than a comparison of numbers.

---

## 1. What terrain is, in a 2D sim

[01-tactical-combat.md](01-tactical-combat.md) fixes the simulation to one plane. So
terrain is **circles on that plane**. A feature has a kind, a centre, a body radius,
and a field radius, and every effect below is a function of a ship's distance to that
centre or of a line segment's overlap with that circle.

This is a deliberate ceiling. No feature has a shape, an orientation, or a
concavity. Circles are cheap to query, trivial to test headlessly, cheap to send over
a wire, and above all they are *legible*: a player can see where the edge is from the
plan inset and know exactly what crossing it will cost. A nebula with a ragged outline
would look better and play worse.

Every feature is placed from the battle seed. A replay reproduces the map because it
reproduces the seed, exactly as it reproduces the ships (see
[11-battle-logs-and-replay.md](11-battle-logs-and-replay.md)).

### 1.1 The three kinds

| Kind | Body radius | Field radius | Body does | Field does |
|---|---|---|---|---|
| `nebula` | none | the cloud | nothing | hides, along the line of sight |
| `asteroid` | the rock | the dust halo | hard collision | grinds shields |
| `planet` | the surface | the gravity well | very hard collision | pulls |

A map type is a **recipe**: how many of each kind, in what size band, placed how. It is
data in `data/maps.json`, not code, per CLAUDE.md 5.4. Adding a map type is adding an
entry to that file.

---

## 2. Nebula

**What it is for:** making a fight about who can see whom. A nebula is where a
frigate goes when a battlecruiser is winning, and where a battlecruiser refuses to
follow.

### 2.1 Obscuration is a path length, not a flag

The wrong model is "you are in the cloud, so you are hidden". That makes the edge a
switch and rewards sitting exactly one metre inside it. The right model is: **how much
cloud is between the two ships**.

For a shot or a lock from A to B, sum the length of the segment A-B that lies inside
any nebula circle, and divide by `nebula_opacity_length` from tuning. Call that the
**obscuration**, a number from 0 upward.

Three consequences follow from one number:

- **Lock degrades before it breaks.** Obscuration is added to the range that the
  damage model uses, scaled by `nebula_range_penalty`. A shot through half a cloud
  lands, and scores as though it were fired from much further away, because
  `WeaponModel` already makes damage fall with range. No new damage rule is written:
  the cloud lies to the gunnery computer about the range, and the existing rule does
  the rest.
- **Lock breaks at a threshold.** At `nebula_lock_obscuration` and above, the target
  cannot be fired on at all and cannot be selected. Seeking weapons already in flight
  lose their target and run to the end of their fuel.
- **Invisible means invisible.** A ship that cannot be locked does not draw a target
  bracket, does not appear in the plan inset, and does not appear in the target
  readout. The last known position is shown, greyed, and it goes stale.

Both directions use the same number, because the segment is the same segment. A ship
that has hidden itself has also blinded itself, which is what stops the nebula from
being a free win.

### 2.2 What the nebula does not do

It does not damage. It does not drain shields, slow ships, or block movement. Those
would each be a separate rule to learn and a separate number to tune, and the hiding
is already the whole point. Federation Commander's full nebula rules do more than
this; we are not copying them, and we are not guessing at them.

---

## 3. Asteroids

**What it is for:** making a piece of the arena expensive to fly through fast, so
that a chase has a shape other than a straight line.

An asteroid is a **rock** with a **dust halo**, placed as a loose cluster of several
rocks so the field reads as a field rather than as bollards.

### 3.1 The halo grinds

Inside the halo, a ship takes `asteroid_grind_dps` damage per second, scaled linearly
from zero at the halo's edge to full at the rock's surface, and scaled by the ship's
speed so that drifting through is survivable and charging through is not. The damage
arrives on the facing pointing along the ship's own velocity, because that is the
facing meeting the dust, which means running through a field with a stripped forward
shield is exactly as bad as it sounds.

Grind resolves through `ShipState.apply_damage` like anything else: shields first,
internals when the shield is gone. There is no separate micrometeor damage rule
(CLAUDE.md 4.1).

### 3.2 The rock collides

Touching the body radius is a collision: `asteroid_collision_damage` on the facing that
met the rock, and the ship's speed is cut to `collision_speed_frac`. There is no
bouncing and no physics; a collision is an event with a cost, not a simulation of
contact. Ships are big and slow and this is a game about arcs.

A collision has a cooldown of `collision_cooldown` seconds per ship so that sitting on
a rock does not deal damage every tick.

### 3.3 So do two ships

Two hulls closer than the sum of their radii are touching, and the price is paid through
the same code, because there is one collision rule and forking it would let a ship
survive a battlecruiser it could not survive an asteroid. A hull's radius is
`tonnage * combat.hull_radius_per_ton`, and it is the simulation's number rather than the
view's: the target bracket measures its on screen size from the same figure, so the ring
a player sees around a contact is the circle that contact collides with.

What is different from a rock is that the other party is a ship, so the damage is shared
out rather than fixed. Severity is the closing speed as a fraction of `ram_speed_ref`,
floored at `ram_speed_floor` so a nudge still counts, and the pair's tonnage divides
`ram_damage` between them: two equal hulls take it each, and neither side's share can
exceed twice that however lopsided the pairing. Ramming a frigate is a tactic. Ramming a
battlecruiser is not.

The opponent does not want any part of this, and steers to avoid it. See
[01-tactical-combat.md](01-tactical-combat.md) section 2, "Two ships cannot occupy the
same space".

---

## 4. Planets

**What it is for:** making one part of the map have a *direction*. A gravity well
turns the arena from flat to sloped, and a fight fought on a slope is a different
fight.

### 4.1 Gravity is a drift, not an acceleration

A planet's well applies a pull toward the centre with magnitude
`planet_pull * (1 - distance / well_radius)`, zero at the well's edge, maximum at the
surface.

The pull is expressed as a **drift velocity** the ship acquires, not as a force
integrated into its own velocity. `ShipState` gains one field, `drift`, added to the
heading vector during integration. Each step the drift moves toward the pull the ship
is currently sitting in, at `drift_accel` per second, and toward zero when there is no
pull.

This is not how gravity works. It is how gravity should *feel* in a game where the
player steers with a heading and a throttle: the ship keeps pointing where it was
told, and slides. It is also stable at any timestep, which a naive integration is not,
and stability matters because a replay must reproduce a battle exactly.

Engines fight the slide because engine thrust is the other term in the same sum. A
ship at full throttle away from a planet escapes; a ship with its engines shot out
does not.

### 4.2 The surface is fatal

Reaching the body radius costs `planet_collision_damage`, which is set high enough
that a healthy cruiser survives one and nothing survives two. The same cooldown rule
as asteroids applies, so a ship sitting on the surface dies in a few seconds rather
than instantly.

### 4.3 Worlds come in three kinds

A planet is drawn as one of `terran`, `ice`, `barren`, or `gas`, chosen by the battle seed
like everything else, so a replay shows the same world. The list lives in
`data/maps.json` beside the recipe, and adding a fourth kind is an entry there
plus a scene to draw it.

They are pixel art, drawn by shaders vendored from Deep-Fold under the MIT
licence and documented in
[14-reference-pixel-planets.md](14-reference-pixel-planets.md). Those shaders are
2D, so each world renders into its own small viewport and is shown on a card that
faces the camera. That is not an approximation of a sphere: a sphere projects to a
circle from every direction, so a camera facing card is exactly the shape of one.
What it buys is that a planet is now made of the same chunky pixels as the ships
and the panels.

They never blend between their colours, which is why they can be used at all here:
feed them palette entries and every pixel they emit is a palette entry
(CLAUDE.md 3.1). The lists live in `data/palette.json` under `worlds`.

Nothing about this is gameplay: a gas giant pulls and kills exactly like a rock
one. The variant is what it looks like, which is why it is a whole authored
scene per kind rather than a material the code swaps in.

### 4.4 A planet is not cover

A planet does not block line of sight. Blocking would require the shot to know about
occlusion, which means a second visibility system alongside the nebula's, and the two
would drift apart. If we later want hard cover, it becomes an opacity so extreme that
the nebula rule already covers it.

---

## 5. Map types

Four to start, in `data/maps.json`:

| Id | Name | Contains |
|---|---|---|
| `open` | Open Space | nothing, the arena as it is today |
| `nebula` | Nebula Shoals | 5 to 7 overlapping clouds, covering a third of the arena or more |
| `belt` | Debris Belt | 2 to 3 clusters of 4 to 7 rocks each |
| `orbit` | High Orbit | 1 planet, off centre, with its well covering a third of the arena |

`open` exists so that the change is provably additive: a battle on `open` must be
byte identical to a battle before terrain existed, and there is a test that says so.

Placement rules that every recipe obeys:

- Nothing is placed within `spawn_clearance` of either starting position. Being
  inside a rock on the first tick is not an interesting tactical situation.
- Bodies do not overlap other bodies. Fields overlap freely, and nebula clouds are
  *meant* to.
- Everything is placed inside the arena, allowing for its field radius, so that
  `Battle._keep_in_arena` never traps a ship against a wall inside a planet.
- **A battle opens with a lock.** Clouds may degrade the line between the two starting
  positions as far as they like, but no cloud is placed that would push that line past
  the lock threshold. Losing contact should be something a captain does, not something
  the map did before the first tick.

---

## 6. The tractor beam

### 6.1 What it is made of

- **A box.** `TRAC`, a control family system, priced at 2 spare parts per box, which is
  what Federation Commander 5G3 charges for a tractor. With the box out, the tractor
  cannot be used, which is 5A2c. Not every hull carries one: the Kthaari Talon is an
  escort with no emitter at all, which is a statement about what that ship is for.
- **A power sink.** `tractor` joins weapons, shields, engines, systems, and reserve in
  `data/tuning.json`. The number of reactor units in that sink **is** the bid. It is
  set with the same discrete box strip that sets every other sink, so there is no new
  control and, per CLAUDE.md 6.2, no slider.
- **A range.** `tractor_range`, shorter than a beam's reach. There is no arc: a
  tractor works in every direction. Giving it an arc would double the number of things
  a player is tracking during a manoeuvre for no gain.

### 6.2 The auction

A tractor is not a hit. It is a standing bid, and the fight over it is continuous.

**Latching.** The attacker orders a latch on a target within range. It succeeds if the
attacker's `TRAC` box is alive and its tractor sink holds at least
`tractor_min_units`. The target is now held.

**Holding.** Every step, both ships' bids are read out of their tractor sinks:

```
hold  = holder.alloc_units("tractor")
break = held.alloc_units("tractor") * (held.tonnage / holder.tonnage)
```

**Holding needs an emitter, breaking does not.** Latching a ship requires a live `TRAC`
box. Shoving against a beam that is already on you is done with the engines and the
structure, so a hull carrying no tractor is never helpless, and the auction is
something every ship can enter.

The mass ratio is the whole design in one line. A frigate can latch a battlecruiser,
and the battlecruiser breaks it with a fraction of the power the frigate is spending,
because the battlecruiser is three times the ship. A frigate holding a frigate is a
straight contest of how much reactor each captain is willing to take away from their
guns.

**Breaking.** When `break > hold` continuously for `tractor_break_seconds`, the beam
snaps. The timer resets whenever the holder is ahead again, so the struggle is
visible and reversible rather than settled on a single tick. After a break, neither
ship may latch the other for `tractor_relatch_cooldown` seconds.

**Both sides pay the whole time.** That is what makes it an auction rather than a
comparison. Every unit in the tractor sink is a unit not charging a capacitor and not
buying a shield box. A captain who wins a long tug of war and then finds their guns
cold has still lost the exchange.

The beam also snaps immediately if the range exceeds `tractor_range`, if the holder's
`TRAC` box is destroyed, or if either ship dies.

### 6.3 What a held ship loses

Federation Commander 5D is explicit that a tractor holds at a distance or pulls
closer, and explicitly that it cannot pull a ship apart. So:

- **The two ships share a velocity.** While the beam is up, both ships' motion is
  blended toward their common momentum, weighted by tonnage, at
  `tractor_blend_rate` per second. A heavy holder drags a light prisoner almost
  completely. A light holder mostly gets towed.
- **Turning is untouched.** The held ship can still come about and bring its guns to
  bear. This is deliberate: taking away a ship's arcs takes away the game, and the
  source says the beam holds position, not attitude. A tractor is a way to keep an
  enemy in your best arc, not a way to stop it fighting.
- **Range control belongs to the holder.** The holder picks `HOLD`, which keeps the
  current separation, or `REEL`, which closes it at `tractor_reel_speed`. Those are
  exactly the two things 5D says a tractor does. There is no push mode, because the
  source does not describe one.

### 6.4 What we are deliberately not building yet

The index of the free rulebook names **5D4 Tractor Beams, Defensive**, which we cannot
read. Using a tractor to catch an incoming seeker is therefore not implemented, and
nothing in the code should imply it exists. It is a natural extension and it can wait
until we have a rule to build against or a design of our own worth writing down.

---

## 7. Where this lives in the code

| Piece | File | Why there |
|---|---|---|
| Feature queries: obscuration, pull, hazards | `src/sim/terrain.gd` | pure, headless, no nodes |
| Map recipes and seeded placement | `src/sim/terrain.gd` + `data/maps.json` | data drives it (5.4) |
| Applying terrain effects each step | `src/sim/battle.gd` | the battle owns the world |
| The tractor contest | `src/sim/tractor.gd` | one implementation, per 4.1 |
| Beams currently up, and the orders that make them | `src/sim/battle.gd` | the one command path (docs/11) |
| Tuning numbers | `data/tuning.json` | never inline (5.4) |

The renderer asks `Terrain` the same questions the simulation does. There is not a
second visibility rule for drawing brackets and a first one for firing: the target
bracket is hidden because `Terrain` says the lock is broken, which is the same call
`fire_check` makes. Two answers to "can I see him" is the exact failure CLAUDE.md 4.1
exists to prevent.

---

## 8. The screens

Both were mocked up and approved before any of them was built, per CLAUDE.md section 6.

- **The map picker** sits in the middle column of the skirmish screen, directly above
  Begin, as four cards in one row. Each card carries a plan of a real placement drawn
  from a fixed preview seed, so choosing Debris Belt means having seen what a debris
  belt looks like. The battle then draws its own arena from its own seed, which is why
  there is no regenerate button: there is nothing to regenerate until Begin is pressed.
- **Terrain in the tactical view** costs no new control, because none of it is
  something a player operates. The 3D world carries the features and the plan inset
  looks at that same world, so the map appears in both without a second painter. A lost
  lock greys the target readout, prints the age of the last reading, and takes the
  bracket and the floating label away; the weapon rows say `no lock` in the same chip
  that already says `no arc`.
- **The tractor station** is the bid strip, the latch control, the HOLD and REEL
  choice, and the contest drawn as two box strips meeting at a seam. One panel serves
  both ends of a beam: the geometry is fixed, grip on the left and shove on the right,
  and the colour says which of them is yours. It is also the one station that stays
  reachable with its box shot out, because shoving needs engines rather than an
  emitter, and that exception lives in `data/stations.json` rather than being named in
  code.

**One thing the mockup did not cover and the game does not yet draw: the beam itself.**
A tractor currently shows in the panel and in how the two ships move, but there is no
line between them in the 3D view. That needs its own mockup.
