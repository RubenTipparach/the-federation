class_name Tractor
extends RefCounted

## One tractor beam, and the contest over it (docs/13 section 6).
##
## The free Federation Commander rulebook does not print its tractor rules and
## says so; docs/09 section 6 records exactly what it does and does not contain.
## What we take from it: a tractor holds at a distance or pulls closer and
## cannot tear a ship apart (5D), and it is dead when the control boxes are
## (5A2c). The contest below is ours, shaped by the index entry named
## "Tractor Auctions".
##
## The bid is whatever the holder's tractor power sink is carrying. There is no
## separate currency, which is what makes this a real cost: every unit in the
## tractor sink is a unit not charging a capacitor.
##
## Pure simulation. This class exists once and both the battle and any fitting
## or panel projection read it (CLAUDE.md 4.1, 5.2).

const SINK: String = "tractor"
const BOX: String = "TRAC"

var holder: ShipState
var held: ShipState

## THE TOW PLAN: where the holder is telling the prisoner to sit, as a bearing
## relative to the holder's own nose and a standoff in whole steps out of
## standoff_steps. Federation Commander 5D's two options, "hold objects at a
## distance" and "pull them closer", are both this one number: holding is
## leaving the standoff where it is and reeling in is walking it down. One
## mechanism rather than a mode beside a distance (CLAUDE.md 4.1).
##
## Relative rather than absolute, because the plan is a station on the ship
## that owns the beam: turning your hull swings the prize around with you,
## which is what makes steering a prisoner into an asteroid a piloting problem.
var bearing: float = 0.0
var standoff: int = 0

## Seconds the prisoner has been out-bidding the holder without the beam having
## snapped yet. Reset the moment the holder is ahead again, so the struggle is
## reversible rather than settled on one tick.
var strain: float = 0.0


## A fresh beam takes the prisoner where it found her: the bearing she is
## already on and the nearest step to the range she is already at. A latch that
## snapped the prize to a default station would be a shove nobody ordered.
static func create(p_holder: ShipState, p_held: ShipState,
		tuning: Dictionary) -> Tractor:
	var t: Tractor = Tractor.new()
	t.holder = p_holder
	t.held = p_held
	t.bearing = Sectors.relative_bearing(
		Sectors.bearing_between(p_holder.pos, p_held.pos), p_holder.heading)
	t.standoff = Tractor.step_for_range(
		p_holder.pos.distance_to(p_held.pos), tuning)
	return t


# ---- the tow plan ------------------------------------------------------------

## How many steps the standoff is cut into, and which one a fresh plan sits on.
static func steps(tuning: Dictionary) -> int:
	return maxi(1, int(tuning["tractor"]["standoff_steps"]))


## The commanded standoff as a fraction of tractor range. Never zero: a step of
## one still leaves the prize off the hull, because a beam that could stack two
## ships in the same water would be a collision generator rather than a tow.
static func frac_for_step(level: int, tuning: Dictionary) -> float:
	var n: int = Tractor.steps(tuning)
	return clampf(float(clampi(level, 1, n)) / float(n),
		float(tuning["tractor"]["standoff_min_frac"]), 1.0)


## Which step a real separation falls on, for a beam adopting what it found.
static func step_for_range(distance: float, tuning: Dictionary) -> int:
	var n: int = Tractor.steps(tuning)
	var reach: float = maxf(0.001, float(tuning["tractor"]["range"]))
	return clampi(int(roundf(distance / reach * float(n))), 1, n)


func standoff_frac(tuning: Dictionary) -> float:
	return Tractor.frac_for_step(standoff, tuning)


## How far out the prisoner is being told to ride, in world units.
##
## Floored at the two hulls' own contact distance plus a clearance, because a
## step is a fraction of RANGE and range knows nothing about tonnage: the
## innermost step of a battlecruiser's beam is well inside her own collision
## circle, so a captain who walked the standoff to the bottom would grind the
## prize to scrap against the hull without ever ordering it. Ramming a held
## ship into something is meant to be steering, not the default of the last
## box on the strip.
func standoff_range(tuning: Dictionary) -> float:
	var want: float = standoff_frac(tuning) * float(tuning["tractor"]["range"])
	return maxf(want, holder.contact_distance(held)
		* float(tuning["tractor"]["station_clearance"]))


## THE FALLOFF: a tractor field is stiff against a hull held close and soft
## against one held at arm's length, so what the emitter is worth is a
## multiplier on the standoff. Linear between the two ends, which puts the
## middle step at exactly one: the default plan is the neutral reading, and
## every other step is legible as better or worse than it at a glance.
##
## This is the whole trade the plan exists for. Reach out to the edge of range
## to catch something running and you hold it with a fraction of your grip;
## walk the standoff in and the same reactor units hold far harder.
func grip_multiplier(tuning: Dictionary) -> float:
	var t: Dictionary = tuning["tractor"]
	return lerpf(float(t["grip_near"]), float(t["grip_far"]),
		standoff_frac(tuning))


## Where the plan says the prisoner belongs, in world coordinates. The bearing
## is relative to the holder's nose, so this point swings as the holder turns.
func station_point(tuning: Dictionary) -> Vector2:
	var world: float = Sectors.wrap_deg(holder.heading + bearing)
	var out: Vector2 = Vector2(sin(deg_to_rad(world)), cos(deg_to_rad(world)))
	return holder.pos + out * standoff_range(tuning)


# ---- the bids ----------------------------------------------------------------

## What a ship is putting into its tractor sink right now. Reactor units, so a
## ship whose reactor has been shot up bids less without anyone rewriting the
## allocation.
static func bid_of(ship: ShipState) -> float:
	return ship.alloc_units(SINK)


## The grip the holder actually brings: units spent, times what the standoff
## does to them. Every reader of the contest goes through here, so the panel's
## projection and the battle's arithmetic cannot disagree (CLAUDE.md 4.1).
func hold_bid(tuning: Dictionary) -> float:
	return Tractor.bid_of(holder) * grip_multiplier(tuning)


## What the prisoner is shoving back with, weighted by the tonnage ratio. This
## one line is the whole design: a frigate may latch a battlecruiser, and the
## battlecruiser breaks it with a fraction of the power the frigate is spending,
## because the battlecruiser is three times the ship.
##
## Breaking needs power but not an emitter. Holding a ship needs a tractor;
## shoving against one that is already on you is done with the engines and the
## structure, so a hull carrying no TRAC box is not helpless.
func break_bid() -> float:
	return Tractor.bid_of(held) * Tractor.tonnage(held) / Tractor.tonnage(holder)


static func tonnage(ship: ShipState) -> float:
	return maxf(1.0, float(ship.fit.hull()["tonnage"]))


## True when this hull still has a working tractor emitter. A destroyed TRAC box
## is a destroyed tractor, which is 5A2c reduced to the one box that matters.
static func emitter_ready(ship: ShipState) -> bool:
	return ship.alive and ship.system_boxes(BOX) > 0


## Why a latch can or cannot be made right now. Shaped like ShipState.fire_check
## so a panel can show the reason the same way a weapon row does.
static func latch_check(attacker: ShipState, target: ShipState,
		tuning: Dictionary) -> Dictionary:
	var t: Dictionary = tuning["tractor"]
	if not Tractor.emitter_ready(attacker):
		return { "ok": false, "reason": "destroyed" }
	if target == null or not target.alive or target == attacker:
		return { "ok": false, "reason": "empty" }
	if attacker.pos.distance_to(target.pos) > float(t["range"]):
		return { "ok": false, "reason": "range" }
	if Tractor.bid_of(attacker) < float(t["min_units"]):
		return { "ok": false, "reason": "no power" }
	return { "ok": true, "reason": "ready" }


# ---- the contest -------------------------------------------------------------

## Advance the struggle. Returns "" while the beam holds, or the reason it
## snapped. Both sides pay for every second of this either way, which is what
## makes it an auction rather than a comparison of two numbers.
func step(dt: float, tuning: Dictionary) -> String:
	var t: Dictionary = tuning["tractor"]
	if not holder.alive or not held.alive:
		return "lost"
	if not Tractor.emitter_ready(holder):
		return "emitter destroyed"
	if holder.pos.distance_to(held.pos) > float(t["range"]):
		return "out of range"
	if Tractor.bid_of(holder) < float(t["min_units"]):
		return "power cut"
	if break_bid() > hold_bid(tuning):
		strain += dt
		if strain >= float(t["break_seconds"]):
			return "broken free"
	else:
		strain = 0.0
	return ""


## How close the prisoner is to breaking loose, from 0 to 1. The panel shows
## this so a captain can see whether to spend more or let go.
func strain_frac(tuning: Dictionary) -> float:
	return clampf(strain / maxf(0.001, float(tuning["tractor"]["break_seconds"])), 0.0, 1.0)


# ---- what a beam does to the two ships ---------------------------------------

## Ask both ships to move toward their common momentum, weighted by tonnage,
## and to work the prisoner toward her commanded station on top of that.
## Written as a target velocity the ships ease toward rather than as a force,
## for the same reason gravity is (docs/13 section 4.1): it is stable at any
## timestep, and a replay depends on that.
##
## The station is a point, so one piece of arithmetic does what hold and reel
## used to do separately. A plan already satisfied has no error left and the
## beam simply carries her along; a plan pointing somewhere else drags her
## there, and whether that reads as reeling in or as swinging her around the
## bow is the captain's business rather than a mode.
##
## Attitude is deliberately untouched. A held ship can still come about and
## bring its guns to bear, because taking away a ship's arcs takes away the
## game, and 5D says the beam holds position rather than attitude.
func apply_tow(tuning: Dictionary) -> void:
	var m_holder: float = Tractor.tonnage(holder)
	var m_held: float = Tractor.tonnage(held)
	var total: float = m_holder + m_held
	var v_holder: Vector2 = holder.engine_velocity()
	var v_held: Vector2 = held.engine_velocity()
	var common: Vector2 = (v_holder * m_holder + v_held * m_held) / total

	var work_holder: Vector2 = Vector2.ZERO
	var work_held: Vector2 = Vector2.ZERO
	var err: Vector2 = station_point(tuning) - held.pos
	if err.length() > 0.001:
		# The closing speed eases off as the prize nears her station, so she
		# settles onto it instead of sailing through and coming back. Capped by
		# reel_speed, which is what the beam can do at its best.
		var t: Dictionary = tuning["tractor"]
		var speed: float = minf(err.length() * float(t["station_ease"]),
			float(t["reel_speed"]))
		# Each ship moves in inverse proportion to its own mass, so the pair
		# closes at that speed and the light ship is the one that travels. A
		# frigate that latches a battlecruiser gets dragged to the cruiser.
		var toward: Vector2 = err.normalized()
		work_held = toward * speed * m_holder / total
		work_holder = -toward * speed * m_held / total

	holder.tow_target = common + work_holder - v_holder
	held.tow_target = common + work_held - v_held
