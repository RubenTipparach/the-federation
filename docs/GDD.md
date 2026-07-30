# The Federation — Game Design Document

**Version:** 0.1 (pre-production draft)
**Engine:** Godot 4
**Backend:** Fly.io
**Genre:** Persistent-world tactical space MMO / 4X hybrid

---

## 1. High Concept

> You are not an admiral moving icons on a map. You are a captain who *built the ship
> you're standing on* — chose its hull, cut a shield generator to fit a fourth torpedo
> tube, hand-picked the officer running its engine room — and who now has to answer for
> that decision in a fight where every erg of power is a choice.

**The Federation** is a space MMO with two interlocking layers:

- **The Galaxy** — a persistent map of roughly 3,000 hexagons, contested continuously by
  six factions of real players. Hexes are claimed, supplied, colonized, traded through,
  raided, and lost. This layer runs 24/7 and does not stop when you log off.
- **The Battle** — when opposing forces meet in a hex, the encounter resolves as an
  instanced tactical scenario. You command a squadron of up to **6 capital ships**,
  fighting with real-time-with-pause energy management, six-facing shields, subsystem
  destruction, tractor beams, and boarding actions.

Between them sits **the shipyard**, where the actual game lives.

---

## 2. Design Pillars

### P1 — The ship is the character

There is no avatar progression ladder. Your progression is a *hangar*: hulls you've
unlocked, blueprints you've captured, officers you've trained, refits you've paid for.
A veteran player and a new player in identical hulls with identical loadouts are near-
equals in a fight — the veteran's advantage is that they own better hulls, better
officers, and a design they've iterated on fifty times. **Time invested buys options,
not raw stat inflation.**

### P2 — Every build is a sacrifice

Hull space, power output, crew berths, and mass are four separate hard budgets that pull
against each other. There is no configuration that is good at everything. A ship that
brawls cannot chase. A ship that can chase cannot take a hit. A ship that boards is
carrying marines instead of ammunition. **The interesting question is never "what's
best" — it's "what am I giving up".**

### P3 — Power is the real weapon

Combat is won at the energy allocation panel, not the trigger. Reactor output is finite
and must be split live between weapon capacitors, shield reinforcement, engine thrust,
and special systems. Overloading a disruptor bank means your shields sag for four
seconds. Running silent means you can't shoot. **Positioning + power = damage.** Raw DPS
is a rounding error.

### P4 — Loss is meaningful but not ruinous

Ships die. When yours does, you lose the hull, the fittings, and possibly officers.
You do not lose your blueprints, your rank, your yard, or your account's progress. The
stakes are high enough that a fleet action feels like a fleet action, and low enough
that losing one does not end your week.

### P5 — The map remembers

Every battle result writes to the strategic layer. A raid that burns a convoy actually
starves the shipyard that convoy was feeding. Territory taken stays taken until someone
takes it back. **Nothing resets nightly.**

---

## 3. Player Fantasy & Target Audience

**Primary audience:** players who bounced off modern space games for being either too
shallow (arcade dogfighters) or too punishing in the wrong dimension (full-loot sandbox
grief). Specifically:

- Players who remember SFC/SFB-style tactical depth and have nowhere to get it.
- Ship-builder/optimizer players (the *Battletech* mech-bay audience, the *KSP* audience,
  the EVE fitting-tool audience).
- Guild-scale strategy players who want their coordination to visibly move a map.

**Not** targeting: twitch-reflex PvP, mobile-idle, or solo-only campaign players.
Skill expression here is *decision quality under time pressure*, not APM.

**The three sentences a happy player says:**
1. "Let me show you what I did with this hull."
2. "We held the corridor for six hours."
3. "That cruiser is mine now — I took it off them at Vheln Reach."

---

## 4. Core Loops

### 4.1 Session loop (30–90 min)

```
   log in → check yard queue & route income
      ↓
   pick a purpose: raid / escort / patrol / explore / haul
      ↓
   move squadron across hexes (strategic layer, real-time, low attention)
      ↓
   CONTACT → instanced battle scenario (high attention, 10–25 min)
      ↓
   outcome: salvage, prestige, captured hulls, casualties, hex pressure
      ↓
   return to yard → repair, refit, iterate the design
      ↓
   (loop, or log off — the map continues)
```

### 4.2 Progression loop (weeks)

```
   fight → prestige + salvage + captured blueprints
      ↓
   unlock hull tiers / component tiers / officer slots
      ↓
   build a better squadron
      ↓
   contest higher-value hexes (better resources, better yards)
      ↓
   fund bigger stations and longer trade routes
      ↓
   fight bigger fights
```

### 4.3 Faction loop (months, community-scale)

```
   faction pushes a front → takes hexes → gains resource access
      ↓
   new hull lines / doctrine techs unlock faction-wide
      ↓
   overextension: supply lines get long and raidable
      ↓
   rival factions counter-raid the lanes
      ↓
   front stabilizes or collapses → seasonal narrative beat
```

The faction loop is what makes this an MMO rather than a lobby game with a shared
scoreboard. See [04-galaxy-and-territory.md](04-galaxy-and-territory.md).

---

## 5. The Three Layers

### 5.1 Shipyard (asynchronous, offline-safe)

Where players spend a surprising amount of their playtime, and by design. Full detail in
[02-ship-construction.md](02-ship-construction.md) and
[03-officers-and-crew.md](03-officers-and-crew.md).

- Buy/unlock **hulls** (the chassis: mass, space, hardpoints, base power, berths).
- Fit **weapons** into hardpoints, each with a firing **arc**.
- Fit **subsystems**: shield generators, engines, reactors, computers/fire control,
  ECM/ECCM, tractors, transporters, cloaks, hangars, marine barracks, cargo.
- Assign **bridge officers** (helm, gunnery, engineering, tactical, science, marine CO)
  and set **crew quality** by paying for training.
- Save as a **design**; queue construction at an owned or allied yard; wait real time.
- **Blueprints** gate what you may build. Some are faction-issued by rank; some are
  researched; some are **taken off a ship you captured**.

### 5.2 Galaxy (persistent, always-on, low attention)

Full detail in [04-galaxy-and-territory.md](04-galaxy-and-territory.md) and
[05-economy-and-expansion.md](05-economy-and-expansion.md).

- ~3,000 hexes on a flat-top hex grid, grouped into ~40 **sectors**.
- Each hex has terrain (deep space, nebula, asteroid field, ion storm, gravity well,
  wreck field), a **strategic value**, optional planets/anomalies, and an owner.
- Squadrons move hex-to-hex in real time (minutes per hex, faster on friendly supplied
  hexes, slower in hazards).
- Contact with a hostile squadron or installation triggers a battle scenario.
- **Supply** propagates from owned stations; unsupplied hexes cost you repair speed,
  reinforcement rate, and eventually attrition.
- Hex control shifts by accumulated **pressure** from battle outcomes, not by one fight.

### 5.3 Battle (instanced, real-time-with-pause, high attention)

Full detail in [01-tactical-combat.md](01-tactical-combat.md).

- 2D plane, top-down, Newtonian-*ish* (momentum + turn rate, but with a speed cap so
  fights stay readable). Slow, weighty capital ship movement.
- Up to **6 capital ships per side** per player squadron; multi-player battles support
  multiple squadrons up to an instance cap (target: 24 capital ships + escorts).
- Direct control of your **flagship**; the rest of the squadron takes standing orders and
  can be micromanaged during **tactical pause**.
- Six shield facings, energy allocation, capacitor charging, seeking weapons,
  subsystem-level internal damage, tractor beams, transporters, boarding, and capture.
- Battles are **10–25 minutes** and end in decisive states (destroyed, crippled,
  captured, withdrawn) that write back to the galaxy layer.

---

## 6. Factions

Six playable factions. Each is a **doctrine**, not a stat block — the differences are in
what their component families are good at, which forces different fitting decisions.

| Faction | Doctrine | Signature | Weakness |
|---|---|---|---|
| **Terran Concord** | Balanced generalist, strong logistics | Multi-arc beam batteries, best shield tech, best repair | No standout edge; expensive per hull |
| **Kthaari Dominion** | Aggressive attrition, heavy hulls | Disruptor banks + drone racks, huge marine complements | Poor sensors, slow turn rate, weak rear arcs |
| **Vaelith Ascendancy** | Ambush and alpha strike | Cloaking, plasma torpedoes, high burst | Fragile hulls, poor sustain, terrible if caught decloaked |
| **Sarn Concordance** | Swarm and control | Fighter hangars, tractor webs, area denial | Weak individual hulls, hangar dependency |
| **Helion Combine** | Modular mercantile industry | Cheapest hulls, most hardpoint flexibility, best cargo/trade | Lowest ceiling per hull; needs numbers or economy |
| **The Bloom** *(NPC/PvE)* | Non-negotiating hostile force | Regenerating organic hulls, no salvageable tech | — |

**Faction is chosen at account creation and is semi-permanent** (a costly, cooldowned
defection path exists to let dead servers rebalance). Cross-faction diplomacy is
*emergent, not systemic*: no formal alliance mechanic, but ceasefires happen because
players honor them.

The Bloom exists so that (a) PvE players have a career, (b) faction fronts have a common
threat that can force temporary truces, and (c) seasonal narrative pressure has a source.

---

## 7. Ship Capture — a first-class pillar

Capture is called out separately here because it is the mechanic that ties all three
layers together, and it must not be a novelty.

**In battle:** collapse a facing's shield → get within transporter range → hold a
transporter lock → beam marines aboard → win the internal boarding fight against their
crew and marines → the ship strikes its colors. Defender countermeasures: shield
reinforcement on that facing, ECM against lock, breaking range, their own marines, and
self-destruct (which denies you the hull but not the prestige).

**At battle end:** a struck ship becomes a **prize**. You must survive to the end of the
scenario still holding it, with enough surviving crew to sail it, or it's scuttled.

**On the galaxy layer:** a prize must be **towed** to a friendly yard — slow, visible on
the map, and a screaming invitation for the previous owner to come take it back. This
generates some of the best emergent content in the game.

**In the shipyard:** a delivered prize can be
- **refitted and flown** (with an upkeep penalty for operating foreign tech), or
- **stripped** for the enemy components, or
- **studied** to unlock the enemy **blueprint** — the most valuable outcome, and the only
  way to fly a rival faction's hull line legitimately.

Design intent: a well-built, marine-heavy boarding cruiser is a *viable specialist
archetype*, not a gimmick. Capture is also the answer to "what do I do with a fight I
can't win outright" — take one hull and leave.

---

## 8. Monetization & Business Model *(placeholder position)*

Stated so it constrains design early rather than being retrofitted:

- **Buy-to-play or subscription. Not free-to-play.** The design is built on symmetric
  power; selling power breaks P1 and P2 outright, and selling *time* (build queue skips,
  repair skips) breaks P4.
- Acceptable: cosmetics (hull paint, decals, bridge/UI skins, name registries), extra
  design-slot storage, account-level convenience that does not touch combat math.
- **Hard no:** premium hulls, premium components, premium officers, XP boosters, repair
  skips, build-queue skips, insurance.

This is not final and is out of scope for the vertical slice, but it is a *design
constraint* from day one.

---

## 9. What This Game Is Not

Explicit anti-goals, to keep scope honest:

- **Not a flight sim.** No cockpit, no 6DOF, no manual aiming of every weapon.
- **Not full-loot open PvP everywhere.** Core faction space is safe-ish; danger scales
  with distance from home and with the value of what you're doing.
- **Not seamless single-shard space.** Combat is instanced. Accept it; it's what makes
  the tactical layer possible.
- **Not a 3D-space game.** Combat is on a 2D plane. This is a deliberate design choice
  inherited from the reference, not a limitation — shield facings, arcs, and crossing
  the T are only legible in 2D.
- **Not skill-tree-based.** No character levels. See P1.
- **Not a 100-ship RTS.** Squadron cap of 6 is a design constraint, not a placeholder.
  It exists so each ship can be individually deep.

---

## 10. Reference Analysis — what we're actually taking

| From | Take | Leave |
|---|---|---|
| SFC1 (1999) | Energy allocation, shield facings, internal damage, real-time-with-pause pacing | Single-player-only structure |
| SFC2 (2001) | Dynaverse persistent campaign map, prestige-funded refit economy, hull-line progression | Prestige as a hard gate that strands players |
| *Star Fleet Battles* lineage | Weapon arcs, seeking weapons, hit-and-run raids, boarding | Any literal rules, tables, terminology, or setting (IP) |
| Modern MMOs | Guild-scale territory, asynchronous industry, session-friendly loops | Gear treadmills, power creep, F2P power sales |

**The specific thing SFC did that nothing else does:** it made a fight between two ships
into a twenty-minute conversation about power, angles, and attrition. Preserving *that
feeling* is the project's actual success criterion. If the tactical layer isn't fun with
exactly two ships and no meta-game attached, nothing built on top of it will save it.

---

## 11. Open Design Questions

Tracked here rather than resolved prematurely.

1. **Squadron control fidelity.** Direct-control-flagship + orders for the other five, or
   free hot-swap between all six? Hot-swap is more expressive but risks reducing five
   ships to "the ones I'm not driving." *Leaning: hot-swap with a control-lag penalty.*
2. **Tactical pause in PvP.** Pause is core to the single-player reference and impossible
   in PvP. Options: (a) no pause in PvP, slower base timescale to compensate;
   (b) shared consensual pause; (c) slow-motion "command mode" on a cooldown budget.
   *Leaning: (a), with the base timescale tuned so PvE and PvP feel the same speed.*
3. **Offline vulnerability.** Can a player's stations/colonies be attacked while offline?
   Necessary for a real strategic layer; toxic if unlimited. *Leaning: installations are
   attackable but only degrade, never delete, and have a defense window mechanic.*
4. **Death of officers.** Permadeath for named officers raises stakes and risks making
   players hoard and never fight. *Leaning: injury + recovery time by default,
   permadeath only on total ship loss with no escape pods.*
5. **Instance cap vs. fleet battles.** 24 capital ships is a guess. Needs a load test
   before the strategic layer commits to letting 200 players converge on one hex.
6. **Server topology per region.** One galaxy globally (latency pain for distant players)
   or a galaxy per region (splits the population)? See
   [06-technical-architecture.md](06-technical-architecture.md) §8.

---

## 12. Document Map

- [01-tactical-combat.md](01-tactical-combat.md) — the battle layer
- [02-ship-construction.md](02-ship-construction.md) — the shipyard
- [03-officers-and-crew.md](03-officers-and-crew.md) — the people
- [04-galaxy-and-territory.md](04-galaxy-and-territory.md) — the hex map & war
- [05-economy-and-expansion.md](05-economy-and-expansion.md) — trade, stations, colonies, exploration
- [06-technical-architecture.md](06-technical-architecture.md) — Godot + Fly.io
- [07-roadmap.md](07-roadmap.md) — build order & risks
