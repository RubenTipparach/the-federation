# 16. Multiplayer

How the tactical layer becomes a game two people can play against each other, and in what
order to build it. This is the plan for M4 in [07](07-roadmap.md). It refines
[06](06-technical-architecture.md) section 4 rather than replacing it, and section 8 below
says exactly where the two differ.

Scope: **one battle, several human captains, on a server.** Accounts, matchmaking,
Postgres, the Fly Machines API and the galaxy layer are outside it. They are
[06](06-technical-architecture.md) sections 3, 5, 6 and 10, and none of them can be
sensibly specified before a battle has been fought over a socket once.

---

## 1. What already exists, and what it is worth

The prototype was built single player, but four of its decisions turn out to be the
expensive parts of multiplayer, already paid for:

| What exists | What it is, for multiplayer |
|---|---|
| `Battle.apply_command(actor, kind, args)` (`src/sim/battle.gd:614`) | The command validator and the single entry point for human orders. |
| `BattleLog` records `[tick, actor, kind, args]` (`src/sim/battle_log.gd:56`) | The wire format, already committed. A recorded battle and a networked battle are the same byte stream, one written to a file and one to a socket. |
| `BattleLog.fingerprint(battle)` (`src/sim/battle_log.gd:163`) | The divergence detector. |
| `CombatScreen._step_replay` (`src/ui/combat_screen.gd:400`) | A tactical view driving a `Battle` from a command stream that did not come from this machine, with seek, pause and speed. That is a network client with a file where the socket goes. |

Two more properties bought for other reasons that pay out here:

- **The sim has no nodes.** `src/sim/` runs and is tested headless, so a dedicated server
  export runs the identical files the client runs. This is what
  [06](06-technical-architecture.md) section 2 promised, and it is real: there is not even
  a build boundary to drift across, which is a stronger guarantee than a shared library
  (CLAUDE.md 4.1).
- **Nothing in the sim is secret yet.** The only limit on what a captain can know is
  `Terrain.lock_broken(a, b)` (`src/sim/terrain.gd:210`), a nebula between two hulls,
  which is symmetric and derivable from positions both sides already have.

**One correction, because the comments overstate it.** `src/sim/battle.gd:608-610` says
every order "from a button, a stick, the AI, or a replay" arrives at `apply_command`. The
AI does not. `CombatAi.act` calls `me.set_order` (`src/sim/ai.gd:65`), `me.set_alloc_units`
(`src/sim/ai.gd:132`) and `battle.try_fire` (`src/sim/ai.gd:70`) directly, so the
door is a door for human input only, and no log contains a single AI order. Replay still
reproduces because `BattleLog.replay` calls `battle.step`, which re-runs the deterministic
AI. That works on one machine and it is a load bearing assumption to be careful with here.

---

## 2. The recommendation

**The server owns the one `Battle`. Commands go up, commands come down, and state travels
as a snapshot: on join, on reconnect, on repair, and as periodic keyframes inside the
battle log. Clients do not run their own copy of the battle in M4.**

That last clause is the decision, and it is worth being clear about why, because the
tempting design is the opposite one. Every client could step the same `Battle` from the
same relayed commands: the code already exists, the wire is already written, the client is
already the replay loop, and it would be beautiful. It was seriously considered here and it
was rejected for one reason, and the reason is not determinism.

**M4 already owes fog of war.** [07](07-roadmap.md) M4 lists "Server-side interest
management / fog of war (a security requirement, not an optimization)" as a deliverable of
this very milestone. It is not future work: cloaking is the Vaelith Ascendancy centrepiece
([01](01-tactical-combat.md) section on doctrine), nebulae halve sensor range
([01](01-tactical-combat.md) terrain table), and stale intelligence is a strategic pillar
([04](04-galaxy-and-territory.md)). A client that steps its own `Battle` holds every hull,
every shield value and every marine count by construction. It is a wallhack whatever the
interface draws, and the only escapes are to switch the replica off, which lands on the
design below anyway, or to run a filtered `Battle` per client, which is a second simulation
whose entire purpose is to differ from the first (CLAUDE.md 4.1 forbids exactly this).

So the replica is not a hedge with an escape hatch. **Its escape hatch is the
destination.** Build the destination.

The determinism question, which is what usually decides this, turns out not to be the
deciding factor either way. Section 3.3 has it, and section 7 records the dissent, because
there is a real condition under which the replica becomes correct later and it should not
be forgotten.

---

## 3. The three things in the way

None of them is network code. All three are worth doing regardless.

### 3.1 The fixed step is not fixed, and recorded battles do not replay

This is a live bug.

- A live battle is stepped from `CombatScreen._physics_process(delta)`
  (`src/ui/combat_screen.gd:337`), so it advances at Godot's physics rate. The project sets
  no override, so that is **60 Hz, a step of 0.0167** (confirmed by probe:
  `Engine.physics_ticks_per_second` is 60).
- Every log is created with `dt` from `tuning combat.replay_step`
  (`src/ui/combat_screen.gd:230`), which is **0.0333, a step of 1/30**.
- `BattleLog.replay()` steps at the recorded `dt` (`src/sim/battle_log.gd:156`).

A replay of a real skirmish therefore runs each recorded tick over twice the simulated time
the live battle gave it. The test suite passes because its scripted battle steps at
`1.0 / 30.0` explicitly (`tests/run_tests.gd:497`), which is the rate the log claims. The
property [11](11-battle-logs-and-replay.md) describes is true of battles driven at the
logged rate, which today is the test suite and nothing else.

**Fix it by adopting 60, not by picking a new number.** The step becomes one value in
`data/tuning.json` read by both the loop and the log, `replay_step` stops being a second
number that can disagree with the first (CLAUDE.md 4.1 applied to a constant), and the
combat screen accumulates wall time and runs a whole number of fixed steps per frame.

**Changing the rate is a rebalance, and that is a separate decision.** The sim is not step
invariant: it integrates explicitly (`src/sim/ship_state.gd:352`, `:371`), accumulates
shield credit and repair progress per step (`:460`, `:492`), and accrues tractor strain per
step (`src/sim/tractor.gd:201`). Every number in `data/tuning.json` was tuned against the
1/60 the game actually runs at. Moving to [06](06-technical-architecture.md)'s 15 Hz
changes turn ramps, shield regeneration and repair behaviour, and invalidates the balance
as well as the logs.

There is also a floor nobody has written down. Seeker impact is a post-step distance test
against `seeker_hit_radius` 5.0, and a drone flies at `seeker_speed` 25.6
(`data/weapons.json`, `src/sim/seeker.gd:50`). Closing head on with a ship doing 25 units
per second, the pair covers 50 units per second, so below roughly 5 to 6 Hz a drone steps
straight through its target without the test ever seeing it. 15 Hz clears that by about
two and a half times, which is margin rather than comfort, and it is one more reason the
tick is a measurement rather than a preference.

**The test that does not exist yet:** record a battle driven the way the game drives it,
through the screen's own loop at the screen's own rate, then replay it headlessly and
compare fingerprints. The current test records a battle driven by the test, which cannot
catch this class of bug because the test supplies the step.

### 3.2 A `Battle` is a duel, and it needs to be a battle

`Battle` hardcodes two ships, ship 0 human and ship 1 AI:

| Site | What it assumes |
|---|---|
| `battle.gd:94`, `:98` | `player()` is `ships[0]`, `enemy()` is `ships[1]`. Eight uses inside the sim, roughly twenty five in the front end |
| `battle.gd:150` | `CombatAi.act(enemy(), player(), self)` runs every step, unconditionally, for ship 1 |
| `battle.gd:181` | `winner = 1 - i`, and the battle ends the moment anyone dies |
| `battle.gd:124` | `target_for`'s fallback is `ships[1] if ship == ships[0] else ships[0]` |
| `battle.gd:498`, `:524`, `:560`, `:580` | Boarding reads `ships[1 - actor]`: marines can only go to the other one |
| `battle.gd:250`, `:279`, `:304`, `:318`, `:379`, `:597`, `:703` | Events carry `target_player` and `holder_player`, booleans meaning "relative to `ships[0]`" |
| `battle.gd:56`, `:64` | `start_positions()` returns exactly two, `create_duel` builds exactly two |

Most of the step loop is already general: contacts, debris, terrain, seekers, damage and
the command door all iterate `ships`. What is hardcoded is the identity layer on top, and
it rests on one thing that does not exist: **there is no team, side or allegiance anywhere
in `src/sim/`**, so `foes_of` currently means "everyone who is not me"
(`src/sim/battle.gd:108`). That one absence blocks the end condition, target selection,
friendly fire and contested boarding, and it is a design decision rather than an edit.

Two smaller gaps in the same area:

- **Nothing records who controls a ship.** `ShipState.create` takes `ai_ship`
  (`src/sim/ship_state.gd:133`), uses it once for the default power split, and throws it
  away. The smallest correct fix is to keep it as a field and replace `battle.gd:150` with
  a loop over the array `step()` already walks twice: `for s in ships: if s.ai:
  CombatAi.act(s, target_for(s), self)`. One step loop, one AI, no fork. Passing
  `target_for(s)` rather than `player()` is part of the minimal fix rather than scope
  creep, because the AI currently steers at `ships[0]` while firing at `target_for`, and
  those two disagree the moment a third ship exists.
- **A log records one fit and one enemy hull id** (`src/sim/battle_log.gd:24-28`), and
  rebuilds the opponent with `ShipFit.create_default` (`:143`). A second human's custom
  loadout is not recorded at all, so a two human battle would not replay even after the
  step is fixed.

**Multiplayer should not pay for this.** M3 in [07](07-roadmap.md) is six ship squadrons
with consorts, per ship AI and hot swap control, and it needs every one of these changes
for single player reasons. Do it there.

### 3.3 Determinism is same binary, not cross platform, and it amplifies

Replay works because it replays on the machine that recorded it. The harder question is
whether a WebAssembly client in a browser and a native Linux server compute the same
battle from the same commands.

The sim's hygiene is genuinely good where it is hardest: no wall clock read anywhere in
`src/sim/`, one seeded generator per battle with a fixed draw order, no order dependent
iteration, no threads, no signals, no nodes. What is not pinned is the arithmetic. The per
tick path calls `atan2` (`src/sim/sectors.gd:43`, reached from thirteen callers), `sin` and
`cos` (ship, seeker, tractor), `pow` (`src/sim/debris.gd:70`), and `sqrt` through
`Vector2.length`. IEEE 754 pins `+ - * /` and `sqrt` exactly. It does not pin the
transcendentals, and a browser and a server link different implementations of them.

**The amplification is the part that matters, and it is specific.** A bearing from `atan2`
is immediately truncated into one of twelve sectors (`src/sim/sectors.gd:23`), which picks
which shield eats a hit (`src/sim/ship_state.gd:672`), which changes how many draws
`apply_internal` takes from the generator (`:704`, `:722`). Both ships and the terrain
share one `RandomNumberGenerator` (`src/sim/battle.gd:67-88`), so a single extra or missing
draw re-keys every subsequent damage roll for **both** sides. A last bit difference in a
bearing is therefore not a last bit difference in the battle. It is a different battle from
that tick onward, and only if the difference happens to land on a sector boundary.

Two consequences:

1. **Do not build anything whose correctness depends on two builds agreeing bit for bit.**
   That is the recommendation in section 2, arrived at independently.
2. **Measure it anyway, cheaply, forever.** Same binary determinism still underwrites
   server side replay and the existing suite. Export the Linux build and the Web build,
   replay a committed corpus of logs through `BattleLog.replay` on each, and diff the
   fingerprints. It needs no socket and no server, it leaves a permanent CI canary, and it
   is the experiment that decides whether section 7's dissent ever becomes correct.

**There is a third option nobody usually takes, and it is worth naming.** Determinism here
is an implementation choice rather than a fact about the world: WebAssembly's float
semantics are fully specified, and the difference between targets is entirely *which libm
got linked*. Implementing `sin`, `cos`, `atan2` and `pow` inside `src/sim` as polynomial
evaluations over the operations IEEE 754 does pin would make the simulation bit identical
on every target, at an accuracy cost this game cannot perceive. It is on the order of a
hundred and fifty lines in one file, and `src/sim/sectors.gd:1-8` already claims to be the
only place bearing mathematics lives, so there is an obvious home for it. It is not
proposed for M4. It is written down because it converts section 7's dissent from a gamble
into an engineering task, and because the option quietly disappears if the sim's arithmetic
spreads out.

---

## 4. The design

### 4.1 Three rates, not one

[06](06-technical-architecture.md) says "15 Hz authoritative tick", which silently fuses
three independent numbers. Keep them apart:

| Rate | What it is | Constraint |
|---|---|---|
| **Simulation step** | How often `Battle.step` runs | Balance and the seeker floor (3.1). Currently 60 |
| **Command frame** | How often the server flushes accepted commands to clients | Latency the captain feels. Cheap: mostly empty |
| **Snapshot** | How often full state goes out | Bandwidth and client cost. This is the dial |

Only the third is expensive, and it is a tuning value.

### 4.2 The wire

**Client to server**, one message per order: `[kind, args]`.

- **Never an actor.** The server stamps it from the connection. A client that cannot name
  a ship cannot give orders to one, and `apply_command`'s actor check stays a range test
  instead of growing an authorisation concept.
- **Never a position, a hit, or a damage number.** Those are outputs.
- **Never a tick.** The client does not choose when its order lands.

**Server to client**, per command frame: the commands accepted for the ticks just executed,
as `[tick, actor, kind, args]`. That is a `BattleLog` frame, so the server's transcript of
what it sent and the replay of the battle are the same artifact.

**Server to client**, on join, on reconnect, on repair, and as periodic keyframes: a
snapshot.

**Coalesce the helm.** `_apply_sticks` issues an `order` command every physics frame while
a stick is held (`src/ui/combat_screen.gd:472`), which is 60 commands a second into a log
that appends without bound. One order per tick carrying the latest heading and throttle,
enforced at the door.

**Send the comm log as codes, not prose.** The sim builds display strings inside events
(`src/sim/battle.gd:190`, `:511`). Sending a code plus parameters is smaller, and it is the
right fix for CLAUDE.md 5.2 and 6.3 independently of any network.

### 4.3 Latency is spent as input delay

Every command is scheduled by the server for `execute_tick = now + delay`, and every
participant executes it on that tick. No rollback and no reconciliation.

**This is affordable for the reason [06](06-technical-architecture.md) section 1.1 gives**,
and it is the fact that makes this genre cheap to network: capital ships take seconds to
turn, so 200 ms on an order to a ship that needs four seconds to come about is under five
percent of the manoeuvre. There is no twitch aiming to protect.

**The helm is the one place it is felt**, and the interface already solves it: the sim
draws the order and the hull as different things (`ordered_heading` at
`src/sim/ship_state.gd:23`, the hull's own heading beside it). The ordered heading marker
moves the instant the stick does; the hull swings when the command executes. Nothing is
predicted and nothing has to be corrected.

### 4.4 The snapshot

Four things currently prevent a `Battle` being written down, all worth fixing regardless:

- `Battle._targets` is keyed by **`ShipState` object** (`src/sim/battle.gd:49`), and
  `Seeker` and `Tractor` hold `ShipState` references. Object identity does not serialise.
  `Debris.owner_index` already made the opposite choice and documented why; follow it.
- Identity comparisons throughout (`beam.holder == ship`, `target == player()`). Indices.
- `ShipState.terrain` and `ShipState.rng` are shared references, stored once and rewired on
  load.
- The generator's position in its stream is state. `RandomNumberGenerator.state` is
  readable and writable, so it is a field, but a snapshot that forgets it reproduces the
  setup and not the run.

Three rules for building it:

1. **Generate it, do not hand write it.** A hand written serialiser over roughly 35 fields
   of `ShipState` has no mechanism that could ever catch a forgotten one, and the failure
   is silent and permanent: miss `pad_cycles` (`src/sim/ship_state.gd:75`) and the marines
   panel shows every pad ready forever while the server refuses every beam. Godot exposes
   a script's variables through `get_property_list`, so snapshot and restore can be
   reflection driven and the round trip test fails automatically on any field anyone adds.
2. **The fingerprint is a projection of the snapshot, not a second walk.** Two traversals
   of a `Battle` will eventually disagree about what a `Battle` is, and the one that
   disagrees silently is the one deciding whether a client is wrong (CLAUDE.md 4.1).
3. **Send what cannot be recomputed, derive what can.** Terrain goes on the wire explicitly
   rather than being rebuilt from the seed: `Terrain.create` draws `sin`/`cos`
   (`src/sim/terrain.gd:125`), and terrain gates line of fire through `lock_broken`, so at
   most eighteen features is a cheap way to remove libm from the question of whether a shot
   is legal. Debris goes the other way: `Debris.burst` is a pure function of
   `seed_value + tick * 7919 + index` (`src/sim/battle.gd:194`, `src/sim/debris.gd:43`), all three of which the
   destroyed event already carries.

**Exercise the restore path constantly, or it will be broken the first time it is needed.**
Snapshot, restore into a fresh `Battle`, step both, compare fingerprints, on every tick of
the scripted battle in `tests/run_tests.gd`. Written first, not last.

**Keyframes fix something that is already broken.** `seek_replay` re-simulates from tick
zero (`src/ui/combat_screen.gd:420`), and its comment says there is no snapshot to restore,
by design. Measured on this machine, a two ship duel steps at 248 us per tick in open space
and 382 us in an asteroid belt, native and headless. A thirty minute battle at 60 Hz is
108,000 ticks, so scrubbing to the end costs about 27 seconds for the smallest possible
battle, on the fastest possible target, and it grows with ship count against an O(n squared)
contact and point defense pass. Keyframes inside the log turn a scrub into a restore plus a
few hundred ticks, and they fix cross build replay drift at the same time, at roughly a
kilobyte or two per keyframe.

### 4.5 The fingerprint has to be split, and it is not sufficient today

`fingerprint` covers tick, winner, seekers in flight, and each ship's position, heading,
speed, boxes, shields and liveness, with floats snapped to a thousandth
(`src/sim/battle_log.gd:163`). Two problems:

- **It omits state that decides battles**: generator position, battery, weapon charge,
  debris and tractors. Two runs can agree on the fingerprint and still be different runs.
- **It is fragile in both directions at once.** Snapping to a thousandth means a value on
  a boundary can round differently on two machines that agree to within a last bit, while
  the discrete state it should be strictest about is compared with the same tolerance as
  a position.

Split it: an **exact** hash of the discrete state (boxes, alive, captured, winner, tick,
generator draw position) and a **tolerant** comparison of the continuous state. Arbitrate
on the first. Report the second. The discrete half is what actually decides a battle, and
it is the half that cannot drift a little.

### 4.6 `apply_command` is not a protocol yet

It validates the actor range and nothing else. No arity check, no weapon index bound, no
shield facing bound, no power sink name check outside a release stripped assert, and no
`is_finite`. Several kinds crash on hostile input and several more poison every float in a
ship: a NaN through `order` passes `fposmod` and `clampf` untouched and reaches `pos`.

Under any networked design this function is the wire parser. Hardening it is a
**precondition for opening the socket**, not a follow up, and it is roughly a day of work.
Note the shape to copy: `tractor_plan` already refuses a no op (`src/sim/battle.gd:666`),
which is what stops `order`, `shield_bias` and `power` from letting one client grow the
server's log without bound. `record()` should also duplicate the args array rather than
storing the caller's by reference.

The payoff is worth stating plainly: **the validator and the rules are the same code**, so
there is no separate server side rules check to write and none to keep in step (CLAUDE.md
4.1).

### 4.7 Both ends must agree about the data, and nothing checks

`Catalog` caches `data/*.json` and has no version, hash or identity of any kind
(`src/sim/catalog.gd:16`). A client with a retuned `weapons.json` computes different damage
and nothing anywhere notices. It is worse than it looks: the AI reads
`Catalog.tuning()["ai"]` every step (`src/sim/ai.gd:14`), so a one character difference in
tuning diverges every tick.

Hash the contents of the sim's data files in a fixed order at load, expose it as
`Catalog.data_id()`, put it in the join handshake and stamp it beside `FORMAT_VERSION` in
`BattleLog`. That turns [11](11-battle-logs-and-replay.md) section 5's warning into
something a replay asserts.

**One decision first:** `data/tuning.json` mixes presentation (`view`, `camera`,
`explosion`, `wreck`, `terrain_view`) with simulation (`combat`, `power`, `tractor`,
`repair`, `ai`). Split it, or hash only the simulation keys, so a camera tweak cannot
refuse a join.

### 4.8 Where cheating actually pays is the result, not the battle

A prize is computed on the client, from the losing `ShipState`, and written straight into
the session's fleet (`src/ui/combat_screen.gd:675`, `src/ui/session.gd:54`). Once ships
persist, that is an economy exploit rather than an information advantage, and it is a much
more valuable thing to steal than a cloaked contact's position.

Signed, idempotent, server side result write back
([06](06-technical-architecture.md) section 3) is therefore part of the netcode boundary
rather than a separate persistence concern. Fits are resolved server side from what the
account owns, and `Session.fit` stays a client convenience.

---

## 5. What the client has to stop assuming

1. **That it is actor 0.** 23 literal `apply_command(0, ...)` call sites in the combat
   screen. They collapse into one `_order(kind, args)` that stamps the local seat, which
   is one place rather than twenty three (CLAUDE.md 4.1).
2. **That `ships[0]` is me and `ships[1]` is the enemy.** Roughly twenty five
   `player()`/`enemy()` calls across the front end. The seat becomes a parameter of the
   view.
3. **That events are told from its point of view.** `target_player` becomes a ship index,
   and `holder_player` should simply be deleted: nothing reads it.
4. **That it owns and steps the battle.** `_physics_process` already branches between live
   and replay (`src/ui/combat_screen.gd:321-338`). A third branch for network is how that
   screen becomes a fork. Collapse the two into one step path fed by a session, and network
   is a third source of commands rather than a third code path.
5. **That the arena holds two ships.** The scene authors exactly two rigs and two target
   brackets. More contacts means a fixed authored pool, which is a scene change and stays
   inside CLAUDE.md 5.1, or a documented section 7 exception. Decide before building.

**And one binding rule genuinely collides.** CLAUDE.md 6.2 says Escape, or the menu button,
always pauses. In a shared battle no client can stop the server. This does not need a
section 7 exception so much as a **scope clause**: single player keeps the pause it has,
and in a shared battle Escape opens the menu over a running fight, which is exactly what
the rule's own test permits, since a captain absolutely would reach for a menu under fire
and would not expect the enemy to freeze. The real dependent is not the tactical view but
the settings panel's pause and restore contract (`src/ui/main.gd:88-100`), which is built
entirely on a local freeze. **This needs agreement before the first line of netcode**, per
CLAUDE.md 7, and it is proposed here rather than assumed.

---

## 6. Build order

Steps 0 to 3 involve no networking at all.

**M4.0. One step size.** Section 3.1. Fix the mismatch by adopting the rate the game is
balanced at, collapse `replay_step` into one `step`, add the test that records through the
game's own loop.
*Proves it:* a battle recorded by playing replays to an identical fingerprint.

**M4.1. Sides and controllers.** Section 3.2. N ships, a side and a controller each, the AI
called per ship inside the one step loop, relative event flags replaced by indices, a log
that records every fit.
*Proves it:* a 2v2 runs, and the existing suite still passes. *This is M3 work. If M3 has
landed, it is already done.*

**M4.2. A `Battle` that can be written down.** Section 4.4. Reflection driven snapshot and
restore, fingerprint derived from the snapshot and split into discrete and continuous
halves, restore exercised on every tick of the scripted battle.
*Proves it:* snapshot mid fight, restore into a fresh `Battle`, step both to destruction,
discrete fingerprints identical every tick.

**M4.3. The door becomes a protocol, and the data gets a name.** Sections 4.6 and 4.7.
*Proves it:* a fuzz pass over `apply_command` cannot crash a battle or produce a non finite
number, and a log recorded against edited data refuses to replay silently.

**M4.4. Two clients and a server, on one machine.** The vertical slice. A dedicated server
export preset (none exists: all four presets set `dedicated_server=false`), the in project
entry point it needs, a WebSocket listener, join, scheduled command relay, and the tactical
view driven by the relayed stream. No Fly, no accounts, no database. Localhost.
*Proves it:* two people fight a duel end to end, and the server's log replays to the result
both of them saw.
*Watch for:* an exported release binary ignores `--script` and boots the main scene, so the
server needs a `dedicated_server` feature branch near `src/ui/main.gd:19` rather than a
command line entry point, and `scripts/verify-build.sh` hardcodes the linux target and
greps for a marker printed from a `Control._ready`, so the first working server export will
be reported as a broken build.

**M4.5. Fog of war.** Section 2's reason for the whole design, and an M4 deliverable in its
own right. Per client filtering reuses `ShipState.can_see` and `Terrain.lock_broken`, the
same functions the fire check calls, rather than a parallel visibility system.
*Proves it:* a client's connection carries no state for a contact it cannot see, verified
by reading the socket rather than the screen.

**M4.6. Join, reconnect, and the captain who leaves.** Falls out of M4.2 and M4.4: a joiner
gets a snapshot before a command stream, and a spectator is a joiner with no seat, which is
the replay path again. **What happens when a captain disconnects is a design question with
an answer already in M3:** hot swap control with transfer lag is the AI taking a seat at a
deterministic tick, so it belongs in the sim, in the log, in the fingerprint and in the
prize rules.
*Proves it:* a client killed mid battle rejoins to the same fight, and a captain who never
comes back leaves a ship that fights on.

**M4.7. Everything else.** Accounts, signed join tokens, server side result write back, the
Fly Machines API, warm pools, TTLs. [06](06-technical-architecture.md) sections 3, 5 and
10, better specified once a battle has been fought over a socket.

**Running alongside, from M4.0:** the cross build determinism canary (section 3.3) and the
24 ship frame budget (section 9).

---

## 7. The dissent, recorded

The client side replica was argued properly and lost on one point, so the point is written
down rather than the conclusion alone. In its favour:

- It creates **no second code path**: client and server call the same `Battle.step`, and
  the client is the replay loop that already exists.
- **The simulation is the interpolator.** The authoritative design has to write a motion
  model for other ships between snapshots; the replica gets the real integrator doing that
  job.
- It avoids the serialiser being the **only** description of a ship.
- The wire is one to two orders of magnitude smaller, though at
  [06](06-technical-architecture.md)'s own estimate of 45 KB/s that buys nothing.

It lost because M4 owes fog of war, and a replica forecloses it (section 2). Two smaller
counts: the dial from "relay" to "snapshot every tick" is not continuous, because at the
far end the replica is stepping only to have its work discarded, so the real fallback is to
stop stepping and interpolate, which is a renderer that does not exist; and a browser
stepping a 24 ship battle is an unmeasured cost on the weakest target.

**The condition under which it becomes correct:** a battle with no hidden information, a
cross build determinism canary that has been clean over a real corpus, and a measured
browser step budget. Then a replica is a legitimate optimisation for those battles, bought
with zero architectural commitment made now. Section 3.3's vendored transcendentals would
turn the first condition from a hope into an engineering task. This is why the canary is in
the build order even though nothing in M4 depends on it.

---

## 8. Where this refines docs/06

Section 4 of that document is not wrong, and its foundations are kept: server
authoritative, WebSocket over TLS rather than UDP, intents rather than positions, interest
management as security, one Machine per battle. Three things change.

| docs/06 says | This says | Why |
|---|---|---|
| The wire carries delta compressed **state**, roughly 45 KB/s per client | The wire carries **commands**, with state on join, repair and as keyframes | The command stream already exists as `BattleLog`, and it keeps the server's transcript and a replay the same artifact instead of splitting them into a command log and a snapshot stream |
| "Determinism is not required" | Correct, and it is still worth **measuring** | Same binary determinism underwrites replay and the test suite either way, and the canary is what makes a later client replica a decision rather than a rewrite |
| A "15 Hz authoritative tick" | Three separate rates (4.1), and the simulation step is a balance decision with a floor | The prototype runs at 60 and its logs claim 30. The number is a measurement, and moving it is a rebalance |

Nothing here contradicts the topology, the persistence model, the cost model or the region
sharding argument. Those stand.

---

## 9. Open, and deliberately not decided here

- **The simulation step.** 60 as the game runs and is balanced, or lower for server cost,
  paid for with a rebalance and floored around 5 to 6 Hz by seeker impact (3.1).
- **Input delay: fixed or adaptive.** Fixed is simpler and fairer. Adaptive is kinder to
  one bad connection and makes the tick a command executes on depend on something other
  than the battle, which is a reproducibility problem.
- **Allegiance.** Teams or a free for all, and whether friendly fire is legal (3.2). This
  is a design question for [01](01-tactical-combat.md) that netcode cannot answer and
  cannot proceed far without.
- **The 24 ship frame budget on `gl_compatibility` in a browser.** `ship_rig.gd` runs
  envelope runs, a posed disc per run, six shield segments, the turn arc, fires and flares
  per ship per frame, plus a target bracket painting in `_draw`. It runs twice today. This
  is the gating measurement for the whole milestone, and if the browser cannot draw
  twenty four ships then the twenty four ship bandwidth arithmetic in
  [06](06-technical-architecture.md) was answering the wrong question. **Measure it before
  choosing anything else.**
- **How N ships deploy.** `start_positions` returns two facing each other. Two lines of
  battle, per team clusters, or a ring is a scenario design decision
  ([01](01-tactical-combat.md)).
- **PvP fitting rules.** Whether captains agree a tonnage limit, and where it is enforced.
  Server side, through `ShipFit.budgets` (`src/sim/fit.gd:138`), which is the same code the
  fitting screen uses.

## 10. Not in this plan

Accounts, the database, matchmaking, the Fly Machines lifecycle, and the entire galaxy
layer. They are real and they are specified in [06](06-technical-architecture.md). They are
excluded because the first thing to learn is whether two people fighting each other in this
simulation is any good, and none of them are needed to find that out.
