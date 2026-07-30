# 11. Battle logs and replay

Every battle can be written down and played back exactly, from the setup to the
last shot. This exists for testing, for reproducing a bug someone hit once, and
for verifying that a change to the simulation did not quietly change the game.

---

## 1. What a log contains, and what it deliberately does not

A log holds the **setup** and the **commands**, nothing else:

| Recorded | Why |
|---|---|
| Seed | The one random source both ships draw from |
| Fixed step (`dt`) | Commands are stamped by tick, so the step size is part of the setup |
| Player hull and every mount's weapon | The design under test |
| Enemy hull | The opponent |
| Every command, as `[tick, actor, kind, args]` | The only things that change a battle from outside |
| End tick | How long the recording ran, so two runs are comparable |
| Result fingerprint | What the recorded run ended as, to compare against a replay |

**Positions, damage, and outcomes are not stored.** They are derived, and
storing them would let a replay disagree with the simulation that produced it.
Replaying means running the same code over the same commands and getting the
same answer, which is precisely what makes the file useful when something has
gone wrong.

A finished log is a few kilobytes of JSON. The whole of a two minute duel is
its seed, two hull names, five mount assignments, and a few dozen commands.

---

## 2. Why it replays exactly

Three things, and all three are enforced rather than hoped for:

1. **Fixed step.** `Battle.tick` counts steps and every command carries the tick
   it was given on. Nothing in the simulation reads a wall clock.
2. **One seeded generator.** `Battle.create_duel` builds a single
   `RandomNumberGenerator` from the seed and hands it to both ships, so every
   damage roll, every weighted box, and every seeker interception comes from one
   stream consumed in a fixed order.
3. **One door.** Every order goes through `Battle.apply_command`, whether it
   came from a button, a thumb stick, or a replay. A recording written at that
   point is complete by construction: there is no second path an input could
   take (CLAUDE.md 4.1).

The AI needs no special handling. It is a pure function of the battle state, so
the same state produces the same orders.

---

## 3. Using it

```gdscript
# Record: attach a log before the first step.
battle.log = BattleLog.create(fit, enemy_hull_id, seed, 1.0 / 30.0)
# ... play the battle. The combat screen does this for every skirmish.
battle.log.close(battle)          # stamps the end tick and the result
battle.log.save("user://battles/duel-0421.json")

# Replay, headless or on screen.
var log := BattleLog.load_from("user://battles/duel-0421.json")
var replayed := log.replay()
assert(BattleLog.fingerprint(replayed) == log.result)
```

`fingerprint` is the comparison: tick, winner, seekers in flight, and for each
ship its position, heading, speed, shields, remaining boxes, and whether it is
alive, with floats snapped to a thousandth. Two runs that agree on that
fingerprint are the same run.

---

## 4. What it is for

- **Reproducing a bug.** A log attached to a report is the bug, not a
  description of it. Replay it headlessly and the failure happens again.
- **Verifying a change.** Replay a corpus of logs before and after a change to
  the simulation. Fingerprints that shift are the behaviour that changed, and
  they are then either intended or a regression. Balance changes are supposed to
  shift them; a refactor is not.
- **Watching a battle back.** The replay returns a real `Battle`, so the
  tactical view can drive it exactly as it drives a live one.
- **Testing.** The suite records a scripted battle, replays it, and asserts the
  fingerprints match box for box, then does it again from JSON and from a file
  on disk. It also asserts that a different seed produces a different battle,
  which is what catches a seed being ignored somewhere.

---

## 5. Limits worth knowing

- A log is tied to the **data files and the code** it was recorded against.
  Retune `data/weapons.json` and old logs will replay differently, which is the
  point: that difference is the change you made. Logs used as regression
  baselines should be re-recorded deliberately, not silently.
- The format carries a `format` version. When the command set changes in a way
  old logs cannot express, bump it and keep a reader for the old one rather than
  breaking every recorded battle.
- Replay is only as deterministic as the simulation. If a future system reads
  the clock, samples input outside `apply_command`, or iterates an unordered
  container in a way that affects results, replay will drift and the tests here
  will catch it.
