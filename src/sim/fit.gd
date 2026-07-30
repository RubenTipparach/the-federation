class_name ShipFit
extends RefCounted

## A design: one hull plus the weapon fitted in each mount. This is the single
## fitting validator (CLAUDE.md 4.1): the fitting screen's projected budgets,
## the skirmish tonnage check, and the combat sim all call this code.

const SIZE_RANK: Dictionary = { "Light": 0, "Medium": 1, "Heavy": 2, "Spinal": 3 }

var hull_id: String = ""
var slots: Dictionary = {}  # mount id -> weapon id, "" for empty


static func create_default(p_hull_id: String) -> ShipFit:
	var fit: ShipFit = ShipFit.new()
	fit.hull_id = p_hull_id
	for m in Catalog.hull(p_hull_id)["mounts"]:
		fit.slots[m["id"]] = String(m.get("default", ""))
	return fit


func duplicate_fit() -> ShipFit:
	var fit: ShipFit = ShipFit.new()
	fit.hull_id = hull_id
	fit.slots = slots.duplicate()
	return fit


func hull() -> Dictionary:
	return Catalog.hull(hull_id)


func mounts() -> Array:
	return hull()["mounts"]


func weapon_in(mount_id: String) -> Dictionary:
	return Catalog.weapon(String(slots.get(mount_id, "")))


## Whether a weapon may be fitted to a mount. Size always binds. The mount's
## permitted families bind unless the weapon is special (docs/02 section 4.3).
func is_legal(mount: Dictionary, weapon: Dictionary) -> bool:
	if weapon.is_empty():
		return true
	if int(SIZE_RANK[String(weapon["size"])]) > int(SIZE_RANK[String(mount["size"])]):
		return false
	if bool(weapon.get("special", false)):
		return true
	return Array(mount["families"]).has(String(weapon["family"]))


func legal_weapons_for(mount: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for id in Catalog.weapons():
		if is_legal(mount, Catalog.weapon(id)):
			out.append(id)
	out.sort()
	return out


func set_slot(mount_id: String, weapon_id: String) -> bool:
	for m in mounts():
		if String(m["id"]) == mount_id:
			if not is_legal(m, Catalog.weapon(weapon_id)):
				return false
			slots[mount_id] = weapon_id
			return true
	return false


## The mount's field, unless a special weapon overrides it (docs/02 4.3).
func effective_field(mount: Dictionary) -> Array[int]:
	var w: Dictionary = weapon_in(String(mount["id"]))
	if not w.is_empty() and bool(w.get("special", false)) and w.has("override_field"):
		return Catalog.to_int_array(w["override_field"])
	return Catalog.to_int_array(mount["field"])


func covered_sectors() -> Array[int]:
	var seen: Dictionary = {}
	for m in mounts():
		if weapon_in(String(m["id"])).is_empty():
			continue
		for s in effective_field(m):
			seen[s] = true
	var out: Array[int] = []
	for s in seen:
		out.append(int(s))
	out.sort()
	return out


func blind_sectors() -> Array[int]:
	var covered: Array[int] = covered_sectors()
	var out: Array[int] = []
	for s in range(Sectors.COUNT):
		if not covered.has(s):
			out.append(s)
	return out


## Total damage that can bear into one sector at point blank: the alpha strike
## by bearing. Range falloff makes this the best case, which is the honest thing
## to project on a fitting screen (see WeaponModel).
func alpha_into(sector: int) -> int:
	var total: int = 0
	for m in mounts():
		var w: Dictionary = weapon_in(String(m["id"]))
		if not w.is_empty() and effective_field(m).has(sector):
			total += WeaponModel.max_damage(w)
	return total


## Damage per shot into one sector at a given distance, accuracy included.
## This is what the fitting screen charts when it asks "and at range 8?".
func expected_into(sector: int, distance: float) -> float:
	var total: float = 0.0
	for m in mounts():
		var w: Dictionary = weapon_in(String(m["id"]))
		if not w.is_empty() and effective_field(m).has(sector):
			total += WeaponModel.expected_damage_at(w, distance)
	return total


func max_range_into(sector: int) -> float:
	var best: float = 0.0
	for m in mounts():
		var w: Dictionary = weapon_in(String(m["id"]))
		if not w.is_empty() and effective_field(m).has(sector):
			best = maxf(best, WeaponModel.max_range(w))
	return best


## The four budgets: used vs max for space, mass, crew, and reactor demand vs
## output for power. This is the projection the fitting screen shows and the
## same numbers the sim consumes.
func budgets() -> Dictionary:
	var h: Dictionary = hull()
	var base: Dictionary = h["base_load"]
	var used: Dictionary = {
		"space": float(base["space"]),
		"mass": float(base["mass"]),
		"crew": float(base["crew"]),
		"power": float(base["power_draw"]),
	}
	for m in mounts():
		var w: Dictionary = weapon_in(String(m["id"]))
		if w.is_empty():
			continue
		var costs: Dictionary = w["costs"]
		used["space"] += float(costs["space"])
		used["mass"] += float(costs["mass"])
		used["crew"] += float(costs["crew"])
		used["power"] += float(costs["power_draw"])
	var caps: Dictionary = h["budgets"]
	return {
		"space": { "used": used["space"], "max": float(caps["space"]) },
		"power": { "used": used["power"], "max": float(caps["power"]) },
		"mass": { "used": used["mass"], "max": float(caps["mass"]) },
		"crew": { "used": used["crew"], "max": float(caps["crew"]) },
	}


func total_weapon_draw() -> float:
	var t: float = 0.0
	for m in mounts():
		var w: Dictionary = weapon_in(String(m["id"]))
		if not w.is_empty():
			t += float(w["costs"]["power_draw"])
	return t


func mounts_fitted() -> int:
	var n: int = 0
	for m in mounts():
		if not weapon_in(String(m["id"])).is_empty():
			n += 1
	return n


func derived() -> Dictionary:
	var blind: Array[int] = blind_sectors()
	return {
		"covered": Sectors.COUNT - blind.size(),
		"total_sectors": Sectors.COUNT,
		"blind": blind,
		"blind_label": Sectors.label_for_sectors(blind),
		"alpha_bow": alpha_into(0),
		"mounts_fitted": mounts_fitted(),
		"mount_count": mounts().size(),
	}
