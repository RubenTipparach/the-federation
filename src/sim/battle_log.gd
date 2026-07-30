class_name BattleLog
extends RefCounted

## A battle, written down completely enough to play it again.
##
## The log holds the setup (both designs, the seed, the fixed step) and every
## command anyone gave, stamped with the tick it was given on. Nothing else is
## recorded: positions, damage, and outcomes are not stored because they are
## derived, and storing them would let a replay disagree with the simulation
## that produced it. Replaying means running the same code over the same
## commands, which is exactly what makes it useful for reproducing a bug.
##
## Determinism rests on three things, all enforced here or in Battle:
##   1. Fixed dt. Commands are stamped by tick, never by wall clock.
##   2. One seeded RandomNumberGenerator, shared by both ships and drawn from
##      in a fixed order by the step loop.
##   3. Every command goes through Battle.command(), so nothing can change the
##      battle without being written down (CLAUDE.md 4.1).

const FORMAT_VERSION: int = 1

var seed_value: int = 0
var dt: float = 1.0 / 30.0
var player_hull: String = ""
var player_slots: Dictionary = {}
var enemy_hull: String = ""

## Commands as [tick, actor, kind, args], the smallest thing that replays.
var commands: Array = []

## The tick the recording stopped on. A log without it is incomplete: a replay
## would not know whether the battle ended by attrition or was simply left, and
## two runs of different lengths are not comparable.
var end_tick: int = -1

## Filled in when the recording stops, and compared after a replay.
var result: Dictionary = {}


static func create(fit: ShipFit, enemy_hull_id: String, seed_v: int,
		step_dt: float) -> BattleLog:
	var log: BattleLog = BattleLog.new()
	log.seed_value = seed_v
	log.dt = step_dt
	log.player_hull = fit.hull_id
	log.player_slots = fit.slots.duplicate()
	log.enemy_hull = enemy_hull_id
	return log


func record(tick: int, actor: int, kind: String, args: Array) -> void:
	commands.append([tick, actor, kind, args])


func commands_at(tick: int) -> Array:
	var out: Array = []
	for c in commands:
		if int(c[0]) == tick:
			out.append(c)
	return out


func last_tick() -> int:
	var last: int = 0
	for c in commands:
		last = maxi(last, int(c[0]))
	return last


# ---- serialisation -----------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"format": FORMAT_VERSION,
		"seed": seed_value,
		"dt": dt,
		"player_hull": player_hull,
		"player_slots": player_slots,
		"enemy_hull": enemy_hull,
		"commands": commands,
		"end_tick": end_tick,
		"result": result,
	}


static func from_dict(d: Dictionary) -> BattleLog:
	var log: BattleLog = BattleLog.new()
	log.seed_value = int(d.get("seed", 0))
	log.dt = float(d.get("dt", 1.0 / 30.0))
	log.player_hull = String(d.get("player_hull", ""))
	log.player_slots = d.get("player_slots", {})
	log.enemy_hull = String(d.get("enemy_hull", ""))
	log.commands = d.get("commands", [])
	log.end_tick = int(d.get("end_tick", -1))
	log.result = d.get("result", {})
	return log


func save(path: String) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true


static func load_from(path: String) -> BattleLog:
	if not FileAccess.file_exists(path):
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	return BattleLog.from_dict(parsed)


# ---- replay ------------------------------------------------------------------

## Stamp where the recording stopped. Call this when a battle is left as well
## as when it ends, so the log always says how long it ran.
func close(battle: Battle) -> void:
	end_tick = battle.tick
	result = BattleLog.fingerprint(battle)


## Rebuild the battle this log describes and run it back. Returns the finished
## Battle, so a caller can compare its fingerprint against the recorded result
## or hand it to the tactical view to watch.
##
## It runs to the recorded end tick. extra_ticks only applies to a log that was
## never closed, which should not happen but is worth surviving.
## The battle this log starts from, before any command is applied. Shared by
## the headless replay and the screen that watches one, so a watched replay and
## a tested replay begin from the same state.
func replay_setup() -> Battle:
	var fit: ShipFit = ShipFit.create_default(player_hull)
	for mount_id in player_slots.keys():
		fit.slots[String(mount_id)] = String(player_slots[mount_id])
	return Battle.create_duel(fit, enemy_hull, seed_value)


func replay(extra_ticks: int = 0) -> Battle:
	var battle: Battle = replay_setup()
	var until: int = end_tick if end_tick >= 0 else last_tick() + extra_ticks
	while battle.tick < until and not battle.over:
		for c in commands_at(battle.tick):
			battle.apply_command(int(c[1]), String(c[2]), c[3], false)
		battle.step(dt)
	return battle


## What a battle looks like when it is over, in numbers a replay must match
## exactly. Positions are rounded to a thousandth: floats that agree to that
## are the same run, and a mismatch beyond it means the replay diverged.
static func fingerprint(battle: Battle) -> Dictionary:
	var ships: Array = []
	for s in battle.ships:
		var shields: Array = []
		for v in s.shields:
			shields.append(snappedf(v, 0.001))
		ships.append({
			"hull": s.fit.hull_id,
			"pos": [snappedf(s.pos.x, 0.001), snappedf(s.pos.y, 0.001)],
			"heading": snappedf(s.heading, 0.001),
			"speed": snappedf(s.speed, 0.001),
			"boxes": s.total_boxes(),
			"shields": shields,
			"alive": s.alive,
		})
	return {
		"tick": battle.tick,
		"over": battle.over,
		"winner": battle.winner,
		"seekers": battle.seekers.size(),
		"ships": ships,
	}
