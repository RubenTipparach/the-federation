class_name CombatAi
extends RefCounted

## The predefined opponent's captain (skirmish requirement: custom ships fight
## AI controlled ships). Deliberately simple and readable: bring the arcs to
## bear, hold preferred range, rotate a collapsing facing away, fire whatever
## bears. All thresholds come from data/tuning.json.


static func act(me: ShipState, foe: ShipState, battle) -> void:
	if not me.alive or not foe.alive:
		me.set_order(me.heading, 0.0)
		return
	var tuning: Dictionary = Catalog.tuning()["ai"]
	var to_foe: float = Sectors.bearing_between(me.pos, foe.pos)
	var dist: float = me.pos.distance_to(foe.pos)

	var desired: float = to_foe

	# If the facing currently toward the enemy is nearly gone, present the
	# next facing instead: the shield rotation defenders are supposed to do.
	var rel: float = Sectors.relative_bearing(to_foe, me.heading)
	var exposed: int = Sectors.facing_of_relative_bearing(rel)
	if me.shields[exposed] / me.shield_max < float(tuning["weak_facing_frac"]):
		var offset: float = float(tuning["presenting_offset_deg"])
		var left: int = posmod(exposed - 1, Sectors.FACING_COUNT)
		var right: int = posmod(exposed + 1, Sectors.FACING_COUNT)
		# Turning the heading CLOCKWISE (+offset) moves the foe's relative
		# bearing counter clockwise, which presents the LEFT neighbor facing.
		# So a positive offset is the move that shows the left shield. This
		# sign was inverted once and the review caught the AI presenting its
		# weaker side; the test suite now pins the direction.
		desired = to_foe + (offset if me.shields[left] >= me.shields[right] else -offset)

	# Hold the range the guns want.
	var best_range: float = float(tuning["fallback_best_range"])
	for i in range(me.weapons_rt.size()):
		var w: Dictionary = me.weapons_rt[i]["weapon"]
		if not w.is_empty() and not me.mount_disabled(i):
			best_range = maxf(best_range, WeaponModel.max_range(w))
	var throttle: float = float(tuning["hold_throttle"])
	if dist > best_range * float(tuning["preferred_range_frac"]):
		throttle = float(tuning["close_throttle"])
	elif dist < best_range * float(tuning["back_off_range_frac"]):
		throttle = float(tuning["back_off_throttle"])

	# Keeping off overrides everything above. A shield the AI would like to
	# present, or a range its guns would like to hold, is not worth trading a
	# hull for, and two ships sitting on top of each other is the one shape
	# this fight should never take.
	var keep_out: float = me.contact_distance(foe) * float(tuning["standoff_radii"])
	if dist < keep_out:
		# Inside the standoff: run, and stop pretending to be doing anything
		# else. Straight away from the foe is the heading that opens the range
		# fastest whatever the turn rate.
		desired = Sectors.bearing_between(foe.pos, me.pos)
		throttle = 1.0
	elif _closing_to_contact(me, foe, tuning):
		# Still outside it, but on a course that ends in contact. Sheer 90
		# degrees rather than turning about: it opens the range, it is quick
		# enough to execute at any turn rate, and it leaves the foe on a beam
		# facing where the arcs still bear.
		desired = _sheer(me.heading, to_foe)

	me.set_order(desired, throttle)
	_work_tractor(me, battle)

	# Fire everything that bears. The battle applies the shots.
	for i in range(me.weapons_rt.size()):
		battle.try_fire(me, i)


## Would the way these two are moving right now put them in contact within the
## next few seconds?
##
## The closest approach of two bodies on straight courses is a closed form, so
## this is arithmetic rather than a simulation of the future: project the
## relative position onto the relative velocity to find the time of closest
## approach, and measure the gap at that time. A negative time means they are
## already separating, and a time past the horizon is too far off to steer for.
##
## The distance it is measured against is ShipState.contact_distance, the same
## one Battle._step_contacts collides on, so the AI cannot be avoiding a
## collision the simulation would not have had, or missing one it would.
static func _closing_to_contact(me: ShipState, foe: ShipState, tuning: Dictionary) -> bool:
	var rel_pos: Vector2 = foe.pos - me.pos
	var rel_vel: Vector2 = foe.velocity() - me.velocity()
	var speed_sq: float = rel_vel.length_squared()
	if speed_sq < 0.0001:
		return false
	var at: float = -rel_pos.dot(rel_vel) / speed_sq
	if at <= 0.0 or at > float(tuning["avoid_lookahead"]):
		return false
	var gap: float = (rel_pos + rel_vel * at).length()
	return gap < me.contact_distance(foe) * float(tuning["avoid_margin"])


## A heading 90 degrees off the bearing to the foe, on whichever side is the
## shorter turn from where the ship is already pointing.
static func _sheer(heading: float, to_foe: float) -> float:
	var left: float = Sectors.wrap_deg(to_foe - 90.0)
	var right: float = Sectors.wrap_deg(to_foe + 90.0)
	if absf(Sectors.turn_delta(heading, left)) <= absf(Sectors.turn_delta(heading, right)):
		return left
	return right


## The opponent's tractor doctrine, which is one sentence long: if something has
## hold of you, shove; otherwise spend nothing on it.
##
## The AI does not latch. Deciding WHEN to grab an enemy is a real tactical
## question and it does not have an answer worth shipping yet, so it is left
## undone rather than faked. Breaking free is not that question: a captain under
## tow always wants out, so the only decision is how much to spend, and pouring
## in enough to beat the grip is the right answer every time.
##
## Without this the player would win every tug of war unopposed, which would
## make the whole auction look like a button rather than a contest.
static func _work_tractor(me: ShipState, battle) -> void:
	var beam = battle.tractor_on(me)
	var tuning: Dictionary = Catalog.tuning()
	if beam == null or beam.holder == me:
		if me.alloc_units(Tractor.SINK) > 0.0:
			me.set_alloc_units(Tractor.SINK, 0.0)
		return
	# Bid enough to out-shove the grip, plus a margin, and never more than the
	# reactor has. The tonnage weighting is the simulation's, so the shove asked
	# for here is divided back out through it.
	var ratio: float = Tractor.tonnage(beam.held) / Tractor.tonnage(beam.holder)
	var wanted: float = beam.hold_bid(tuning) / maxf(0.01, ratio) \
		+ float(tuning["ai"]["tractor_break_margin"])
	me.set_alloc_units(Tractor.SINK, minf(wanted, me.power_output()))
