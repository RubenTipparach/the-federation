class_name ReplayStore
extends RefCounted

## Where recorded battles are kept, and how they are named. Small enough to be
## obvious, separate from the UI so a headless tool can list and replay the same
## files the game shows (CLAUDE.md 4.1, 5.2).

const DIR: String = "user://battles"


static func ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)


## A name that sorts chronologically and says what the battle was.
static func name_for(log: BattleLog, stamp: int) -> String:
	return "%d-%s-vs-%s.json" % [stamp, log.player_hull, log.enemy_hull]


static func save(log: BattleLog, stamp: int) -> String:
	ensure_dir()
	var path: String = DIR + "/" + name_for(log, stamp)
	return path if log.save(path) else ""


## Every recorded battle, newest first.
static func list_paths() -> Array[String]:
	var out: Array[String] = []
	var dir: DirAccess = DirAccess.open(DIR)
	if dir == null:
		return out
	for file in dir.get_files():
		if file.ends_with(".json"):
			out.append(DIR + "/" + file)
	out.sort()
	out.reverse()
	return out


## A one line description for a list row, without replaying anything.
static func describe(log: BattleLog) -> String:
	var player: String = String(Catalog.hull(log.player_hull)["name"])
	var foe: String = String(Catalog.hull(log.enemy_hull)["name"])
	var seconds: float = float(log.end_tick) * log.dt
	var outcome: String = "unfinished"
	if not log.result.is_empty():
		if bool(log.result.get("over", false)):
			outcome = "you won" if int(log.result.get("winner", -1)) == 0 else "you lost"
		else:
			outcome = "disengaged"
	return "%s vs %s   %ds   %d orders   %s" % [
		player, foe, int(seconds), log.commands.size(), outcome]
