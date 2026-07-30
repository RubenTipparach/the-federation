# 07. Roadmap

The organizing principle: **prove the fun before building the MMO.** Everything in this
design is expensive, and almost all of it is worthless if a two-ship fight isn't gripping.
So the build order is deliberately backwards from the feature list: tactical layer first,
persistence last.

---

## M1. Tactical Prototype *(no networking, no MMO)*

**Goal:** answer the only question that matters: is the combat fun?

**Scope:**
- One scene: two ships, deep space, no terrain.
- Movement (momentum, turn rate, throttle) that *feels* like tonnage.
- **Energy allocation panel**, fully working, with reallocation ramp.
- Six shield facings with regen, bias, and battery reinforcement.
- Three weapons only: a beam battery, a disruptor bank (with overload), a plasma torpedo.
- Hull, armor, and the internal damage table with real consequences.
- One hardcoded enemy AI that manages its own power and shield rotation competently.
- Tactical pause.
- Runs locally in the Godot editor. **No server, no accounts, no database, no art.**

**Exit criteria, hard gates:**
- A fight between two evenly matched ships lasts 6-12 minutes and is *tense throughout*.
- Five external playtesters, given no tutorial, discover shield rotation on their own.
- Those testers ask to play again unprompted.
- Every tester can articulate *why* they lost, in mechanical terms.

**If M1 fails these gates, stop and iterate on M1.** Do not proceed. There is no amount of
strategic layer that rescues boring combat, and every milestone after this one is built on
the assumption that M1 succeeded.

---

## M2. The Shipyard

**Goal:** prove that building ships is a game in itself.

- Hull definitions (4 hulls: frigate, destroyer, light cruiser, heavy cruiser).
- The **four budgets** (space / power / mass / crew) with live validation.
- Hardpoints with sizes and arcs; the **arc rose** overlay.
- ~30 components across the categories in [02](02-ship-construction.md) §5, at 2 tiers.
- Derived stats panel, compare mode, named designs with revisions.
- **Dry-dock simulation**: test a design against M1's AI immediately.
- Shared `TheFederation.Sim` C# library used by both the fitting screen and the battle sim.

**Process note:** this milestone is almost entirely UI, so `CLAUDE.md` §6 applies heavily.
Each screen needs a mockup approved before implementation, per screen rather than one
blanket approval for the whole shipyard.

**Exit criteria:**
- Testers voluntarily iterate a design 5+ times in one session.
- No single fit wins against all others in a round-robin of tester-made designs.
- Two testers independently produce *different* designs they can each justify.
- A new tester can produce a functional ship in under 5 minutes using a faction preset.

---

## M3. Squadron & Scenarios

**Goal:** scale combat from a duel to a battle.

- 6-ship squadrons with **command tonnage** budget.
- Consort standing orders; officer-rating-driven consort AI.
- Hot-swap control (with transfer lag), resolving GDD §11.1 by testing it.
- Officers and crew: 6 posts, ratings, traits, crew quality, marines.
- **Boarding and capture**, end to end, including prize retention at scenario end.
- Terrain types and their combat effects.
- 4 scenario types: Fleet Action, Convoy Raid, Station Assault, Bloom Incursion.

**Exit criteria:**
- A 6v6 battle is comprehensible and completes in under 25 minutes.
- Consorts are useful without being micromanaged.
- Boarding is a viable win route that a tester chooses *on purpose*, not by accident.
- A marine-heavy specialist design is competitive with a gun-heavy one.

---

## M4. Netcode & Battle Instances

**Goal:** the tactical layer, multiplayer, on Fly.io.

- Godot dedicated-server export of the combat sim.
- WebSocket transport, 15 Hz authoritative tick, client interpolation, intent-only inputs.
- **Server-side interest management / fog of war** (a security requirement, not an optimization).
- `tf-world` creates battle Machines via the Fly Machines API; warm pool; TTLs.
- Signed join tokens; signed, idempotent result write-back.
- Accounts and auth; minimal persistence for ships and designs.

**Exit criteria:**
- 8 real players in one battle, cross-continent, with acceptable feel at 150-250ms.
- Battle Machine boot p95 under 10 seconds.
- Zero authoritative-state divergence in a 50-battle soak test.
- A killed or hung Machine never corrupts a result or double-awards salvage.

---

## M5. The Galaxy

**Goal:** a persistent map worth fighting over.

- 300-hex map (**not** 3,000; validate the systems at small scale first).
- Hex ownership, control pressure, supply propagation.
- Squadron movement, real-time, with the reinforcement window.
- Fog of war / stale intelligence on the strategic map.
- Battle results writing back to hex pressure.
- The tick service, with idempotency and resumability from day one.
- 2 factions only (Terran, Kthaari), enough to have a war.

**Exit criteria:**
- A front visibly forms, moves, and stabilizes over a week of tester play without
  designer intervention.
- Supply pressure demonstrably changes where testers choose to fight.
- No resource duplication across 500+ ticks including forced restarts mid-tick.

---

## M6. Economy & Expansion

**Goal:** the builder career, and the reason to fight over specific hexes.

- Resources, location-scoped stores, refining.
- Stations: outposts and stations, modules, station fitting and defense.
- **Trade routes**, convoys, interception, Convoy Raid scenarios wired to the map.
- Colonization: survey, found, develop, planetary assault.
- Regional markets, contracts, bounties.
- Credits/prestige split; rank; blueprint acquisition including capture-to-blueprint.
- Repair, refit, and field refit.

**Exit criteria:**
- A tester who never initiates PvP can sustain a meaningful economic career and is
  *visibly relevant* to their faction's war effort.
- Raiding a trade route is more profitable than farming NPCs, and starving an enemy yard
  demonstrably slows their construction.
- The economic sinks in [05](05-economy-and-expansion.md) §7 hold a stable currency supply
  across a 4-week closed test.

---

## M7. Closed Alpha

- All 6 factions; full 3,000-hex map.
- Bloom as an active NPC faction with autonomous expansion.
- Exploration: surveys, anomalies, derelicts, deep space, unique components.
- Corporations (guilds) with permission roles and shared stations.
- Sieges, defense windows, offline-protection rules.
- Faction objectives and doctrine techs.
- Onboarding and tutorial; faction preset designs at every tier.
- Telemetry on everything: build diversity, win rates by fit, time-to-first-battle, churn points.

---

## M8. Beta → Season 1

- Balance passes driven by telemetry, especially build diversity (the health metric that
  matters most. If the top 5 fits are 60%+ of ships, [02](02-ship-construction.md) §10 has
  failed and needs work).
- Season structure, scoring, and the soft territory reset.
- Load testing to the §7 targets in [06](06-technical-architecture.md).
- Region sharding decision (GDD §11.6) made with real concurrency data.
- Monetization implementation per GDD §8.
- Anti-grief, reporting, and moderation tooling. **Do not leave this to launch week.**

---

## Deliberate Scope Cuts

Named explicitly so they don't creep back in:

| Cut | Why |
|---|---|
| 3D combat | Breaks arc/facing legibility (see [01](01-tactical-combat.md) §1). Non-negotiable. |
| Avatar/walking-around gameplay | Enormous cost, orthogonal to every pillar. |
| Seamless single-shard galaxy | Instancing is what makes the tactical depth affordable. |
| Player-designed hulls (custom geometry) | Hardpoints and arcs must be hand-authored to stay balanced. Fit, don't sculpt. |
| Ground combat as a playable layer | Planetary assault resolves in orbit + a marine check. |
| Fighter/small-craft direct piloting | Hangars are a subsystem, not a second game. |
| Voice/social platform features | Players already have Discord. |
| Mobile client | Possibly a companion app for yard/market later. Never the battle layer. |

---

## Risk Register (design)

Technical risks are in [06](06-technical-architecture.md) §11. Design risks:

| Risk | Severity | Mitigation |
|---|---|---|
| Combat isn't fun | **Critical** | M1 gates. Stop-the-line authority if it fails. |
| Fitting complexity repels new players | High | Presets, dry-dock, progressive disclosure; tested from M2 |
| One dominant fit emerges | High | Four budgets, component families, scenario variety, telemetry on build diversity |
| Trade/colony career is boring busywork | Medium | It must be *strategically relevant*, not just income; M6 exit criteria enforce this |
| Offline losses drive players off | High | Defense windows, degrade-never-delete, guaranteed notification |
| Faction population imbalance | Medium | Underdog prestige bonuses, cooldowned defection, seasonal soft reset |
| Capture is a novelty nobody uses | Medium | M3 exit criteria require a competitive boarding specialist |
| Territory stagnates into a boring stalemate | Medium | The Bloom, seasons, pressure decay |
| Veterans crush new players permanently | High | No power inflation (P1); safety gradient; public design sharing flattens knowledge asymmetry |

---

## Team Shape (rough)

For M1-M3, a very small team is correct and sufficient:

- 1 gameplay programmer (C#, the sim)
- 1 UI/UX programmer (the shipyard is a UI-heavy product in its own right)
- 1 designer (systems + balance + scenario authoring)
- Placeholder art throughout M1-M3

Backend, art, and ops staffing begins at M4, not before. Hiring infrastructure engineers to
support combat that hasn't been proven fun yet is the most common way projects like this die.
