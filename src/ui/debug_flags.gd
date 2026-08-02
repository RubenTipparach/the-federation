class_name DebugFlags
extends RefCounted

## The debug overlay's switches, and the one place anything asks about them.
##
## Every flag is VIEW ONLY. A flag may hide something, stop something
## repainting, or lower a render scale. None of them may reach the simulation,
## which is what makes the overlay safe to leave in a shipped build: a battle
## plays out identically whatever is switched off, and a replay of it still
## reproduces (CLAUDE.md 5.2).
##
## The list lives in data/debug.json, not here, so adding a switch is a data
## entry plus one read at the place that decides the thing. The panel itself
## knows nothing about what any flag means: it lists them, flips them, and shows
## the counters. That is what stops this growing into a switch statement that
## every new toggle has to be threaded through (CLAUDE.md 4.2, open closed).
##
## Read at the point of decision, never cached by a consumer. A flag that a
## system read once at startup would silently stop responding, and the whole
## value of this thing is flipping something and watching the number move.

const PATH: String = "res://data/debug.json"

## id to current value. Booleans are bools, cycles hold the current entry.
static var _values: Dictionary = {}
static var _spec: Dictionary = {}
static var _order: Array = []


static func _load() -> void:
	if not _spec.is_empty():
		return
	var f: FileAccess = FileAccess.open(PATH, FileAccess.READ)
	assert(f != null, "missing debug flags: " + PATH)
	var data: Dictionary = JSON.parse_string(f.get_as_text())
	_spec = data["flags"]
	_order = data["order"]
	for id in _order:
		var key: String = String(id)
		assert(_spec.has(key), "debug order names unknown flag: " + key)
		var entry: Dictionary = _spec[key]
		_values[key] = entry["default"] if String(entry["kind"]) == "bool" \
			else entry["values"][0]


## The flags in the order the panel should show them, worst first.
static func ids() -> Array:
	_load()
	return _order


## The combat screen nodes a flag hides, or an empty list when it only gates
## work. Read from the data file so the mapping lives beside the flag it
## belongs to rather than in a table in the screen (CLAUDE.md 5.4).
static func nodes(id: String) -> Array:
	return spec(id).get("nodes", [])


## The timing bucket a flag owns in HudProfile, or "" when it measures nothing.
static func part(id: String) -> String:
	return String(spec(id).get("part", ""))


static func spec(id: String) -> Dictionary:
	_load()
	assert(_spec.has(id), "unknown debug flag: " + id)
	return _spec[id]


## True when a boolean flag is on. Anything not a boolean is on by definition,
## so a caller that asks the wrong question gets the harmless answer.
static func on(id: String) -> bool:
	_load()
	return bool(_values.get(id, true))


## The current value of a cycling flag.
static func value(id: String) -> Variant:
	_load()
	return _values.get(id, null)


static func number(id: String, fallback: float) -> float:
	_load()
	var v: Variant = _values.get(id, null)
	return fallback if v == null else float(v)


## Advance a flag: booleans invert, cycles step to the next value and wrap.
static func advance(id: String) -> void:
	_load()
	var entry: Dictionary = spec(id)
	if String(entry["kind"]) == "bool":
		_values[id] = not bool(_values[id])
		return
	var values: Array = entry["values"]
	var at: int = values.find(_values[id])
	_values[id] = values[(at + 1) % values.size()]


## What the panel prints on the button: the label, and the value when there is
## one worth reading.
static func caption(id: String) -> String:
	_load()
	var entry: Dictionary = spec(id)
	if String(entry["kind"]) == "bool":
		return "%s  %s" % [String(entry["label"]), "ON" if on(id) else "OFF"]
	return "%s  %s" % [String(entry["label"]), str(_values[id])]


## True when anything at all has been switched away from its default, so the
## overlay can say plainly that what is on screen is not the real game.
static func modified() -> bool:
	_load()
	for id in _values:
		var entry: Dictionary = _spec[id]
		var base: Variant = entry["default"] if String(entry["kind"]) == "bool" \
			else entry["values"][0]
		if _values[id] != base:
			return true
	return false


static func reset() -> void:
	_load()
	for id in _values:
		var entry: Dictionary = _spec[id]
		_values[id] = entry["default"] if String(entry["kind"]) == "bool" \
			else entry["values"][0]
