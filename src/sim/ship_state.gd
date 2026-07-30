class_name ShipState
extends RefCounted

## A ship in a battle: position on the plane, heading, shields, internal boxes,
## power split, weapon charge. This file owns the damage model (docs/01
## section 7) and exists exactly once; the SSD demo, the combat scene, and the
## AI all resolve damage through it (CLAUDE.md 4.1).
##
## Plane convention: pos is Vector2(x, z), heading in degrees, bearing 0 along
## +Z, clockwise seen from above. No Node dependencies: the sim must run and
## test headless without a scene tree (CLAUDE.md 5.2).

var fit: ShipFit
var rng: RandomNumberGenerator

var pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var ordered_heading: float = 0.0
var ordered_throttle: float = 0.0

var shield_max: float = 0.0
var shields: Array[float] = []

## Flat list of internal systems: {code, family, boxes_max, boxes, mount_id, row}.
var systems: Array[Dictionary] = []

## Runtime per mount: {mount, weapon, charge 0..1}. Index-aligned with
## fit.mounts() so UI rows and fire commands share indices.
var weapons_rt: Array[Dictionary] = []

## Power split as fractions of output summing to 1 (see PowerModel).
var split: Dictionary = {}
var battery: float = 0.0

var alive: bool = true


static func create(p_fit: ShipFit, p_rng: RandomNumberGenerator, ai_ship: bool = false) -> ShipState:
	var s: ShipState = ShipState.new()
	s.fit = p_fit
	s.rng = p_rng
	var h: Dictionary = p_fit.hull()
	s.shield_max = float(h["shield_per_facing"])
	for i in range(Sectors.FACING_COUNT):
		s.shields.append(s.shield_max)
	var row: int = 0
	for row_data in h["internals"]:
		for entry in row_data:
			s.systems.append({
				"code": String(entry[0]),
				"boxes_max": int(entry[1]),
				"boxes": int(entry[1]),
				"family": String(entry[2]),
				"mount_id": String(entry[3]) if entry.size() > 3 else "",
				"row": row,
			})
		row += 1
	for m in p_fit.mounts():
		s.weapons_rt.append({
			"mount": m,
			"weapon": p_fit.weapon_in(String(m["id"])),
			"charge": 0.0,
		})
	s.split = PowerModel.default_split(ai_ship)
	return s


# ---- derived integrity -------------------------------------------------------

func _family_ratio(family: String) -> float:
	var cur: int = 0
	var total: int = 0
	for sys in systems:
		if String(sys["family"]) == family:
			cur += int(sys["boxes"])
			total += int(sys["boxes_max"])
	return 1.0 if total == 0 else float(cur) / float(total)


func power_output() -> float:
	return float(fit.hull()["budgets"]["power"]) * _family_ratio("power")


func engine_integrity() -> float:
	return _family_ratio("power")


func max_speed() -> float:
	return float(fit.hull()["max_speed"]) * engine_integrity()


func turn_rate() -> float:
	return float(fit.hull()["turn_rate_deg"]) * engine_integrity()


func total_boxes() -> int:
	var n: int = 0
	for sys in systems:
		n += int(sys["boxes"])
	return n


func total_boxes_max() -> int:
	var n: int = 0
	for sys in systems:
		n += int(sys["boxes_max"])
	return n


func mount_disabled(index: int) -> bool:
	var mount_id: String = String(weapons_rt[index]["mount"]["id"])
	for sys in systems:
		if String(sys["mount_id"]) == mount_id:
			return int(sys["boxes"]) <= 0
	return false


func alloc_units(sink: String) -> float:
	return float(split.get(sink, 0.0)) * power_output()


func set_alloc_units(sink: String, units: float) -> void:
	var out: float = power_output()
	if out <= 0.0:
		return
	PowerModel.rebalance(split, sink, units / out)


# ---- orders and integration --------------------------------------------------

func set_order(p_heading: float, p_throttle: float) -> void:
	ordered_heading = Sectors.wrap_deg(p_heading)
	ordered_throttle = clampf(p_throttle, 0.0, 1.0)


func step(dt: float, tuning: Dictionary) -> void:
	if not alive:
		speed = maxf(0.0, speed - dt)
		pos += Vector2(sin(deg_to_rad(heading)), cos(deg_to_rad(heading))) * speed * dt
		return
	var combat: Dictionary = tuning["combat"]

	# Turn toward the ordered heading, no overshoot. Engine damage slows it.
	var delta: float = Sectors.turn_delta(heading, ordered_heading)
	var max_turn: float = turn_rate() * dt
	heading = Sectors.wrap_deg(heading + clampf(delta, -max_turn, max_turn))

	# Speed approaches ordered throttle times damaged max, engine power scales
	# acceleration so a ship running silent genuinely cannot chase.
	var eng_share: float = clampf(alloc_units("engines") / float(combat["engine_power_demand"]), 0.0, 1.25)
	var target_speed: float = ordered_throttle * max_speed() * minf(eng_share, 1.0)
	var accel: float = float(fit.hull()["accel"]) * maxf(eng_share, 0.2)
	speed = move_toward(speed, target_speed, accel * dt)
	pos += Vector2(sin(deg_to_rad(heading)), cos(deg_to_rad(heading))) * speed * dt

	# Weapon capacitors charge at a rate scaled by the weapons power share.
	var draw: float = maxf(fit.total_weapon_draw(), 0.001)
	var wpn_factor: float = clampf(alloc_units("weapons") / draw, 0.0, 1.25)
	for w in weapons_rt:
		if w["weapon"].is_empty():
			continue
		var reload: float = float(w["weapon"]["reload"])
		w["charge"] = minf(1.0, float(w["charge"]) + dt / reload * wpn_factor)

	# Shield regeneration split evenly across facings, scaled by shields power.
	var shd_share: float = clampf(
		alloc_units("shields") / float(combat["shield_power_demand"]), 0.0, 1.25)
	var regen: float = float(combat["shield_regen_per_sec"]) * shd_share * dt
	for i in range(shields.size()):
		shields[i] = minf(shield_max, shields[i] + regen)

	# Reserve power charges the battery that pays for shield reinforcement.
	battery = minf(1.0, battery + dt * alloc_units("reserve")
		* float(combat["battery_charge_per_reserve_unit"]))


# ---- firing ------------------------------------------------------------------

## Why a weapon can or cannot fire right now. Reasons match the mockup chips.
func fire_check(index: int, target_pos: Vector2) -> Dictionary:
	var w: Dictionary = weapons_rt[index]
	if w["weapon"].is_empty():
		return { "ok": false, "reason": "empty" }
	if mount_disabled(index):
		return { "ok": false, "reason": "destroyed" }
	if float(w["charge"]) < 1.0:
		return { "ok": false, "reason": "charging" }
	if pos.distance_to(target_pos) > float(w["weapon"]["range"]):
		return { "ok": false, "reason": "range" }
	var rel: float = Sectors.relative_bearing(Sectors.bearing_between(pos, target_pos), heading)
	if not fit.effective_field(w["mount"]).has(Sectors.sector_of_bearing(rel)):
		return { "ok": false, "reason": "no arc" }
	return { "ok": true, "reason": "bears" }


## Resolve one shot against a target. Returns the event for UI and logs.
func fire_at(index: int, target: ShipState) -> Dictionary:
	var w: Dictionary = weapons_rt[index]
	w["charge"] = 0.0
	var damage: int = int(w["weapon"]["damage"])
	var arrive_bearing: float = Sectors.bearing_between(target.pos, pos)
	var log_lines: Array[String] = target.apply_damage(arrive_bearing, float(damage))
	return {
		"type": "shot",
		"weapon": String(w["weapon"]["short"]),
		"damage": damage,
		"from_pos": pos,
		"to_pos": target.pos,
		"log": log_lines,
	}


# ---- the damage model --------------------------------------------------------

## Incoming fire resolves against the facing it arrives from: shield absorbs,
## the remainder rolls into internals weighted by remaining boxes, so a fit
## determines its own vulnerability profile (docs/01 section 7).
func apply_damage(world_bearing: float, amount: float) -> Array[String]:
	var lines: Array[String] = []
	var rel: float = Sectors.relative_bearing(world_bearing, heading)
	var facing: int = Sectors.facing_of_relative_bearing(rel)
	var remaining: float = amount
	if shields[facing] > 0.0:
		var absorbed: float = minf(shields[facing], remaining)
		shields[facing] -= absorbed
		remaining -= absorbed
		lines.append("Shield #%d absorbs %d, at %d" % [facing + 1, int(absorbed), int(shields[facing])])
		if shields[facing] <= 0.0:
			lines.append("SHIELD #%d DOWN, internals exposed" % [facing + 1])
	else:
		lines.append("Facing #%d already down" % [facing + 1])
	if remaining > 0.0:
		lines.append_array(apply_internal(remaining))
	return lines


## Weighted internal damage. Public so the SSD dry dock demo and tests can
## exercise the bleed rule directly.
func apply_internal(amount: float) -> Array[String]:
	var lines: Array[String] = []
	var remaining: float = amount
	while remaining > 0.0:
		var living: Array[Dictionary] = []
		var total: int = 0
		for sys in systems:
			if int(sys["boxes"]) > 0:
				living.append(sys)
				total += int(sys["boxes"])
		if living.is_empty():
			alive = false
			lines.append("SHIP DESTROYED, no systems remain")
			break
		var roll: float = rng.randf() * float(total)
		var pick: Dictionary = living[0]
		for sys in living:
			roll -= float(int(sys["boxes"]))
			if roll <= 0.0:
				pick = sys
				break
		var take: int = mini(int(pick["boxes"]), int(ceilf(remaining)))
		take = maxi(take, 1)
		pick["boxes"] = int(pick["boxes"]) - take
		remaining -= float(take)
		if int(pick["boxes"]) <= 0:
			lines.append("%s DESTROYED" % [String(pick["code"])])
		else:
			lines.append("%s takes %d, %d left" % [String(pick["code"]), take, int(pick["boxes"])])
	if total_boxes() <= 0:
		alive = false
	return lines


## Spend the battery to restore one facing (docs/01 section 4 reinforcement).
func reinforce(facing: int, tuning: Dictionary) -> bool:
	if battery < 1.0 or facing < 0 or facing >= shields.size():
		return false
	battery = 0.0
	shields[facing] = minf(shield_max, shields[facing] + float(tuning["combat"]["reinforce_amount"]))
	return true


func weakest_facing() -> int:
	var best: int = 0
	for i in range(shields.size()):
		if shields[i] < shields[best]:
			best = i
	return best
