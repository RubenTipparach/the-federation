# The Federation

A persistent-galaxy space MMO in the tradition of **Starfleet Command** (1999) and
**Starfleet Command II: Empires at War** (2001): tactical, energy-managed capital ship
combat layered on top of a living strategic map that thousands of players fight over
simultaneously.

**Ship construction and customization is the game's centerpiece.** Every hull the player
flies is assembled by them, hardpoint by hardpoint, officer by officer, power relay by
power relay. Everything else in the game exists to give that shipyard meaning: territory
to fight over, trade routes to fund the yard, colonies to feed it rare alloys, and enemy
hulls to board, capture, and refit into your own.

- **Client:** Godot 4
- **Backend:** Fly.io (Fly Machines + Fly Postgres)
- **Strategic layer:** a galaxy of ~3,000 hexagons
- **Tactical layer:** instanced battles, up to 6 capital ships per squadron

## Documents

| Doc | Contents |
|---|---|
| [docs/GDD.md](docs/GDD.md) | **Master design document**: vision, pillars, player fantasy, loops, factions |
| [docs/01-tactical-combat.md](docs/01-tactical-combat.md) | Battle scenarios, energy allocation, shield arcs, damage, boarding & capture |
| [docs/02-ship-construction.md](docs/02-ship-construction.md) | Hulls, budgets, hardpoints, subsystems, refit economy, blueprints |
| [docs/03-officers-and-crew.md](docs/03-officers-and-crew.md) | Bridge officers, crew quality, marines, promotion, permadeath rules |
| [docs/04-galaxy-and-territory.md](docs/04-galaxy-and-territory.md) | Hex galaxy, supply, fleet movement, contested space, sieges |
| [docs/05-economy-and-expansion.md](docs/05-economy-and-expansion.md) | Trade routes, stations, colonization, exploration, resources |
| [docs/06-technical-architecture.md](docs/06-technical-architecture.md) | Godot + Fly.io topology, netcode, persistence, scaling, cost model |
| [docs/07-roadmap.md](docs/07-roadmap.md) | Vertical slice → alpha → beta, scope cuts, risk register |

## Status

Pre-production. This repository currently contains design documentation only. Nothing
here is implemented yet. See [docs/07-roadmap.md](docs/07-roadmap.md) for the intended
build order and the first milestone's exit criteria.

## A note on IP

Starfleet Command is the design *reference*, not the setting. Its combat model descends
from *Star Fleet Battles* (Amarillo Design Bureau) under Star Trek license, and both the
Star Trek setting and SFB's specific rules text are owned property. The game systems
described here are original reinterpretations, and the factions, ships, and setting in
these documents are original IP. Keep it that way: no Star Trek names, no ship classes,
no reproduced SFB tables or terminology.
