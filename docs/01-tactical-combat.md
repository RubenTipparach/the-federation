# 01. Tactical Combat

The battle layer. This is the part that must be fun before anything else is built.

---

## 1. Framing

- **View:** **rendered in 3D**, with an orbitable camera, in the manner of Starfleet
  Command. Ships are 3D models. A plan-view tactical inset is always present. Ships are readable
  silhouettes with visible shield arcs and damage state.
- **Scale:** capital ships are slow and heavy. A heavy cruiser takes ~8 seconds to come
  about 90°. Engagements are decided over minutes, not seconds.
- **Pacing:** real-time. Single-player and co-op PvE support **tactical pause**. PvP runs
  unpaused at the same base timescale (see GDD §11.2).
- **Duration target:** 10-25 minutes. Hard scenario timer at 30 minutes, after which
  a withdrawal is forced and the result is scored on damage dealt.
- **Sides:** up to 6 capital ships per player squadron; instance target cap 24 capital
  hulls plus fighters/drones/platforms.

### 3D presentation, 2D simulation

**Combat renders in 3D. This is a hard requirement.** Ships are 3D models, the camera
orbits, and the engagement is presented the way Starfleet Command presented it.

**Ships move on a single plane.** The simulation is 2D: a position, a heading, and a
velocity. There is no pitch, no roll as a manoeuvre, no altitude, and no vertical
separation between contacts. This is the same split the reference used, and it is what
makes the two halves compatible rather than contradictory.

Why the plane stays 2D:

- Shield facings, weapon arcs, and crossing the T are only legible when every contact
  shares one plane. Full 3D movement turns arc management into guesswork, which would
  gut the fitting screen's entire purpose.
- Six facings is a *planar* partition. In free 3D you need a solid angle partition, and
  the tabletop lineage this design comes from does not have one.
- The sim state stays tiny. A ship is `x, z, heading`, so netcode payload, interest
  management, and the authoritative tick are unaffected by the 3D presentation. See
  [06-technical-architecture.md](06-technical-architecture.md) §4.

**How arcs stay readable in 3D:** every tactical overlay is painted **on the plane**, not
in screen space. Shield facings are arc segments on the plane around each hull, firing
envelopes are fans on the plane, and range rings are circles on the plane that read as
ellipses under perspective. Because they live on the plane, the perspective that makes the
scene look 3D also tells you where things are.

### The camera looks down, always

**Elevation is clamped to 25 to 90 degrees.** The camera is never level with the plane,
never below it, and never tilted up toward a horizon. Straight down (90) is the plan view;
25 is the lowest, most cinematic angle allowed.

This is a hard constraint, not a default, and it does two jobs with one number:

- **It is the camera rule.** Combat is looked *down* on. There is no positive pitch and no
  under-plane view, so the player can never lose the plane as a spatial reference.
- **It also settles legibility.** A low camera foreshortens the plane until arcs collapse
  into slivers, which starts to bite around 20 degrees. Because the floor sits above that,
  arc geometry is *always* readable from the 3D view. Foreshortening is prevented
  structurally rather than warned about.

The clamp must live in exactly one function that every input path calls (slider, drag,
keyboard, presets, scripted camera moves). Per-handler clamping is how one path eventually
drifts and allows an illegal camera.

**A plan-view inset is still mandatory, not a nicety.** Whatever the 3D camera is doing,
one always-top-down view of arcs and positions must be on screen. At the floor the 3D view
is readable, but the inset is what makes arc comparison across several ships quick, and it
is the guarantee that cinematic framing can never cost tactical information.

---

## 2. Movement

Momentum-based but bounded, so ships feel massive without becoming unmanageable.

| Property | Meaning |
|---|---|
| **Thrust** | Acceleration, scaled by power routed to engines |
| **Max speed** | Hard cap by hull class × engine tier (prevents runaway drifting) |
| **Turn rate** | Degrees/sec, scaled by power to engines and hull mass |
| **Lateral thrust** | Optional subsystem; enables strafing/slipping without turning |

Player issues **heading + throttle**; the ship obeys as fast as its mass and current
engine power allow. There is no reverse: you turn, or you don't get there.

**Terrain effects** (inherited from the hex the battle spawned in):

| Terrain | Effect |
|---|---|
| Deep space | Baseline |
| Nebula | Sensor range halved, shields at 50% effectiveness, cloaks unreliable |
| Asteroid field | Cover (blocks line of fire), collision damage, seeking weapons lose lock |
| Ion storm | Random power spikes/brownouts, ECM heavily degraded |
| Gravity well | Constant drift toward the mass; thrust cost to hold station |
| Wreck field | Cover + salvage objects + hidden derelicts |

Terrain is a primary reason to fight *here* instead of *there*, which gives the strategic
layer real texture. See [04-galaxy-and-territory.md](04-galaxy-and-territory.md).

---

## 3. Energy Allocation: the core mechanic

Each ship produces **Power** per second from its reactors. The player continuously splits
it across five sinks. This panel is the primary interface during combat.

```
        REACTOR OUTPUT: 42 / 42
   ┌──────────────────────────────────────────┐
   │ WEAPONS      ████████████░░░░░░   14     │  → charges weapon capacitors
   │ SHIELDS      ██████████░░░░░░░░   12     │  → regen + reinforcement per facing
   │ ENGINES      ████████░░░░░░░░░░   10     │  → thrust + turn rate + max speed
   │ SYSTEMS      ████░░░░░░░░░░░░░░    4     │  → cloak / tractor / ECM / transporters
   │ RESERVE      ██░░░░░░░░░░░░░░░░    2     │  → battery charge, emergency dump
   └──────────────────────────────────────────┘
```

Rules that make this interesting:

1. **Total is fixed and always fully spent.** Adding to one sink takes from another. No
   "just add more". You spend the whole time robbing Peter to pay Paul.
2. **Reallocation is not instant.** Moving power has a ramp (≈0.5-1.5s depending on your
   engineering officer and power-conduit tier). You must commit *slightly early*, which is
   where skill lives.
3. **Batteries** store a small reserve for one burst: a single overload shot, an
   emergency shield reinforce, or a full-power turn. Recharging costs sustained allocation.
4. **Damaged reactors reduce total output.** Losing a reactor mid-fight forces a complete
   rethink, not a small stat loss. This is the most impactful internal hit in the game.
5. **Weapons only fire from charged capacitors.** Rerouting away from weapons doesn't
   dump the charge you already have. It stops you getting the *next* shot.

**Doctrine presets** (one-key allocation profiles: Alpha Strike / Brawl / Run Silent /
Flank / Withdraw) exist so newer players aren't drowning, and so veterans can snap between
states quickly. Presets are configured in the shipyard, per design.

---

## 4. Shields: six facings

**Two controls beyond raw power.** The shield engineer can **bias** one facing,
which weights that facing's share of regeneration toward the side being held,
and can **transfer** strength to an adjacent facing, which is Federation
Commander 3C3: only to an adjacent shield, only to replace what damage took,
never above the original strength. Both live in `ShipState`, so the AI can use
them the moment it is taught to.

Every ship has six independent shield facings mapped to the hex-like arrangement around
the hull:

```
            FORE
       ╱ 1 ╲   ╱ 2 ╲
   PORT│ 6 │ SHIP │ 3 │STBD
       ╲ 5 ╱   ╲ 4 ╱
            AFT
```

- Each facing has its own **strength** and **regen**, and takes damage independently.
- Regen is fed by the SHIELDS allocation and split by a player-set **bias** (e.g. 60%
  forward while charging in, flipped while withdrawing).
- **Reinforcement:** dump battery power into one facing for a short, large temporary boost.
  The classic panic button; costs your burst reserve.
- When a facing hits 0, further hits on that arc go to **hull and internals**. Facings
  don't "break" permanently. They regen, if you can buy time by turning a fresh face to
  the enemy.

**"Shield tanking" by rotation** is the intended core defensive skill: constantly turning
so your strong facing eats fire while a spent one recovers. That is the fight.

Most hulls also mount **armor** on specific facings: flat damage reduction that applies
after shields collapse, doesn't regenerate, and is repaired at a yard. Armor is how heavy
hulls survive; it costs mass, which costs speed.

---

## 5. Weapons

Every weapon occupies a **mount**, and the mount owns the **arc** (see
[02-ship-construction.md](02-ship-construction.md) §4). Bearings are 12 sectors of 30
degrees, and each shield facing is exactly two sectors, so resolving which facing a shot
strikes is a lookup rather than angle math.

Firing requires: target within range, target inside one of the mount's sectors, and
capacitor charged. The **firing envelope** is therefore the mount's arc intersected with
the weapon's range, which is exactly the wedge the fitting screen draws.


### 5.0 Controls, and touch

The game is built for a mouse and keyboard: click the plane to set a heading, drag to
orbit, and use the action row. **Touch is a testing surface, not the primary one.** On a
device with a touchscreen the combat view adds an overlay: a left stick that turns the
ship, a right stick that moves the camera through the same clamp the mouse uses, and
previous and next target buttons. Throttle and the power split stay on their sliders.

Target selection lives in the simulation (`Battle.target_for`), not in the overlay, so the
buttons cycle the same thing a shot resolves against and a squadron UI will reuse it
unchanged.

### 5.1 Direct-fire energy

| Family | Behavior |
|---|---|
| **Beam batteries** | Instant hit, damage falls off with range, wide arcs, cheap power. The reliable baseline. |
| **Disruptor banks** | Punchy at medium range, narrow arc, higher power draw, can **overload** for ~2× damage at half range and a heavy capacitor cost. |

**Range falloff is a table, not a curve.** Every weapon in `data/weapons.json` carries a
`falloff` list: bands from point blank outward, each with the damage a hit scores and the
chance the shot connects at all. `src/sim/weapon_model.gd` is the only code that reads it,
so the fitting screen's projected alpha, the arc wheel's radius, and a real shot in a
battle cannot disagree.

The three shapes are inherited from Federation Commander, see
`docs/09-reference-federation-commander.md`:

| Shape | Accuracy with range | Damage with range | Feels like |
|---|---|---|---|
| Beams, phasers | Unchanged, they always connect | Falls steadily | Reliable, and worth closing for |
| Torpedoes | Falls | Unchanged, a hit is a hit | All or nothing at long range |
| Disruptors | Falls | Falls | Punishing to trade with at distance |

Two consequences the fitting screen must state plainly: **alpha strike is a point blank
figure**, the best case, and expected damage at a chosen range is the honest comparison
between two designs. `ShipFit.expected_into(sector, distance)` is that number.
| **Lance/spinal mounts** | Extreme damage, forward-only, very long charge, huge power. Battleship/dreadnought only. |
| **Point defense** | Auto-firing, short range, only engages seeking weapons and fighters. |

### 5.2 Seeking weapons

| Family | Behavior |
|---|---|
| **Plasma torpedoes** | Slow-moving, enormous damage, degrades over flight distance, killable by point defense. Fired *ahead* of where the enemy will be. |
| **Drone/missile racks** | Limited ammunition, pursue autonomously, can be shot down, can be **re-targeted** mid-flight. Ammo count is a fitting decision. |

**Seeking weapons are launched, not fired.** A weapon with `seeking` in
`data/weapons.json` puts a `Seeker` on the plane instead of resolving damage:
it flies at its own speed toward wherever the target is now, and it carries hit
points. Anything hostile with `point_defense` in range shoots it for free,
without spending its own capacitor, which is what makes a light beam worth its
space. A seeker that arrives resolves through the same `apply_damage` a beam
does, on the facing it arrived through. One that is shot down or runs out of
fuel says so in the comm log.

This is the distinction Federation Commander draws in 4F: direct fire is a die
roll, seeking weapons are counters on the map that move until they arrive or
die. See `docs/09-reference-federation-commander.md`.
| **Mines** | Deployed, area denial, invisible until triggered. Great for chokepoint and station defense. |

Seeking weapons create the game's most interesting pressure: a plasma torpedo in the water
forces the target to *spend* something: thrust to evade, point defense power, or a shield
facing. Damage is almost secondary to the tempo it steals.

### 5.3 Special mounts

- **Tractor beam**: lock a target, drag it, prevent it fleeing, hold it for boarding.
  Contestable: the target can fight the lock with their own tractor or engine power.
- **Transporters**: deliver marines, snatch cargo, or run **hit-and-run raids** (beam a
  small team aboard to sabotage one subsystem, then recall). Requires the target's facing
  shield to be down.
- **Shuttle/fighter hangars**: launch small craft; screening, alpha strike, or point
  defense soak. Sarn Concordance doctrine centerpiece.
- **Cloaking device**: near-invisibility at heavy sustained power cost, cannot fire while
  cloaked, brief vulnerable window on decloak. Vaelith Ascendancy centerpiece.

---

## 6. Sensors, ECM, ECCM

Information is a resource.

- **Sensor range** by computer tier; nebulae and jamming cut it.
- **ECM** raises the enemy's chance to miss and degrades their seeking-weapon locks.
- **ECCM** counters enemy ECM.
- Both consume SYSTEMS power, i.e. **information warfare competes directly with weapons
  and shields.** A jamming build is choosing to be harder to hit instead of hitting harder.
- **Lock quality** is a spectrum: unaware → contact → tracked → firing solution. Long-range
  and seeking weapons need better locks than short-range beams.

---

## 7. Damage Model

Damage resolves in a strict order:

```
  incoming hit
      ↓
  facing determined by attack vector (which of the 6 arcs)
      ↓
  SHIELD on that facing absorbs (reduced by shield-piercing weapons)
      ↓
  ARMOR on that facing reduces remainder
      ↓
  HULL integrity takes remainder
      ↓
  INTERNALS: each point of hull damage rolls against the internal allocation table
```

### Internals

Every ship has an **internal allocation table** derived from what's actually fitted.
A ship that fitted four reactors is *more likely* to take reactor hits. Your build
determines your own vulnerability profile, which is an elegant, emergent consequence.

Damageable internals: reactors, power conduits, each weapon mount, each shield generator,
engines, sensors/computers, tractors, transporters, hangars, marine barracks, cargo hold,
crew quarters, bridge, damage-control teams.

Effects are specific, not abstract:

| Hit | Consequence |
|---|---|
| Reactor | Permanent -N total power for the scenario |
| Conduit | Power reallocation ramp gets slower |
| Weapon mount | That specific weapon offline (may be repairable) |
| Shield generator | That facing's max strength and regen drop |
| Engine | Thrust/turn/max-speed loss |
| Sensors | Range and lock quality drop |
| Crew quarters | Crew casualties → all systems degrade slightly |
| Bridge | Command penalty; officer injury risk; possible loss of squadron orders |

### Damage Control

Crews repair during combat. Player sets **repair priority** (or the engineering officer
does it automatically, better with a better officer). Only some hits are field-repairable;
the rest need a yard. This makes mid-fight triage a real decision: fix the shield
generator or the weapon?

### Crippled and destroyed

- At low hull, a ship becomes **crippled**: severe penalties, effectively combat-
  ineffective, still alive, still capturable, still able to run.
- **Destruction** is the explicit end state; hulls destroyed in battle are gone.
- **Escape pods** launch on destruction. Recovered pods save your officers and part of
  your crew. Enemies can *deny* recovery. This is a real, nasty, excellent decision point.

---

## 8. Boarding & Capture

The full loop, since capture is a design pillar (GDD §7).

### Preconditions
1. Target's shield facing on your approach vector is at **0**.
2. Target within **transporter range** (short, so you must commit to being close).
3. Maintain **transporter lock** through their ECM.
4. Optionally hold them with a **tractor beam** so they can't break range.

### Resolution
Boarding is an attritional contest resolved in rounds while conditions hold:

```
  attacker: marines beamed × marine officer skill × marine equipment tier
  defender: marines aboard + armed crew × crew quality × defensive bonus
```

- Attacker wins a round → defender loses marines/crew, attacker gains a **foothold**;
  footholds accumulate toward control of engineering, then the bridge.
- Defender wins → attacking marines are lost. Marines are a **finite, expensive resource**
  that must be replaced at a station.
- Control of engineering disables the target's power. Control of the bridge **strikes their
  colors**: the ship is yours.

### Defender counterplay
Break range · reinforce that facing · ECM the lock · counter-tractor · commit their own
marines · vent compartments (kills marines and their own crew) · **self-destruct** (denies
the prize, and is often the correct call).

### Aftermath
1. **Hold the prize** to the end of the scenario, with enough surviving crew to sail it.
2. **Tow** it across the galaxy layer to a friendly yard: slow, visible, contestable.
   This is deliberately dangerous; retaking a prize is premium emergent content.
3. **Disposition** at the yard: fly it (foreign-tech upkeep penalty) · strip it for
   components · **study it to unlock the blueprint**.

### Hit-and-run raids
A lighter version: beam a small team aboard to sabotage *one* subsystem, then recall them.
Cheap, fast, doesn't require winning a boarding war. The signature move of light raiders
and the reason transporters are worth mass on a small hull.

---

## 9. Squadron Command

You bring up to 6 capital ships. You are one captain.

- **Flagship:** directly controlled.
- **Consorts:** operate on **standing orders**: formation station, engagement range,
  target priority, energy doctrine preset, withdrawal threshold.
- **Command interface:** a squadron bar; select a ship to inspect or re-order. In PvE you
  pause to do this; in PvP you do it live, which is the real pressure.
- **Hot-swap** (pending decision, GDD §11.1): take direct control of any consort, with a
  brief control-transfer lag to prevent frame-perfect ship-juggling.
- **Officer quality drives AI competence.** A consort with a good tactical officer manages
  its own shield rotation and power well. A bad one flies into a plasma torpedo. This makes
  officers matter *mechanically* rather than as a stat tax, and it means investing in your
  consorts' crews is a real strategic choice.

**Multi-player battles:** each player brings their own squadron, subject to the instance
cap. A fleet commander role can issue *advisory* objectives (marks, focus targets, hold
lines) that players may follow or ignore. There is never forced control of another player's ships.

---

## 10. Scenario Types

Battles are not all "kill the other fleet." The scenario type comes from *why* the
encounter happened on the galaxy layer.

| Scenario | Objective | Source |
|---|---|---|
| **Fleet Action** | Destroy or rout the enemy squadron | Two squadrons meet |
| **Convoy Raid** | Attacker destroys/captures freighters; defender escorts them off-map | Raid on a trade route |
| **Blockade Run** | Cross the map under fire; survival matters more than kills | Running a besieged hex |
| **Station Assault** | Reduce a station's defenses and shield arcs; garrison + platforms defend | Siege of an installation |
| **Planetary Strike** | Suppress orbital defenses, land marines, hold orbit | Colony assault |
| **Salvage Contest** | Both sides race to secure derelicts in a wreck field | Contested wreck field hex |
| **Anomaly Encounter** | PvE/exploration; unknown rules, no reinforcement, high reward | Exploration event |
| **Bloom Incursion** | Survive escalating waves; hold the line | NPC threat pushing a front |

Objective-based scenarios are what keep the tactical layer from staling. "Escort four
freighters off the east edge while a Kthaari raider group hunts them" is a fundamentally
different fitting and power-management problem than a straight fleet fight, and *that*
variety is what makes the shipyard worth revisiting.

---

## 11. Outcome & Write-back

Every scenario emits an authoritative result to the galaxy layer:

- Ships destroyed / crippled / captured on both sides (persistent, real losses)
- Officer casualties and injuries
- Marines expended
- Ammunition and consumables spent
- Salvage recovered (components, alloys, intel, blueprint fragments)
- **Prestige** awarded, weighted by objective completion and *tonnage disadvantage*, so
  winning while outmatched pays far better than curb-stomping
- **Hex pressure** applied toward control of the contested hex
- Trade-route damage, station damage, colony status changes

Withdrawal is always a legitimate, supported outcome. A squadron that disengages early
keeps its hulls and concedes pressure. **Making retreat viable is what makes the strategic
layer breathe**. If every contact is to the death, nobody ever leaves home.
