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
| [docs/02-ship-construction.md](docs/02-ship-construction.md) | Hulls, budgets, mounts and arcs, subsystems, refit economy, blueprints |
| [docs/03-officers-and-crew.md](docs/03-officers-and-crew.md) | Bridge officers, crew quality, marines, promotion, permadeath rules |
| [docs/04-galaxy-and-territory.md](docs/04-galaxy-and-territory.md) | Hex galaxy, supply, fleet movement, contested space, sieges |
| [docs/05-economy-and-expansion.md](docs/05-economy-and-expansion.md) | Trade routes, stations, colonization, exploration, resources |
| [docs/06-technical-architecture.md](docs/06-technical-architecture.md) | Godot + Fly.io topology, netcode, persistence, scaling, cost model |
| [docs/07-roadmap.md](docs/07-roadmap.md) | Vertical slice → alpha → beta, scope cuts, risk register |
| [docs/08-build-and-deploy.md](docs/08-build-and-deploy.md) | itch.io deploy pipeline, secrets, targets, what is verified |
| [docs/09-reference-federation-commander.md](docs/09-reference-federation-commander.md) | What the Federation Commander starter rules say, what we take, where we differ |
| [docs/10-shipyard.md](docs/10-shipyard.md) | Buying hulls, fitting them out, the credit economy |
| [docs/11-battle-logs-and-replay.md](docs/11-battle-logs-and-replay.md) | The deterministic log, replay reproduction, the replay bar |
| [docs/12-ship-design-language.md](docs/12-ship-design-language.md) | How the ships of this era are built, and what our hulls take from that |
| [docs/13-terrain-and-tractors.md](docs/13-terrain-and-tractors.md) | Nebulae, asteroids, gravity wells, and the tractor beam auction |
| [docs/14-reference-planet-shader.md](docs/14-reference-planet-shader.md) | The vendored planet shader, why the game is GPL-3.0, and what it replaced |
| [docs/15-worlds.md](docs/15-worlds.md) | Concept for the seven worlds an arena can hold, with plates drawn from the game |
| [docs/16-multiplayer.md](docs/16-multiplayer.md) | Making the tactical layer multiplayer: what already exists, what is in the way, and the build order |
| [docs/17-starship-design-bible.md](docs/17-starship-design-bible.md) | The starship tradition from the studio floor: parts, light, liveries, kitbashing, dialects, and what our pixel art hulls take from it |
| [docs/18-the-fleet.md](docs/18-the-fleet.md) | How the sixty hulls are generated, painted and checked, and what each stage decides |

Project rules live in [CLAUDE.md](CLAUDE.md) and are binding.

## Status

Pre-production, first playable prototype. What is in the repository:

- The design documents above.
- A **deploy pipeline** for itch.io, triggered on merge to `main`. See
  [docs/08-build-and-deploy.md](docs/08-build-and-deploy.md), including a plain
  account of which parts are verified and which are not.
- A **playable prototype** (Godot 4.7.1, GDScript, web first): ship fitting with the
  four budgets and a live SSD dry dock demo, the 12 sector arc wheel, skirmish setup,
  and 1v1 3D tactical combat against an AI opponent. The simulation is a shared library
  under `src/sim/` with a 541 check headless test suite (`./scripts/run-tests.sh`).

Fly.io deployment is deliberately deferred until the prototype mechanics are
understood. See [docs/08-build-and-deploy.md](docs/08-build-and-deploy.md) section 8.

See [docs/07-roadmap.md](docs/07-roadmap.md) for the intended build order and the
first milestone's exit criteria.

## Quick start

```sh
./scripts/install-godot.sh      # pinned Godot, from build.config
./scripts/install-butler.sh     # itch.io upload tool
./scripts/build.sh              # export ENABLED_TARGETS
DRY_RUN=1 ./scripts/deploy-itch.sh
```

CI runs these same scripts. `build.config` is the single source of truth for
versions, targets, and itch.io coordinates.

## Licence

**GPL-3.0.** The full text is in [LICENSE](LICENSE). The game is under the GPL
because the planet shader it vendors is: see
[docs/14-reference-planet-shader.md](docs/14-reference-planet-shader.md) section
1 for what that means in practice and what the alternative would be. Anything
vendored from here on has to be GPL compatible.

## A note on IP

Starfleet Command is the design *reference*, not the setting. Its combat model descends
from *Star Fleet Battles* (Amarillo Design Bureau) under Star Trek license, and both the
Star Trek setting and SFB's specific rules text are owned property. The game systems
described here are original reinterpretations, and the factions, ships, and setting in
these documents are original IP. Keep it that way: no Star Trek names, no ship classes,
no reproduced SFB tables or terminology.
