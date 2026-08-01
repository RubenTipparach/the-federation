class_name Catalog
extends RefCounted

## Loads and caches the data files in res://data/. The one place JSON is read,
## so number coercion (JSON parses every number as float) happens exactly once.

const SHIPS_PATH: String = "res://data/ships.json"
const WEAPONS_PATH: String = "res://data/weapons.json"
const TUNING_PATH: String = "res://data/tuning.json"
const STATIONS_PATH: String = "res://data/stations.json"
const MAPS_PATH: String = "res://data/maps.json"

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


## The tactical view's subsystem stations: what each tab is called, which
## committed icon it wears, which box it speaks for, and which strip it sits
## in. Configuration rather than tuning, but it lives in a data file for the
## same reason (CLAUDE.md 5.4): a station list scattered across inspector
## fields is neither diffable nor reviewable.
static func stations() -> Dictionary:
	return _load_json(STATIONS_PATH)["stations"]


static func station(id: String) -> Dictionary:
	var all: Dictionary = stations()
	assert(all.has(id), "unknown station: " + id)
	return all[id]


## Station ids in display order, filtered to one strip. The order lives in the
## data file so reordering the tabs is a data change, not a scene edit.
static func station_ids(side: String = "") -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var all: Dictionary = stations()
	for id in _load_json(STATIONS_PATH)["order"]:
		var key: String = String(id)
		if all.has(key) and (side.is_empty() or String(all[key]["side"]) == side):
			out.append(key)
	return out


## The skirmish map recipes (docs/13 section 5). A recipe says how many of each
## kind of feature to place and in what size band; where they land is drawn
## from the battle seed, in Terrain.
static func maps() -> Dictionary:
	return _load_json(MAPS_PATH)["maps"]


static func map(id: String) -> Dictionary:
	var all: Dictionary = maps()
	assert(all.has(id), "unknown map: " + id)
	return all[id]


## Map ids in display order, so reordering the picker is a data change.
static func map_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var all: Dictionary = maps()
	for id in _load_json(MAPS_PATH)["order"]:
		if all.has(String(id)):
			out.append(String(id))
	return out


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
