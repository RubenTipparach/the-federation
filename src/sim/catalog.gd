class_name Catalog
extends RefCounted

## Loads and caches the data files in res://data/. The one place JSON is read,
## so number coercion (JSON parses every number as float) happens exactly once.

const SHIPS_PATH: String = "res://data/ships.json"
const FLEET_PATH: String = "res://data/fleet.json"
const FACTIONS_PATH: String = "res://data/factions.json"
const WEAPONS_PATH: String = "res://data/weapons.json"
const TUNING_PATH: String = "res://data/tuning.json"
const STATIONS_PATH: String = "res://data/stations.json"
const MAPS_PATH: String = "res://data/maps.json"

## Cache key for the merged hull table. Deliberately not a file path: it is not
## one file, it is two read and merged once, and every caller shares the result.
const HULLS_KEY: String = "hulls:merged"

static var _cache: Dictionary = {}


## `required` is false for a file the game can do without. A missing required
## file is a broken checkout and trips the assert; a missing optional one is an
## empty dictionary and the caller decides what that means.
static func _load_json(path: String, required: bool = true) -> Dictionary:
	if _cache.has(path):
		return _cache[path]
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		assert(not required, "missing data file: " + path)
		_cache[path] = {}
		return _cache[path]
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	assert(parsed is Dictionary, "data file is not a JSON object: " + path)
	_cache[path] = parsed
	return parsed


## Every hull in the game, hand authored and generated alike, as one table.
##
## data/ships.json holds the five hulls a person wrote and tuned. data/fleet.json
## holds the sixty written by tools/gen_ship_data.py, in the same schema field
## for field (docs/18-the-fleet.md section 1). They are two files because a
## generator that rewrote the hand authored five would reserialise them on every
## run and a reviewer could not tell a real change from a reformatting; they are
## one table here because nothing downstream should have to know which file a
## hull came from.
##
## ships.json wins a clash of ids: it is the authored file, the other is a build
## product. And fleet.json is optional, because a build product may be absent:
## a checkout without it is the five hull game that shipped before the fleet did,
## which is a smaller game and not a broken one.
static func hulls() -> Dictionary:
	if _cache.has(HULLS_KEY):
		return _cache[HULLS_KEY]
	var merged: Dictionary = {}
	merged.merge(_load_json(SHIPS_PATH)["hulls"])
	var fleet: Dictionary = _load_json(FLEET_PATH, false)
	if fleet.has("hulls"):
		merged.merge(fleet["hulls"])
	_cache[HULLS_KEY] = merged
	return merged


static func hull(id: String) -> Dictionary:
	var all: Dictionary = hulls()
	assert(all.has(id), "unknown hull: " + id)
	return all[id]


## The navies: id to what a heading calls them. data/factions.json owns both
## this and the order below, so adding a culture is a data change (CLAUDE.md
## 5.4) and two screens cannot end up with two ideas of the same fleet.
static func factions() -> Dictionary:
	return _load_json(FACTIONS_PATH)["factions"]


## Faction ids in display order, written the way station_ids() and map_ids() are.
static func faction_ids() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	var all: Dictionary = factions()
	for id in _load_json(FACTIONS_PATH)["order"]:
		if all.has(String(id)):
			out.append(String(id))
	return out


## What a heading calls a navy. An unnamed one falls back to its own id rather
## than to nothing, because a hull with a faction the order file forgot still
## has to be reachable.
static func faction_name(id: String) -> String:
	var all: Dictionary = factions()
	if all.has(id):
		return String(all[id]["name"])
	return id.capitalize()


## The class ladder, smallest hull first, in the spelling a hull's `cls` uses.
static func class_ladder() -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for cls in _load_json(FACTIONS_PATH)["ladder"]:
		out.append(String(cls))
	return out


## A list of hull ids gathered into navies, each navy in ladder order: the shape
## the skirmish screen draws, and the shape any later roster or shipyard listing
## should draw, because there is one answer to "what order do ships go in" and
## it lives in data/factions.json.
##
## Insertion order is the display order, so a caller iterates the result and
## does no sorting of its own. Ids the catalog does not know are dropped.
static func group_by_faction(ids: Array[String]) -> Dictionary:
	var all: Dictionary = hulls()
	var seen_factions: PackedStringArray = PackedStringArray()
	var members: Dictionary = {}
	for id in ids:
		if not all.has(id):
			continue
		var faction: String = String(all[id].get("faction", ""))
		if not members.has(faction):
			members[faction] = []
			seen_factions.append(faction)
		members[faction].append(id)
	var groups: Dictionary = {}
	for faction in _in_data_order(seen_factions, faction_ids()):
		groups[faction] = _in_class_order(members[faction])
	return groups


## One navy's hulls, smallest class first.
##
## Ordered by walking the ladder rather than by sorting on tonnage: tonnage
## happens to climb the ladder today, and the day a faction is given a heavier
## frigate than somebody's destroyer the list should still read as a ladder.
static func _in_class_order(ids: Array) -> Array[String]:
	var all: Dictionary = hulls()
	var seen: PackedStringArray = PackedStringArray()
	for id in ids:
		var cls: String = String(all[id].get("cls", ""))
		if not seen.has(cls):
			seen.append(cls)
	var out: Array[String] = []
	for cls in _in_data_order(seen, class_ladder()):
		for id in ids:
			if String(all[id].get("cls", "")) == cls:
				out.append(String(id))
	return out


## `values` put in the order `order` names them, with anything it does not name
## kept and appended in the order it arrived. One helper for the navies and for
## the classes, because that is one question asked twice (CLAUDE.md 4.1).
##
## Unnamed values are appended rather than dropped, which is where this parts
## company with station_ids(): a tab the order file forgets is a tab nobody
## misses, and a hull it forgets is a ship that cannot be flown.
static func _in_data_order(values: PackedStringArray,
		order: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	for want in order:
		if values.has(want) and not out.has(want):
			out.append(want)
	for v in values:
		if not out.has(v):
			out.append(v)
	return out


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
