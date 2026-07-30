# 02. Ship Construction & Customization

**The centerpiece system.** If a player spends an hour in the shipyard and enjoys it more
than the fight, that's not a failure. That's the design working.

---

## 1. Design Goals

1. **Legible depth.** A new player can fit a workable ship in five minutes. A veteran can
   spend an hour on the same hull and produce something meaningfully better.
2. **No dominant build.** Enforced by *multiple simultaneous budgets* (§3) plus a
   rock-paper-scissors-ish weapon/defense triangle, not by hand-nerfing.
3. **Builds are readable in combat.** An opponent should be able to infer roughly what
   you're carrying from how you fly and what you do, and be punished for guessing wrong.
4. **The build is an identity.** Named designs, shareable, versioned, with a lineage.
   Players should be *known* for a design.

---

## 2. Hulls

The hull is the chassis. It is the one thing you cannot change about a ship.

Each hull defines:

| Property | Meaning |
|---|---|
| **Class** | Frigate → Destroyer → Light Cruiser → Heavy Cruiser → Battlecruiser → Battleship → Dreadnought (+ Carrier, Freighter, Tender variants) |
| **Mass** | Base mass; drives thrust/turn requirements |
| **Internal space** | The primary fitting budget (§3) |
| **Base power** | Free power before any reactors are fitted |
| **Hardpoints** | Fixed list of mounts, each with size and arc (§4) |
| **Shield facing caps** | Max shield strength per facing, regardless of generators |
| **Armor facings** | Which facings can mount armor, and how much |
| **Berths** | Crew + marine capacity ceiling |
| **Hull integrity** | Structural HP |
| **Internals slot map** | Which internal categories can be fitted and how many |

**Hull lines** are faction-flavored and progress by *variant*, not by strict power. A
Kthaari heavy cruiser and a Terran heavy cruiser cost similar and sit at the same tier;
they are shaped completely differently. Within a line, later variants trade one thing for
another (the "-B refit" pattern) rather than being flatly better.

### Squadron tonnage budget

A squadron is limited by **command tonnage**, not just ship count. Rank raises your
tonnage ceiling. So the 6-ship cap interacts with tonnage:

- 6 destroyers, or
- 2 battlecruisers and 2 escorts, or
- 1 dreadnought and nothing else.

This makes "how many ships" a genuine strategic decision and keeps low-tier hulls
permanently relevant: a screen of cheap escorts is often correct.

---

## 3. The Four Budgets

Fitting is constrained by four independent budgets. **This is the heart of the system**.
Optimizing any one budget alone always produces a bad ship.

```
  ┌─ SPACE ──── internal volume. Almost everything costs space.
  ├─ POWER ──── reactor output vs. sum of all systems' demand.
  ├─ MASS ───── total mass vs. engine thrust → speed and turn rate.
  └─ CREW ───── berths vs. crew required to operate all fitted systems + marines.
```

Why four and not one:

- Add reactors for power → they cost **space** and **mass**.
- Add engines to fix the mass → they cost **space** and **power**.
- Add weapons → they cost **space**, **power**, **mass**, and **crew** to operate.
- Add marines for boarding → they cost **berths** you needed for weapon crews.
- Cut crew to make room → remaining systems operate at reduced efficiency.

Every fix creates a new problem somewhere else. There's no closed-form optimum, which is
exactly what keeps players in the shipyard.

### Undermanning

If crew required exceeds crew aboard, the ship still functions but at reduced efficiency
across the board: slower reloads, slower damage control, worse boarding defense. This is
a *legitimate strategy* (a deliberately skeleton-crewed alpha-strike ship) rather than an
error state, which is a nice source of build diversity.

---

## 4. Hardpoints & Arcs

Weapons go in hardpoints. Hardpoints are **fixed by the hull**: you cannot add or move
them. This is the primary reason hull choice matters.

Each hardpoint has:

- **Size**: Light / Medium / Heavy / Spinal. A weapon fits its size or smaller
  (with wasted capacity), never larger.
- **Arc**: the firing cone, expressed against the six facings.

```
  Arc types:
    FA   Forward only            (60°)   : lances, spinal mounts
    FX   Forward extended       (120°)   : main disruptor banks
    FP/FS Forward port/stbd      (90°)   : asymmetric broadside mounts
    LS/RS Left/right broadside  (180°)   : beam batteries
    RA   Rear                    (120°)  : retreat guns, mine layers
    360  Full turret             (360°)  : expensive, low damage, point defense
```

**Arc management is the tactical skill the fitting screen sells you.** A ship with
everything in FA is a hammer that must be pointed; a ship with broadsides wants to circle;
a 360 turret build has no bad angle and no punch. The shipyard is where you decide which
kind of fight you're going to be able to have.

The fitting UI renders your combined arc coverage as an overlay, with a **damage-by-angle
rose** so you can see your blind spots before an enemy finds them.

---

## 5. Internal Systems

Fitted into the hull's internal slot map. All cost space; most cost power, mass, and crew.

### Power
- **Reactors**: the power budget. Tiers trade output vs. space/mass vs. **damage
  volatility** (high-tier reactors do secondary damage when destroyed).
- **Batteries**: burst reserve. More batteries = more overloads and emergency reinforces.
- **Power conduits**: reallocation ramp speed. Underrated; a high-conduit ship reacts
  fast, which is worth more than raw output in a knife fight.

### Defense
- **Shield generators**: strength and regen per facing. Can be biased toward specific
  facings at fitting time (a forward-heavy assault ship).
- **Armor plating**: per-facing flat reduction, no regen, heavy mass cost.
- **Damage control teams**: in-combat repair rate and number of concurrent repairs.

### Mobility
- **Engines**: thrust, turn rate, max speed, all vs. total mass.
- **Maneuvering thrusters**: turn rate specifically; cheap way to fix a sluggish hull.
- **Warp/jump drive**: strategic-layer speed between hexes. Cheap to fit, easy to
  under-invest in, and then your squadron is late to every fight in the war.

### Information
- **Computer/fire control**: accuracy, lock quality, number of simultaneous targets.
- **Sensor array**: detection range, cloak detection.
- **ECM / ECCM suites**: jamming and counter-jamming.

### Special
- **Tractor beams**: hold targets, resist being held, tow prizes.
- **Transporters**: marines, hit-and-run raids, cargo snatching. Count = throughput.
- **Cloaking device**: enormous space/power cost; entire builds bend around it.
- **Hangar bays**: fighters/shuttles/bombers. Needs deck crew (berths) and ordnance space.
- **Marine barracks**: boarding capacity and boarding defense.
- **Cargo holds**: trade capacity, salvage capacity, ammunition reserve.
- **Repair bay**: repair *other* ships between battles; makes tenders viable.
- **Colony/construction module**: required to found colonies and build stations. See
  [05-economy-and-expansion.md](05-economy-and-expansion.md).

---

## 6. Component Tiers & Families

Components exist on two axes:

- **Tier (1-5)**: flatly better, gated by blueprint access and rare materials. Vertical.
- **Family**: a *sideways* choice within a tier.

Example, Tier 3 shield generators:

| Family | Strength | Regen | Space | Power | Note |
|---|---|---|---|---|---|
| Standard | 100 | 100 | 100 | 100 | Baseline |
| Reinforced | 130 | 70 | 120 | 110 | Tank a burst, recover slowly |
| Recursive | 80 | 140 | 100 | 130 | Shield-rotation builds |
| Compact | 85 | 90 | 70 | 100 | Buy space for something else |
| Hardened | 100 | 90 | 110 | 100 | Resists shield-piercing |

**Families are how build diversity survives tier progression.** Tier 5 doesn't collapse
into one right answer, because the family choice is still a real trade at every tier.

Faction access is asymmetric: Terrans get the best Standard/Reinforced lines, Vaelith get
Recursive, Helion get Compact. This makes captured foreign components genuinely desirable
and gives the capture pillar economic teeth.

---

## 7. Designs, Blueprints, Construction

### Blueprints
Blueprints gate what you *may* build. Sources:
- **Faction issue**: unlocked by rank/prestige. The reliable path.
- **Research**: spend resources and time at a station with a research module.
- **Salvage**: blueprint *fragments* from wrecks; collect a set to reconstruct.
- **Capture**: study a captured hull to unlock the enemy's blueprint outright (§GDD 7).
  The most valuable and most fun acquisition route.

### Designs
A **design** is a saved, named, validated fitting of one hull. Designs are:
- **Versioned**: `Wayfarer Mk III`, with a visible revision history.
- **Shareable**: export/import as a code; a community meta emerges immediately.
- **Costed**: the UI shows credits, materials, build time, and crew required up front.
- **Simulatable**: dry-dock test-fires against a target dummy or a scripted opponent
  *before* you commit resources. This is non-negotiable for the fitting loop to be fun;
  iteration must be cheap and immediate.

### Construction
1. Queue a design at an owned/allied **shipyard station** (§05).
2. Consume credits + materials; materials must be *present at that station*, which is what
   makes trade routes matter.
3. Wait **real time** (minutes for a frigate, many hours for a dreadnought). Yard tier and
   parallel slips reduce this.
4. Ship is delivered to that station. Crew is assigned. Officers are appointed.

### Refit
Changing an existing ship's fitting at a yard: cheaper and faster than new construction,
but bounded: you can swap components freely; you cannot change hull or hardpoints. This
is the "prestige-funded refit" loop from the reference, and it's where most of a player's
ongoing spend goes.

**Field refit** is a limited version available at a supplied hex with a tender present:
swap a small number of components, no structural work. Keeps long deployments viable.

---

## 8. Cost & Repair Economy

Two currencies with distinct jobs:

- **Credits**: earned from trade, salvage, contracts. Buys hulls, components, crew,
  repairs. Fungible, tradeable between players.
- **Prestige**: earned only from combat and objectives. Buys **rank** (→ command tonnage,
  blueprint access, station permits). Non-tradeable. This is your military standing.

You cannot buy your way to a dreadnought with trade money alone, and you cannot fund a fleet
on prestige alone. Both careers are necessary and both are viable to specialize in.

**Repair** costs credits and time, scaled by damage type: hull is cheap, internals moderate,
destroyed components must be re-bought. Full loss means the hull and everything on it, but
never blueprints, rank, or designs (pillar P4).

---

## 9. Shipyard UI: Requirements

The fitting screen is the most-used screen in the game. It must be excellent.

**Must have:**
- Live budget bars (space / power / mass / crew) with **projected** values as you hover a
  component, before you commit.
- The **arc rose**: damage-by-angle overlay, updating live.
- A **derived-stats panel**: alpha strike, sustained DPS, effective HP per facing, time to
  turn 180°, max speed, sensor range, boarding strength.
- **Compare mode**: two designs side by side with a stat delta.
- **Dry-dock simulation**: test-fire before spending.
- **Undo/redo and named revisions.** Players will iterate dozens of times per session.
- **Copy-fit** from any design you own or have imported.

**Must not have:**
- A single "power score" number. It would flatten the entire four-budget design into a
  scalar and every player would just optimize that number. Show the trade-offs; never
  summarize them away.

---

## 10. Anti-Degeneracy Rules

Known failure modes and their designed answers:

| Failure mode | Answer |
|---|---|
| One dominant fit copied by everyone | Four budgets + component families + arc constraints + scenario variety |
| Max-tier everything trivializes lower tiers | Tier gated by *materials* (supply-line dependent), plus command tonnage caps |
| Glass cannon dominance | Alpha-strike fits can't sustain; scenarios have objectives and timers, not just kills |
| Turtle stalemates | Scenario timers, objective scoring, and shield-piercing weapon families |
| Fitting-screen paralysis | Faction preset designs available at every tier as a starting point |
| Veterans unbeatable by design knowledge | Public design sharing means the meta is *known*; the edge is execution and logistics |
