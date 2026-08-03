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
##
## Overload is the same rule read at a different scale, which is why it is here
## and not a second damage path. A weapon armed to overload trades reach for
## weight: its distance is divided by the range multiplier before the band is
## looked up, and the band's damage is multiplied on the way out. Everything
## downstream, the chart, the readiness chip, the AI's preferred range and a
## real shot, asks these same functions with the flag set, so an overloaded
## weapon cannot be worth one thing on paper and another in combat.

const NO_BAND: Dictionary = { "to": 0.0, "hit": 0.0, "damage": 0 }


## Every band of a weapon, ordered from point blank outward.
static func bands(weapon: Dictionary) -> Array:
	if weapon.is_empty():
		return []
	return weapon.get("falloff", [])


## What overloading does to this weapon, or empty when it cannot be overloaded.
static func overload_profile(weapon: Dictionary) -> Dictionary:
	if weapon.is_empty():
		return {}
	return weapon.get("overload", {})


## Whether this weapon has an overload at all. The arming control and the fire
## check both ask here, so a mount can never be armed for a shot it cannot take.
static func can_overload(weapon: Dictionary) -> bool:
	return not overload_profile(weapon).is_empty()


## How much of its reach an overloaded shot keeps. 1.0 when the weapon has no
## overload or is not armed, so an unarmed weapon reads exactly as before.
static func range_scale(weapon: Dictionary, overloaded: bool) -> float:
	if not overloaded:
		return 1.0
	var o: Dictionary = overload_profile(weapon)
	return 1.0 if o.is_empty() else maxf(0.001, float(o.get("range", 1.0)))


## How much heavier an overloaded hit lands.
static func damage_scale(weapon: Dictionary, overloaded: bool) -> float:
	if not overloaded:
		return 1.0
	var o: Dictionary = overload_profile(weapon)
	return 1.0 if o.is_empty() else float(o.get("damage", 1.0))


## The weapon's reach: the outer edge of its last band. A weapon with no bands
## cannot reach anything, which is what an empty mount should mean.
static func max_range(weapon: Dictionary, overloaded: bool = false) -> float:
	var b: Array = bands(weapon)
	if b.is_empty():
		return 0.0
	return float(b[b.size() - 1]["to"]) * range_scale(weapon, overloaded)


## The band a shot at this distance falls in, or NO_BAND when out of reach.
static func band_at(weapon: Dictionary, distance: float,
		overloaded: bool = false) -> Dictionary:
	var reach: float = distance / range_scale(weapon, overloaded)
	for b in bands(weapon):
		if reach <= float(b["to"]):
			return b
	return NO_BAND


## What a hit scores at this distance, before any shield absorbs it.
static func damage_at(weapon: Dictionary, distance: float,
		overloaded: bool = false) -> int:
	return _weigh(band_at(weapon, distance, overloaded), weapon, overloaded)


## The chance the shot connects at all, 0 when out of reach.
static func hit_chance_at(weapon: Dictionary, distance: float,
		overloaded: bool = false) -> float:
	return float(band_at(weapon, distance, overloaded)["hit"])


## Damage per shot averaged over accuracy. This is the number to compare two
## weapons with, and what the fitting screen should chart against range.
static func expected_damage_at(weapon: Dictionary, distance: float,
		overloaded: bool = false) -> float:
	var b: Dictionary = band_at(weapon, distance, overloaded)
	return float(b["hit"]) * float(_weigh(b, weapon, overloaded))


## Point blank damage: the alpha figure the fitting screen projects.
static func max_damage(weapon: Dictionary, overloaded: bool = false) -> int:
	var b: Array = bands(weapon)
	return 0 if b.is_empty() else _weigh(b[0], weapon, overloaded)


## What a band is worth once the overload multiplier is in. Damage is whole
## boxes, so the product is rounded here rather than being carried as a float
## into the damage model, where a fractional box already means something else
## (ShipState.apply_internal).
static func _weigh(band: Dictionary, weapon: Dictionary, overloaded: bool) -> int:
	return roundi(float(band["damage"]) * damage_scale(weapon, overloaded))


## The longest reach in the catalog: the scale an arc chart should draw to, so
## the wheel never needs a hardcoded number that drifts from the data.
static func longest_range() -> float:
	var best: float = 0.0
	for id in Catalog.weapons().keys():
		best = maxf(best, max_range(Catalog.weapon(String(id))))
	return best


## Resolve one shot. Returns the damage scored, which is zero on a miss, so a
## caller never has to know whether this weapon misses or merely weakens.
##
## One draw from the generator either way, whether the shot is overloaded or
## not and whether it is in reach or not, because a replay steps the same
## generator in the same order as the battle it is reproducing (BattleLog).
static func roll_damage(weapon: Dictionary, distance: float,
		rng: RandomNumberGenerator, overloaded: bool = false) -> int:
	var b: Dictionary = band_at(weapon, distance, overloaded)
	if rng.randf() > float(b["hit"]):
		return 0
	return _weigh(b, weapon, overloaded)
