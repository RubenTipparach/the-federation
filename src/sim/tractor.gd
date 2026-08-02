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

## Keep the current separation. Federation Commander 5D: "hold objects at a
## distance".
const MODE_HOLD: String = "hold"
## Close the range. 5D: "or pull them closer". There is no push mode, because
## the source does not describe one.
const MODE_REEL: String = "reel"

const SINK: String = "tractor"
const BOX: String = "TRAC"

var holder: ShipState
var held: ShipState
var mode: String = MODE_HOLD

## Seconds the prisoner has been out-bidding the holder without the beam having
## snapped yet. Reset the moment the holder is ahead again, so the struggle is
## reversible rather than settled on one tick.
var strain: float = 0.0


static func create(p_holder: ShipState, p_held: ShipState) -> Tractor:
	var t: Tractor = Tractor.new()
	t.holder = p_holder
	t.held = p_held
	return t


# ---- the bids ----------------------------------------------------------------

## What a ship is putting into its tractor sink right now. Reactor units, so a
## ship whose reactor has been shot up bids less without anyone rewriting the
## allocation.
static func bid_of(ship: ShipState) -> float:
	return ship.alloc_units(SINK)


func hold_bid() -> float:
	return Tractor.bid_of(holder)


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
	if hold_bid() < float(t["min_units"]):
		return "power cut"
	if break_bid() > hold_bid():
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

## Ask both ships to move toward their common momentum, weighted by tonnage, and
## in REEL to close as well. Written as a target velocity the ships ease toward
## rather than as a force, for the same reason gravity is (docs/13 section 4.1):
## it is stable at any timestep, and a replay depends on that.
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

	var reel_holder: Vector2 = Vector2.ZERO
	var reel_held: Vector2 = Vector2.ZERO
	if mode == MODE_REEL:
		var span: Vector2 = held.pos - holder.pos
		if span.length() > 0.001:
			# Each ship closes in inverse proportion to its own mass, so the
			# total closing rate is the reel speed and the light ship is the one
			# that actually travels.
			var toward: Vector2 = span.normalized()
			var rate: float = float(tuning["tractor"]["reel_speed"])
			reel_holder = toward * rate * m_held / total
			reel_held = -toward * rate * m_holder / total

	holder.tow_target = common + reel_holder - v_holder
	held.tow_target = common + reel_held - v_held
