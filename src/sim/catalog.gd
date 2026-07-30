class_name Catalog
extends RefCounted

## Loads and caches the data files in res://data/. The one place JSON is read,
## so number coercion (JSON parses every number as float) happens exactly once.

const SHIPS_PATH: String = "res://data/ships.json"
const WEAPONS_PATH: String = "res://data/weapons.json"
const TUNING_PATH: String = "res://data/tuning.json"

static var _cache: Dictionary = {}


static func _load_json(path: String) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert(f != null, "missing data file: " + path)
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "data file is not a JSON object: " + path)
	_cache[path] = parsed
	return parsed


static func hulls() -> Dictionary:
	return _load_json(SHIPS_PATH)["hulls"]


static func hull(id: String) -> Dictionary:
	var all: Dictionary = hulls()
	assert(all.has(id), "unknown hull: " + id)
	return all[id]


static func weapons() -> Dictionary:
	return _load_json(WEAPONS_PATH)["weapons"]


static func weapon(id: String) -> Dictionary:
	if id.is_empty():
		return {}
	var all: Dictionary = weapons()
	assert(all.has(id), "unknown weapon: " + id)
	return all[id]


static func tuning() -> Dictionary:
	return _load_json(TUNING_PATH)


## JSON arrays of numbers arrive as floats. Sector fields must be ints.
static func to_int_array(raw: Array) -> Array[int]:
	var out: Array[int] = []
	for v in raw:
		out.append(int(v))
	return out


static func playable_hull_ids() -> Array[String]:
	var out: Array[String] = []
	for id in hulls():
		if bool(hulls()[id].get("playable", false)):
			out.append(id)
	return out


static func ai_hull_ids() -> Array[String]:
	var out: Array[String] = []
	for id in hulls():
		if bool(hulls()[id].get("ai", false)):
			out.append(id)
	return out
