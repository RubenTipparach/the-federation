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

## Sector index of the hull core: the shared volume behind every facing. It has
## no shield and is only reachable once a struck sector has been stripped.
const CORE: int = -1

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

## Runtime per mount: {mount, weapon, charge 0..1, overload}. Index-aligned
## with fit.mounts() so UI rows and fire commands share indices.
var weapons_rt: Array[Dictionary] = []

## Power split as fractions of output summing to 1 (see PowerModel).
var split: Dictionary = {}
var battery: float = 0.0

var alive: bool = true

## The world this ship is flying in. Every terrain question a ship asks goes
## through here, so firing, the AI, and the target bracket cannot disagree about
## whether a contact is visible (CLAUDE.md 4.1). A bare ShipState outside a
## battle flies in an empty arena, which is why this is never null.
var terrain: Terrain = Terrain.new()

## Velocity a gravity well is giving the ship. Added to the heading vector
## during integration, so the ship keeps pointing where it was told and slides
## (docs/13 section 4.1).
var drift: Vector2 = Vector2.ZERO

## Velocity a tractor beam is imposing, and what it is easing toward. The target
## is cleared every step and rewritten by whatever beam is on this hull, so a
## beam that snaps stops towing without anything having to remember that it
## existed (Battle._step_tractors).
var tow: Vector2 = Vector2.ZERO
var tow_target: Vector2 = Vector2.ZERO

## Seconds before this hull can be hurt by running into something again, so
## resting against a rock is not damage every tick.
var collision_grace: float = 0.0

## Micrometeor damage banked but not yet worth a whole point. See
## Battle._apply_grind for why dust is not applied every tick.
var grind_credit: float = 0.0

## The facing the shield engineer is buying boxes for. Federation Commander
## 3C7 makes regeneration a purchase aimed at one shield at a time, so this is
## the choice of which shield, not a weighting.
var shield_bias: int = -1

## Energy the shields sink has accrued toward the next shield box. A box
## arrives when this reaches the price; nothing arrives if the sink is empty,
## because under 3C7 nothing comes back unbought.
var shield_credit: float = 0.0

## Seconds the shield generators are still recovering from an overloaded shot.
## While this is running they buy nothing, which is the "your shields sag for
## four seconds" of docs/GDD P3. Counted down in step, so a paused battle does
## not recover and a replay recovers at exactly the same ticks.
var shield_sag: float = 0.0

## Spare parts still aboard, and the stock the hull sailed with. Repair spends
## this and nothing refills it in flight: restocking happens at a base.
var parts: int = 0
var parts_max: int = 0

## How many boxes the damage control parties can work in parallel, expressed
## as a rate multiplier. Federation Commander 5G1 says the rating is not
## reduced by damage, so neither is this.
var damage_control: int = 1

## Indices into `systems`, in the order they will be worked. Only the head is
## under way: 5G4 requires a box to be finished before work moves elsewhere.
var repair_queue: Array[int] = []

## Seconds of work banked toward the head job's current box. Reset when a box
## completes, so a job that is dropped and requeued does not carry credit.
var repair_progress: float = 0.0


static func _make_system(entry: Array, sector: int) -> Dictionary:
	return {
		"code": String(entry[0]),
		"boxes_max": int(entry[1]),
		"boxes": int(entry[1]),
		"family": String(entry[2]),
		"mount_id": String(entry[3]) if entry.size() > 3 else "",
		"sector": sector,
	}


static func create(p_fit: ShipFit, p_rng: RandomNumberGenerator, ai_ship: bool = false) -> ShipState:
	var s: ShipState = ShipState.new()
	s.fit = p_fit
	s.rng = p_rng
	var h: Dictionary = p_fit.hull()
	s.shield_max = float(h["shield_per_facing"])
	for i in range(Sectors.FACING_COUNT):
		s.shields.append(s.shield_max)
	var internals: Dictionary = h["internals"]
	var facing: int = 0
	for sector_rows in internals["sectors"]:
		for entry in sector_rows:
			s.systems.append(ShipState._make_system(entry, facing))
		facing += 1
	for entry in internals["core"]:
		s.systems.append(ShipState._make_system(entry, ShipState.CORE))
	for m in p_fit.mounts():
		s.weapons_rt.append({
			"mount": m,
			"weapon": p_fit.weapon_in(String(m["id"])),
			"charge": 0.0,
			"overload": false,
		})
	s.split = PowerModel.default_split(ai_ship)
	s.parts_max = int(h.get("spare_parts", 0))
	s.parts = s.parts_max
	s.damage_control = int(h.get("damage_control", 1))
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


## Living systems in one sector, or in the core when asked for CORE.
func systems_in(sector: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sys in systems:
		if int(sys["sector"]) == sector:
			out.append(sys)
	return out


func boxes_in(sector: int) -> int:
	var n: int = 0
	for sys in systems:
		if int(sys["sector"]) == sector:
			n += int(sys["boxes"])
	return n


## Boxes still standing in the named system, summed over every sector that
## carries one. Zero means the system is out, which is how the tractor knows its
## emitter is dead and how any other system check should ask.
func system_boxes(code: String) -> int:
	var n: int = 0
	for sys in systems:
		if String(sys["code"]) == code:
			n += int(sys["boxes"])
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
	collision_grace = maxf(0.0, collision_grace - dt)
	if not alive:
		speed = maxf(0.0, speed - float(tuning["combat"]["dead_ship_decel"]) * dt)
		_step_drift(dt, tuning)
		pos += velocity() * dt
		return
	var combat: Dictionary = tuning["combat"]

	# Turn toward the ordered heading, no overshoot. Engine damage slows it.
	var delta: float = Sectors.turn_delta(heading, ordered_heading)
	var max_turn: float = turn_rate() * dt
	heading = Sectors.wrap_deg(heading + clampf(delta, -max_turn, max_turn))

	# Speed approaches ordered throttle times damaged max, engine power scales
	# acceleration so a ship running silent genuinely cannot chase.
	var overdrive: float = float(combat["overdrive_cap"])
	var eng_share: float = clampf(
		alloc_units("engines") / float(combat["engine_power_demand"]), 0.0, overdrive)
	var target_speed: float = ordered_throttle * max_speed() * minf(eng_share, 1.0)
	var accel: float = float(fit.hull()["accel"]) * maxf(
		eng_share, float(combat["min_accel_factor"]))
	speed = move_toward(speed, target_speed, accel * dt)
	_step_drift(dt, tuning)
	pos += velocity() * dt

	# Weapon capacitors charge at a rate scaled by the weapons power share.
	var draw: float = maxf(fit.total_weapon_draw(), 0.001)
	var wpn_factor: float = clampf(
		alloc_units("weapons") / draw, 0.0, float(combat["overdrive_cap"]))
	for w in weapons_rt:
		if w["weapon"].is_empty():
			continue
		var reload: float = float(w["weapon"]["reload"])
		w["charge"] = minf(1.0, float(w["charge"]) + dt / reload * wpn_factor)

	shield_sag = maxf(0.0, shield_sag - dt)
	_step_shield_regen(dt, combat)
	_step_repair(dt, tuning)

	# Reserve power charges the battery that pays for shield reinforcement.
	battery = minf(1.0, battery + dt * alloc_units("reserve")
		* float(combat["battery_charge_per_reserve_unit"]))


func heading_vector() -> Vector2:
	return Vector2(sin(deg_to_rad(heading)), cos(deg_to_rad(heading)))


## What the ship would be doing under its own power in the world it is in: the
## motion a tractor has to argue with. Kept separate from velocity() so the tow
## a beam computes does not feed back into the tow it computed last frame.
func engine_velocity() -> Vector2:
	return heading_vector() * speed + drift


## Where the hull is actually going: what the engines are doing plus everything
## dragging it. One answer, used by integration, by the dust that grinds the
## leading facing, and by anything that needs to draw a velocity.
func velocity() -> Vector2:
	return engine_velocity() + tow


## Ease the carried velocities toward what the world and any tractor are asking
## for, and toward nothing when nothing is asking. Easing rather than
## integrating a force keeps this stable at any timestep, which a replay depends
## on (docs/13 sections 4.1 and 6.3).
func _step_drift(dt: float, tuning: Dictionary) -> void:
	if not (terrain.features.is_empty() and drift == Vector2.ZERO):
		var want: Vector2 = terrain.pull_at(pos)
		var rate: float = float(tuning["terrain"]["drift_accel"]) * dt
		drift = Vector2(
			move_toward(drift.x, want.x, rate),
			move_toward(drift.y, want.y, rate))
	if tow == Vector2.ZERO and tow_target == Vector2.ZERO:
		return
	var blend: float = float(tuning["tractor"]["blend_rate"]) * dt
	tow = Vector2(
		move_toward(tow.x, tow_target.x, blend),
		move_toward(tow.y, tow_target.y, blend))


## The range the gunnery computer believes it is shooting at: the true distance
## plus whatever cloud is in the way. Every range decision a ship makes reads
## this rather than pos.distance_to, so nebulae degrade gunnery through the one
## falloff rule WeaponModel already owns.
func apparent_range_to(target_pos: Vector2) -> float:
	return terrain.apparent_range(pos, target_pos, pos.distance_to(target_pos))


## Whether a lock can be held on a point at all. The firing check and the target
## bracket both call this, so a contact that cannot be shot at cannot be drawn.
func can_see(target_pos: Vector2) -> bool:
	return not terrain.lock_broken(pos, target_pos)


## Shield boxes are bought, not handed back. Federation Commander 3C7: "you can
## pay two Energy Tokens to regenerate (remove the disabled mark from) any one
## shield box on any one shield." Energy from the shields sink accrues here and
## buys whole boxes at a fixed price, one facing at a time, so a player who
## spends nothing on shields gets nothing back. The old version handed out a
## free trickle, which the rule does not allow.
func _step_shield_regen(dt: float, combat: Dictionary) -> void:
	if shield_sag > 0.0:
		# An overload just took the generators offline. The energy the shields
		# sink draws in these seconds buys nothing and is not banked: handing
		# it back a moment later would make the overload free, which is the
		# opposite of a cost.
		shield_credit = 0.0
		return
	shield_credit += alloc_units("shields") * dt
	var price: float = maxf(0.001, float(combat["shield_energy_per_box"])
		* float(combat["shield_power_demand"]))
	while shield_credit >= price:
		var facing: int = _regen_facing()
		if facing < 0:
			# Nothing to buy. Credit is capped at one box so a long lull with
			# full shields cannot bank a free instant repair later.
			shield_credit = minf(shield_credit, price)
			return
		shields[facing] = minf(shield_max, shields[facing] + 1.0)
		shield_credit -= price


## Which shield the next box goes to: the one the engineer picked if it still
## needs boxes, otherwise the weakest that does. 3C7 is a choice of shield, and
## defaulting to the weakest is the choice a player would make anyway.
func _regen_facing() -> int:
	if shield_bias >= 0 and shield_bias < shields.size() \
			and shields[shield_bias] < shield_max:
		return shield_bias
	var worst: int = -1
	for i in range(shields.size()):
		if shields[i] >= shield_max:
			continue
		if worst < 0 or shields[i] < shields[worst]:
			worst = i
	return worst


## Work the head of the repair queue. One box at a time, priced per box, paid
## for out of the parts aboard (5G3, 5G4). A job whose parts are not aboard
## stalls in place rather than being dropped, because an earlier job finishing
## does not free parts but a restock would.
func _step_repair(dt: float, tuning: Dictionary) -> void:
	while not repair_queue.is_empty():
		var index: int = repair_queue[0]
		if index < 0 or index >= systems.size():
			repair_queue.pop_front()
			repair_progress = 0.0
			continue
		var sys: Dictionary = systems[index]
		if not RepairModel.repairable(sys, tuning):
			repair_queue.pop_front()
			repair_progress = 0.0
			continue
		var family: String = String(sys["family"])
		var price: int = RepairModel.parts_per_box(family, tuning)
		if parts < price:
			return
		repair_progress += dt * float(damage_control)
		var needed: float = RepairModel.seconds_per_box(family, tuning)
		if repair_progress < needed:
			return
		repair_progress -= needed
		parts -= price
		sys["boxes"] = mini(int(sys["boxes"]) + 1, int(sys["boxes_max"]))
		# The loop goes round so a queue can finish a job and start the next in
		# the same frame, which matters at large dt when a replay is scrubbed.


## Put a system in the repair queue. Refuses anything undamaged, anything
## already queued, and anything whose family repair does not cover.
func queue_repair(index: int, tuning: Dictionary) -> bool:
	if index < 0 or index >= systems.size():
		return false
	if repair_queue.has(index):
		return false
	if not RepairModel.repairable(systems[index], tuning):
		return false
	repair_queue.append(index)
	return true


## Take a system out of the queue. Dropping the head abandons the box being
## worked on, and the parts already spent on finished boxes stay spent.
func drop_repair(index: int) -> bool:
	var at: int = repair_queue.find(index)
	if at < 0:
		return false
	repair_queue.remove_at(at)
	if at == 0:
		repair_progress = 0.0
	return true


# ---- firing ------------------------------------------------------------------

## What an overloaded shot costs, for every weapon that can take one.
##
## Read from the catalog rather than passed in, which is a deliberate exception
## to this file's habit of taking tuning as an argument. fire_check runs from
## the HUD refresh and from the AI, neither of which holds tuning, and threading
## it through four signatures for one number would buy nothing. Catalog is a
## static cache with no scene tree behind it, so the sim still runs headless.
func _overload_tuning() -> Dictionary:
	return Catalog.tuning()["combat"]


## Whether this mount could be armed to overload at all: a property of what is
## fitted, not of what the ship can currently afford.
func can_overload(index: int) -> bool:
	if index < 0 or index >= weapons_rt.size():
		return false
	return WeaponModel.can_overload(weapons_rt[index]["weapon"])


func overloaded(index: int) -> bool:
	if index < 0 or index >= weapons_rt.size():
		return false
	return bool(weapons_rt[index].get("overload", false))


## Arm or disarm one mount. Returns false when nothing changed, so the battle
## does not write a no op into the log and a replay does not replay one.
func set_overload(index: int, on: bool) -> bool:
	if index < 0 or index >= weapons_rt.size():
		return false
	if on and not can_overload(index):
		return false
	if overloaded(index) == on:
		return false
	weapons_rt[index]["overload"] = on
	return true


## Why a weapon can or cannot fire right now. Reasons match the mockup chips.
func fire_check(index: int, target_pos: Vector2) -> Dictionary:
	var w: Dictionary = weapons_rt[index]
	if w["weapon"].is_empty():
		return { "ok": false, "reason": "empty" }
	if mount_disabled(index):
		return { "ok": false, "reason": "destroyed" }
	if float(w["charge"]) < 1.0:
		return { "ok": false, "reason": "charging" }
	var ovl: bool = overloaded(index)
	# Checked before the lock and the range, because it is the one reason a
	# captain can do something about without moving the ship.
	if ovl and battery < float(_overload_tuning()["overload_battery_cost"]):
		return { "ok": false, "reason": "battery" }
	if not can_see(target_pos):
		return { "ok": false, "reason": "no lock" }
	if apparent_range_to(target_pos) > WeaponModel.max_range(w["weapon"], ovl):
		return { "ok": false, "reason": "range" }
	var rel: float = Sectors.relative_bearing(Sectors.bearing_between(pos, target_pos), heading)
	if not fit.effective_field(w["mount"]).has(Sectors.sector_of_bearing(rel)):
		return { "ok": false, "reason": "no arc" }
	return { "ok": true, "reason": "bears" }


## Resolve one shot against a target. Returns the event for UI and logs.
func fire_at(index: int, target: ShipState) -> Dictionary:
	var w: Dictionary = weapons_rt[index]
	w["charge"] = 0.0
	# The reserve pays before the shot resolves, and the switch springs back:
	# an overload is one burst (docs/01 section 3), not a mode the mount stays
	# in. Leaving it armed would empty the battery again on the next reload
	# without the captain having asked twice.
	var ovl: bool = overloaded(index)
	if ovl:
		var combat: Dictionary = _overload_tuning()
		battery = maxf(0.0, battery - float(combat["overload_battery_cost"]))
		shield_sag = float(combat["overload_shield_sag_sec"])
		w["overload"] = false
	var distance: float = pos.distance_to(target.pos)
	# Range decides both whether the shot connects and what it scores, so a
	# weapon fired at its extreme edge is worth less than the same weapon
	# fired point blank (WeaponModel). Cloud between the two hulls counts as
	# extra range, which is the whole of the nebula's effect on gunnery.
	var damage: int = WeaponModel.roll_damage(
		w["weapon"], apparent_range_to(target.pos), rng, ovl)
	var arrive_bearing: float = Sectors.bearing_between(target.pos, pos)
	var log_lines: Array[String] = []
	# -1 means nothing was struck, so a miss cannot light a shield up.
	var facing: int = -1
	if damage <= 0:
		log_lines.append("%s misses at range %d" % [String(w["weapon"]["short"]), int(distance)])
	else:
		var result: Dictionary = target.apply_damage(arrive_bearing, float(damage))
		log_lines = result["log"]
		facing = int(result["facing"])
	if ovl:
		log_lines.insert(0, "%s OVERLOAD, shields off line" % [String(w["weapon"]["short"])])
	return {
		"type": "shot",
		"weapon": String(w["weapon"]["short"]),
		"damage": damage,
		"hit": damage > 0,
		"overload": ovl,
		"facing": facing,
		"range": distance,
		"from_pos": pos,
		"to_pos": target.pos,
		"log": log_lines,
	}


# ---- the damage model --------------------------------------------------------

## Incoming fire resolves against the facing it arrives from: shield absorbs,
## the remainder rolls into internals weighted by remaining boxes, so a fit
## determines its own vulnerability profile (docs/01 section 7).
##
## Returns the facing that took the hit alongside the log, because the view
## needs to know which shield to light up and working it out a second time
## from the bearing would be a second implementation of the rule that decides
## which facing is struck (CLAUDE.md 4.1). One answer, computed here, used by
## the damage model and the renderer alike.
func apply_damage(world_bearing: float, amount: float) -> Dictionary:
	var lines: Array[String] = []
	var rel: float = Sectors.relative_bearing(world_bearing, heading)
	var facing: int = Sectors.facing_of_relative_bearing(rel)
	var remaining: float = amount
	var absorbed: float = 0.0
	if shields[facing] > 0.0:
		absorbed = minf(shields[facing], remaining)
		shields[facing] -= absorbed
		remaining -= absorbed
		lines.append("Shield %s absorbs %d, at %d" % [Sectors.facing_mark(facing),
			int(absorbed), int(shields[facing])])
		if shields[facing] <= 0.0:
			lines.append("SHIELD %s DOWN, internals exposed" % [Sectors.facing_mark(facing)])
	else:
		lines.append("Facing %s already down" % [Sectors.facing_mark(facing)])
	if remaining > 0.0:
		lines.append_array(apply_internal(remaining, facing))
	return { "facing": facing, "absorbed": absorbed, "log": lines }


## Internal damage from a hit that arrived through one facing. The struck
## sector takes it first, the hull core takes what a stripped sector cannot,
## and only when both are gone does damage carry into the neighbouring sectors
## (docs/09, Federation Commander 3D and 5J). Public so the dry dock demo and
## the tests exercise exactly the rule a battle uses.
##
## Boxes are integers and bleed through is often fractional (a shield holding
## 0.3 leaves 7.7 of an 8 damage shot). Rounding the fraction UP would make
## the shield's remnant worth nothing, so the fractional part becomes a
## proportional chance of one extra box: on average the boxes destroyed equal
## the damage dealt, and an integer amount destroys exactly that many.
func apply_internal(amount: float, facing: int = 0) -> Array[String]:
	var lines: Array[String] = []
	var boxes_to_take: int = int(floorf(amount))
	if rng.randf() < amount - float(boxes_to_take):
		boxes_to_take += 1
	while boxes_to_take > 0:
		var source: int = _damage_source(facing)
		if source == CORE and boxes_in(CORE) <= 0:
			alive = false
			lines.append("SHIP DESTROYED, no systems remain")
			break
		var living: Array[Dictionary] = []
		var total: int = 0
		for sys in systems_in(source):
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
		var take: int = mini(int(pick["boxes"]), boxes_to_take)
		take = maxi(take, 1)
		pick["boxes"] = int(pick["boxes"]) - take
		boxes_to_take -= take
		if int(pick["boxes"]) <= 0:
			lines.append("%s DESTROYED" % [String(pick["code"])])
			if source == facing and boxes_in(facing) <= 0:
				lines.append("SECTOR %s STRIPPED, the hull core is exposed" % [Sectors.facing_mark(facing)])
		else:
			lines.append("%s takes %d, %d left" % [String(pick["code"]), take, int(pick["boxes"])])
	if total_boxes() <= 0:
		alive = false
	return lines


## Where the next box comes from: struck sector, then the core, then the
## nearest facing still holding anything. Federation Commander 3E only calls a
## ship lost when every non-shield box is gone, so damage keeps landing until
## that is true.
func _damage_source(facing: int) -> int:
	if boxes_in(facing) > 0:
		return facing
	if boxes_in(CORE) > 0:
		return CORE
	for step in range(1, 4):
		for candidate in [posmod(facing + step, Sectors.FACING_COUNT),
				posmod(facing - step, Sectors.FACING_COUNT)]:
			if boxes_in(int(candidate)) > 0:
				return int(candidate)
	return CORE


## Spend the battery to restore one facing (docs/01 section 4 reinforcement).
func reinforce(facing: int, tuning: Dictionary) -> bool:
	if battery < 1.0 or facing < 0 or facing >= shields.size():
		return false
	battery = 0.0
	shields[facing] = minf(shield_max, shields[facing] + float(tuning["combat"]["reinforce_amount"]))
	return true


## Point defense damage per second this ship can put on a point, from every
## undamaged weapon that has it and reaches. Free: it does not spend the
## weapon's capacitor, so a light beam defends while its crew reloads.
func point_defense_dps(at: Vector2) -> float:
	var total: float = 0.0
	for i in range(weapons_rt.size()):
		var w: Dictionary = weapons_rt[i]["weapon"]
		if w.is_empty() or not bool(w.get("point_defense", false)):
			continue
		if mount_disabled(i):
			continue
		if pos.distance_to(at) <= float(w["pd_range"]):
			total += float(w["pd_dps"])
	return total


## Move shield strength from one facing to a neighbour, which is Federation
## Commander 3C3: five boxes may be transferred to an adjacent shield, and only
## to replace what damage took, never to exceed the original strength.
func transfer_shield(from_facing: int, to_facing: int, tuning: Dictionary) -> bool:
	if from_facing == to_facing:
		return false
	var step: int = int(Sectors.turn_delta(
		float(from_facing) * 60.0, float(to_facing) * 60.0))
	if absi(step) != 60:
		return false
	var amount: float = float(tuning["combat"]["shield_transfer_amount"])
	var missing: float = shield_max - shields[to_facing]
	var moved: float = minf(minf(amount, shields[from_facing]), missing)
	if moved <= 0.0:
		return false
	shields[from_facing] -= moved
	shields[to_facing] += moved
	return true


func weakest_facing() -> int:
	var best: int = 0
	for i in range(shields.size()):
		if shields[i] < shields[best]:
			best = i
	return best
