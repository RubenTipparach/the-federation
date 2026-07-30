# 05 — Economy, Trade, Stations, Colonization & Exploration

The systems that fund the shipyard and give the map a reason to exist beyond kill counts.
This is the "builder career" — fully viable as a primary way to play.

---

## 1. Resources

Deliberately short list. Deep economies fail from too many nouns, not too few.

| Resource | Source | Consumed by |
|---|---|---|
| **Credits** | Trade, contracts, salvage, colony tax | Everything |
| **Alloys** | Asteroid belts, planetary mining | Hulls, armor, station structure |
| **Volatiles** | Gas giants, nebula harvesting | Reactors, engines, ammunition |
| **Crystalline** | Rare planetary deposits, deep-core hexes | Shields, computers, sensors, cloaks |
| **Organics** | Habitable colonies | Crew, marines, colony growth, morale supply |
| **Exotics** | Anomalies, Bloom kills, deep-core only | Tier 4–5 components, doctrine techs |

**Exotics are the top of the economy and only exist in dangerous places.** That single fact
connects the peaceful builder career to the war: the best components require materials that
come from contested space, so industrialists need the military and vice versa.

### Materials are physical
Resources exist **at a location** and must be **moved**. There is no global bank. Building a
dreadnought means getting alloys to that specific yard, which means a trade route, which
means something raidable. This is the design's central economic decision and everything
interesting downstream depends on it.

---

## 2. Trade Routes

A **trade route** is a persistent, player-established, semi-automated convoy lane.

### Establishing one
1. Own or have docking rights at two endpoints (stations/colonies).
2. Pay setup cost and assign **freighter hulls** (player-built, from the same shipyard system
   — freighters are real designs with real fittings, not abstract tokens).
3. Optionally assign **escorts** (your ships, or contracted from other players).
4. Set the cargo manifest and the route's hex path.

### Running
- Convoys traverse the hex path in real time, hauling resources and generating credits based
  on distance, cargo value, endpoint demand, and risk.
- Routes through **hostile or contested hexes** pay substantially more. Risk *is* the yield
  curve — the safe route is the poor route.
- Routes are **visible** to players with intelligence on those hexes. You cannot run a
  fat secret convoy through a war zone forever.

### Raiding
- A hostile squadron intercepting a convoy triggers a **Convoy Raid** scenario
  ([01](01-tactical-combat.md) §10): attacker wants freighters dead or captured, defender
  wants them off the far map edge.
- Captured freighters and cargo go to the raider. Destroyed ones are a pure loss to the owner.
- Repeated raids **degrade the route's reputation**, reducing throughput until re-secured.

**This is the game's primary PvP driver, and it's economic rather than arbitrary.** Raiders
raid because it pays and because it starves an enemy shipyard. Defenders defend because the
alternative is not being able to build their dreadnought. Nobody needs a contrived reason to
fight.

### Contracts
Players post **escort contracts**, **hauling contracts**, and **bounties** on an in-game
market. This gives combat players income without trade infrastructure and gives trade players
protection without a combat fleet. It's the connective tissue between the two careers.

---

## 3. Stations

Stations are the player's permanent footprint on the galaxy. **They are built with the same
system as ships** — modular, fitted, upgradeable, and defensible — which means the
shipbuilding pillar covers stations too, at very little extra design cost.

### Construction
1. Bring a squadron with a **construction module** to a legal hex (unowned or friendly;
   permit required, gated by rank/prestige).
2. Deliver alloys and volatiles to the site — a real logistics operation.
3. Build in real time. An **Outpost** is hours; a **Starbase** is days.

### Tiers
| Tier | Role |
|---|---|
| **Outpost** | Minimal: supply projection, small dock, 1–2 modules |
| **Station** | Real base: several modules, meaningful defenses, garrison |
| **Starbase** | Regional anchor: full yard, many modules, serious defenses |
| **Fortress** | Chokepoint fortification: defense-heavy, minimal industry |

### Modules
Chosen against a station's own space/power budget — the same trade-off system as ships.

- **Shipyard** (build ships; tier + slip count determines what and how fast)
- **Repair dock** (repair, refit)
- **Supply depot** (projects supply into surrounding hexes — see [04](04-galaxy-and-territory.md) §5)
- **Refinery** (raw → refined materials)
- **Market** (player trading hub; generates transaction income)
- **Academy** (recruit/train officers, train crew)
- **Barracks** (marines)
- **Research lab** (blueprints, doctrine tech contribution)
- **Sensor array** (extends map visibility)
- **Defense batteries / shield generators / hangar** (station combat fitting)
- **Warehouse** (resource storage — capacity limits are what force trade routes)

### Ownership
- **Personal** — one player. Cheap, small, vulnerable.
- **Corporation** (guild) — shared, with permission roles. The main path for real bases.
- **Faction** — NPC-owned core infrastructure, always safe, always available. Guarantees new
  players access to a yard and academy without needing a guild.

### Vulnerability
Stations are attackable but never instantly deleted (GDD §11.3, [04](04-galaxy-and-territory.md) §6):
guaranteed owner notification, a minimum time-to-loss measured in hours, damage that persists
under blockade, and capture-by-boarding as the primary loss condition. Losing a starbase
should be a story your guild tells for a year, not a thing that happens while you sleep.

---

## 4. Colonization

Colonies are the resource base and the long game.

### Founding
1. **Survey** the planet (Science officer + sensors; quality of survey affects revealed data).
2. Bring a **colony module** and Organics.
3. Claim requires the hex to be owned or unowned — never inside hostile territory.
4. Colony starts at population 1 and grows on real-time ticks.

### Planet profile
- **Habitability** — growth rate ceiling and Organics yield
- **Resource deposits** — which materials, at what richness
- **Hazards** — radiation, tectonics, atmosphere; require investment to offset
- **Orbital slots** — how many orbital installations the planet supports

### Development
Colonies have their own build queue, spending credits and materials on:
- **Extraction** (mines, harvesters, refineries — resource output)
- **Habitation** (population growth ceiling, Organics, crew recruitment pool)
- **Infrastructure** (build speed, storage, route capacity)
- **Defense** (ground batteries, orbital platforms, planetary shield, garrison)

### Colonies feed the shipyard, directly
A developed colony produces the alloys and crystalline your yard needs and the population
your crews are drawn from. **A player with good colonies can build ships nobody else can
afford.** That's the payoff for the builder career, and it's why colonies are worth attacking.

### Planetary assault
Taking a colony:
1. Win orbital superiority (Station Assault / Planetary Strike scenarios).
2. Reduce orbital and ground defenses.
3. Land **marines** and hold — the capture pillar again, at the largest scale.
4. Captured colonies suffer heavy unrest and reduced output for a long recovery period, so
   conquest is worse than growing your own — but it *denies* the enemy, which is often the
   point.

---

## 5. Exploration

Exploration is the third career and the game's source of novelty.

### Survey
- Hexes have a **survey state**: unsurveyed → scanned → fully surveyed.
- Surveying reveals terrain detail, planetary data, anomalies, hidden jump lanes, and
  derelicts.
- **First survey** of a hex awards prestige and credits to the player, permanently credited
  in the hex's record. Names go on the map. This is a cheap, powerful retention hook —
  players will chase it hard.

### Anomalies
Discrete, hand-authored-and-procedurally-varied content in surveyed hexes:

| Type | Content |
|---|---|
| **Derelict** | An intact hull to recover. Best non-combat source of foreign blueprints. |
| **Ancient cache** | Exotics, Tier-5 blueprint fragments, unique components |
| **Spatial phenomenon** | Persistent hex-wide effect; can be studied or weaponized |
| **Distress signal** | Branching PvE encounter; sometimes a trap |
| **Bloom nest** | Must be cleared or it spreads to adjacent hexes |
| **Precursor site** | Multi-stage guild-scale content; unlocks doctrine techs |

### Deep space
Beyond the rim: unowned, unsupplied, no reinforcement, best Exotics. Long-range expeditions
need tenders, cargo, and jump-drive investment — a completely different fitting problem from
combat, which gives the shipyard yet another axis to be interesting on.

**Unique components** from anomalies are the one place where non-tiered, weird gear lives:
a one-of-a-kind cloak that works while firing but cooks your reactor. These are prestige
items, deliberately rare, and never strictly better than tiered gear — just strange.

---

## 6. Markets & Player Trade

- **Regional markets** at station Market modules, with **location-specific prices** driven
  by local supply and demand. No global auction house — because a unified market would
  destroy the entire trade-route pillar overnight.
- Players list components, hulls, materials, blueprints, and prizes.
- Contracts for escort, hauling, construction, and bounties (§2).
- **Credits are tradeable; prestige and rank are not.** Nobody buys their way to command.

Price differentials between regions *are* the trade game. The reason to haul crystalline
from the rim to a core yard is that it's worth four times as much there, and the reason
that's not free money is the six contested hexes in between.

---

## 7. Economic Sinks

An MMO economy dies of inflation. Deliberate, permanent sinks:

- **Ship losses** — the primary sink, and the reason combat must stay lethal
- **Repairs** — continuous, scaled to damage
- **Refits** — the single largest recurring voluntary spend
- **Crew and marine replacement** — recurring, unavoidable
- **Ammunition and consumables** — per-battle
- **Station and colony upkeep** — recurring; a station you can't afford mothballs itself
- **Construction and market fees** — transaction friction
- **Officer salaries** — scaled to rating, which caps god-crew hoarding

Target: a mature player's *recurring* costs consume most of a normal week's income, so that
growth requires either expansion or better play — never idling.
