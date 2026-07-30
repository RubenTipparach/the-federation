# 04. The Galaxy & Territory

The persistent strategic layer. Always running, never resetting, low attention cost per
minute. That is what makes this an MMO rather than a matchmaker.

---

## 1. Structure

- **~3,000 hexes** on a flat-top hex grid (axial coordinates `q, r`).
- Grouped into **~40 sectors** of 60-100 hexes. Sectors are the unit of narrative,
  faction objectives, and server sharding (see [06](06-technical-architecture.md) §4).
- Six **faction cores** (one per playable faction) at the periphery, a contested
  **mid-band**, and a **deep core** that is high-value, unowned, and Bloom-infested.

```
        [Kthaari core]         [Terran core]
              \                    /
               \   contested      /
                \    mid-band    /
   [Vaelith core] ── DEEP CORE ── [Sarn core]
                /   (Bloom)      \
               /                  \
      [Helion core]         [neutral rim]
```

Geography is not symmetric-fair; it's *interesting*. Chokepoints, dead-end pockets, nebula
walls, and one long corridor across the map that every faction wants and nobody can hold.

---

## 2. Hex Anatomy

Every hex has:

| Field | Notes |
|---|---|
| **Terrain** | Deep space / nebula / asteroid field / ion storm / gravity well / wreck field. Determines battle-scenario terrain (see [01](01-tactical-combat.md) §2) |
| **Owner** | Faction, or unowned |
| **Control pressure** | Per-faction accumulated value; drives ownership flips (§4) |
| **Strategic value** | 1-5. Drives income, and how hard it is to hold |
| **Bodies** | 0-4 planets/moons/belts, each with resource profiles and colonizability |
| **Installations** | Player/faction stations, outposts, defense platforms, minefields |
| **Anomalies** | Exploration content; hidden until surveyed |
| **Supply state** | Supplied / degraded / cut off (§5) |
| **Jump links** | Adjacency isn't always 6: some hexes have long-range jump lanes, some edges are impassable |

**Jump lanes are the map's most important design lever.** They create real chokepoints,
make certain hexes strategically enormous, and let designers shape fronts without invisible
walls.

---

## 3. Movement & Contact

- Squadrons move hex-to-hex in **real time**: ~2-8 minutes per hex depending on jump drive
  tier, hull mass, terrain, and supply state. Friendly supplied hexes are fastest.
- Movement continues while you're doing other things (fitting ships, managing trade).
  You can queue multi-hex routes.
- **Visibility:** you see your own hexes, hexes adjacent to your installations, and hexes
  within your squadrons' sensor range. Everything else is stale intelligence with a
  timestamp. Scouting is a real job.
- **Contact** occurs when a squadron enters a hex containing hostiles. The defender gets a
  short window to accept, reinforce (pull in adjacent friendly squadrons), or withdraw.
- **Contact → battle instance.** Everything relevant about the hex (terrain, installations,
  defense platforms, present squadrons) is serialized into the tactical scenario.

### Reinforcement window
A short (60-90s) window in which squadrons in *adjacent* hexes can join the battle before it
starts. This is what makes fleet positioning on the strategic map matter, and it's the
mechanism by which a small raid can suddenly become a major engagement. Both sides get it.

---

## 4. Control & Pressure

Ownership does **not** flip on a single battle. Each hex tracks per-faction **pressure**.

**Pressure accrues from:**
- Winning battles in the hex (scaled by tonnage engaged and by tonnage *disadvantage*)
- Holding installations in the hex
- Having supplied friendly squadrons present, over time
- Successful trade route throughput through the hex
- Completed sector objectives

**Pressure decays** toward zero when unreinforced, so held ground requires ongoing presence.

**Flip:** when a faction's pressure exceeds the current owner's by a threshold *and* the
owner has no functional installation in the hex, ownership changes. Installations must be
reduced first (§6), which means real territory change requires a **siege**, not a drive-by.

This design deliberately makes territory change **slow, visible, and coordinated**: you
can see a front building for hours, which gives defenders time to organize and turns the
map into a communication tool for the faction.

---

## 5. Supply

Supply is the strategic layer's central constraint and the reason logistics players exist.

- Supply **propagates from stations** with a supply module, spreading N hexes along
  owned/friendly hexes, attenuating with distance.
- Each hex is **Supplied**, **Degraded**, or **Cut Off**.

| State | Effect on squadrons in hex |
|---|---|
| Supplied | Full repair rate, ammo/marine resupply, fast movement, field refit possible |
| Degraded | Half repair, no resupply, slower movement |
| Cut Off | No repair, no resupply, **attrition** (slow hull damage, morale loss, fatigue) |

**Consequences that make this good:**
- Offensives must build forward stations or bring **tenders**: logistics ships become a
  genuinely wanted squadron slot.
- Overextension is self-punishing without any artificial mechanic: push too far, your supply
  line is long, thin, and full of trade lanes that raiders love.
- Cutting an enemy's supply is often better than fighting their fleet. **Raiders have a
  strategic purpose**, not just a PvP hobby.

---

## 6. Installations & Sieges

Installations are covered mechanically in [05](05-economy-and-expansion.md); their
*strategic* role:

- An installation **anchors** a hex: pressure can't flip it while a functional installation
  stands.
- Installations have their own **shield facings, mounts, and internals**: they are
  fitted, like ships, by whoever built them. A well-fitted station is a serious battle.
- **Sieges** are multi-stage and take real time:
  1. **Blockade**: cut the hex's supply; the station's regeneration and garrison
     reinforcement stop.
  2. **Reduction**: repeated Station Assault scenarios reduce the station's facings and
     internals. Damage persists between assaults while blockaded.
  3. **Capture or destruction**: a reduced station can be **boarded and captured**
     (marines again, since the capture pillar applies to stations too) or destroyed.
- **Defense window:** the owner gets a guaranteed notification and a minimum time-to-loss,
  so offline players are never deleted in their sleep (GDD §11.3). Stations degrade and can
  be captured, but the timeline is long enough to rally.

---

## 7. Fronts, Objectives, Seasons

### Faction objectives
Each faction's leadership (top-prestige players, or an elected council, see §9) sets
**sector objectives**: take this hex, hold this lane, break this siege. Completing them
awards prestige to participants and unlocks **faction doctrine techs** (faction-wide
component or hull line access). This is how individual play aggregates into faction progress.

### The Bloom
A hostile NPC faction that expands from the deep core on its own schedule, taking hexes
from *everyone*. It exists to:
- give PvE-focused players a permanent career with real strategic relevance,
- apply pressure that can force rival factions into informal truces,
- prevent the map from settling into a stable, boring stalemate.

The Bloom does not negotiate, does not hold trade routes, and drops no usable technology,
only rare materials and prestige.

### Seasons
The galaxy runs in **seasons (≈3 months)**. A season ends with a scored state and a
narrative beat; the next season **soft-resets territory** (borders relax toward faction
cores) but **never resets player assets**: ships, blueprints, officers, designs, rank, and
credits all persist. Stations in lost territory are converted to mothballed assets that can
be redeployed rather than confiscated.

This is the mechanism that keeps a dominant faction from making the game unplayable
permanently, without punishing the players who won.

---

## 8. Safety Gradient

Not everywhere is equally dangerous. This is deliberate and load-bearing for retention.

| Zone | Rule |
|---|---|
| **Faction core** | No hostile players. Yards, academies, markets. Fully safe. |
| **Faction territory** | Hostile incursion possible but rare and heavily opposed by defenses |
| **Border/contested** | Open war. Where most of the game happens |
| **Deep core / rim** | No safety, no supply, best resources, Bloom presence |

A player who never wants to PvP can run trade routes and colonies in faction space and
fight the Bloom forever, with real economic relevance to their faction's war effort. A
player who only wants to fight lives on the border. **Both are first-class careers.**

---

## 9. Faction Leadership *(open)*

How sector objectives get set is unresolved. Options:

1. **Prestige oligarchy**: top-N prestige players set objectives. Simple; risks a clique.
2. **Elected council**: periodic in-game elections. Great drama; vulnerable to apathy and
   brigading.
3. **NPC high command + player influence**: NPC-generated objectives weighted by player
   activity. Robust, always functions, less player agency.

*Leaning: (3) as the baseline with (1) layered on top*. NPC command always produces
objectives so the system never stalls on a quiet server, and high-prestige players can
*promote* specific objectives to focus their faction's attention. Ship it as (3), add (1)
once population supports it.
