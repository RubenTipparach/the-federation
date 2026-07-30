class_name WeaponModel
extends RefCounted

## Range falloff: the one place a weapon's reach, accuracy, and damage at a
## given distance are decided (CLAUDE.md 4.1). The fitting screen's projected
## alpha, the arc wheel's radius, the readiness chips, the AI's preferred range,
## and a real shot in a battle all ask this class, so a weapon can never be
## worth one thing on paper and another in combat.
##
## The shape is Federation Commander's (docs/09-reference-federation-commander.md):
## beams hold their accuracy and lose damage with range, torpedoes hold their
## damage and lose accuracy, disruptors lose both. The numbers are ours and live
## in data/weapons.json, never here (CLAUDE.md 5.4).

const NO_BAND: Dictionary = { "to": 0.0, "hit": 0.0, "damage": 0 }


## Every band of a weapon, ordered from point blank outward.
static func bands(weapon: Dictionary) -> Array:
	if weapon.is_empty():
		return []
	return weapon.get("falloff", [])


## The weapon's reach: the outer edge of its last band. A weapon with no bands
## cannot reach anything, which is what an empty mount should mean.
static func max_range(weapon: Dictionary) -> float:
	var b: Array = bands(weapon)
	return 0.0 if b.is_empty() else float(b[b.size() - 1]["to"])


## The band a shot at this distance falls in, or NO_BAND when out of reach.
static func band_at(weapon: Dictionary, distance: float) -> Dictionary:
	for b in bands(weapon):
		if distance <= float(b["to"]):
			return b
	return NO_BAND


## What a hit scores at this distance, before any shield absorbs it.
static func damage_at(weapon: Dictionary, distance: float) -> int:
	return int(band_at(weapon, distance)["damage"])


## The chance the shot connects at all, 0 when out of reach.
static func hit_chance_at(weapon: Dictionary, distance: float) -> float:
	return float(band_at(weapon, distance)["hit"])


## Damage per shot averaged over accuracy. This is the number to compare two
## weapons with, and what the fitting screen should chart against range.
static func expected_damage_at(weapon: Dictionary, distance: float) -> float:
	var b: Dictionary = band_at(weapon, distance)
	return float(b["hit"]) * float(b["damage"])


## Point blank damage: the alpha figure the fitting screen projects.
static func max_damage(weapon: Dictionary) -> int:
	var b: Array = bands(weapon)
	return 0 if b.is_empty() else int(b[0]["damage"])


## The longest reach in the catalog: the scale an arc chart should draw to, so
## the wheel never needs a hardcoded number that drifts from the data.
static func longest_range() -> float:
	var best: float = 0.0
	for id in Catalog.weapons().keys():
		best = maxf(best, max_range(Catalog.weapon(String(id))))
	return best


## Resolve one shot. Returns the damage scored, which is zero on a miss, so a
## caller never has to know whether this weapon misses or merely weakens.
static func roll_damage(weapon: Dictionary, distance: float, rng: RandomNumberGenerator) -> int:
	var b: Dictionary = band_at(weapon, distance)
	if rng.randf() > float(b["hit"]):
		return 0
	return int(b["damage"])
