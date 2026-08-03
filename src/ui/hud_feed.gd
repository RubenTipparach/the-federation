class_name HudFeed
extends RefCounted

## What changed since the last tick, so a panel that did not change is not
## repainted at all.
##
## Measured on the phone: dropping the repaint rate from 60 to 5 took 35
## milliseconds off the frame with the draw count completely unchanged. So the
## cost is not rasterising the panels, it is the work a repaint SETS OFF: every
## label whose text is reassigned re-shapes its text and rebuilds its draw
## commands, whether or not the string is different. Godot compares the string
## and skips the work when it matches, which is why the guard in paint.gd was
## worth so much, but most of these strings are rebuilt from numbers that did
## move, one digit in a corner, and the whole panel pays.
##
## Lowering the rate fixed that by being wrong more slowly. This fixes it by
## not repainting what did not change, which is the same saving without the
## readouts going stale.
##
## THE SIGNATURES ARE OF WHAT IS DISPLAYED, NOT OF WHAT IS TRUE.
##
## This is the whole trick and it is easy to get wrong. The range to the target
## changes every single tick, so a signature on the raw float is dirty every
## tick and saves nothing. The panel prints it to one decimal, so the signature
## is the range times ten as an integer, and the panel repaints when the digit
## a player can actually see changes. Same for speed, for charge, and for every
## other reading that is formatted before it is shown.
##
## Over-reporting a change is safe and under-reporting is a bug, so where a
## facet is uncertain it is drawn wider rather than narrower: the station
## panels sign on everything their ten possible stations could read, because
## one panel serves all of them and the open one is not known here.

## Every facet a panel may depend on. Named here rather than as loose strings at
## the call sites, so a typo is a missing constant instead of a panel that
## quietly never repaints again.
const HELM: String = "helm"
const POWER: String = "power"
const SYSTEMS: String = "systems"
const QUEUE: String = "queue"
const SHIELDS: String = "shields"
const TARGET: String = "target"
const FOE: String = "foe"
const WEAPONS: String = "weapons"
const LOG: String = "log"

var _last: Dictionary = {}
var _moved: Dictionary = {}
var _force: bool = true


## Repaint everything on the next sample. For the moments where the panels are
## drawing a different ship than they were: a battle starting, a replay seeking,
## a station tab opening, or a debug switch putting a panel back on screen.
func force() -> void:
	_force = true


## Read every facet once and record which of them moved. One pass, called once
## per tick before any panel asks anything.
## `lost_tenths` is how long the lock has been broken, in tenths of a second,
## and it is a parameter rather than something derived here for a reason worth
## recording: the target panel prints that age to one decimal while the lock is
## out, so it genuinely has to repaint every tenth of a second, and a signature
## that did not include it would freeze the readout at the moment contact was
## lost. It reads zero while the contact is held.
func sample(me: ShipState, foe: ShipState, seen: bool, target_range: float,
		target_bearing: float, lost_tenths: int, log_lines: int) -> void:
	var now: Dictionary = {}

	# Rounded to the digit the panel prints, so a reading that is changing in
	# the fourth decimal does not count as news.
	now[HELM] = [me.total_boxes(), int(me.speed * 10.0), int(me.max_speed() * 10.0),
		int(me.heading), int(me.ordered_heading),
		int(me.ordered_throttle * 1000.0)]

	var power: Array = [int(me.power_output() * 10.0)]
	for sink in ["weapons", "shields", "engines", "systems", "reserve"]:
		power.append(int(roundf(me.alloc_units(sink))))
	now[POWER] = power

	# One entry per system rather than a total, because a box moving from one
	# system to another is a change the damage report has to show and a sum
	# would hide.
	var systems: Array = []
	for sys in me.systems:
		systems.append(int(sys["boxes"]))
	now[SYSTEMS] = systems

	now[QUEUE] = [me.repair_queue.duplicate(), me.parts, me.damage_control]

	var shields: Array = [int(me.battery * 100.0), me.shield_bias]
	for s in me.shields:
		shields.append(int(s))
	now[SHIELDS] = shields

	now[TARGET] = [seen, int(target_range * 10.0), int(target_bearing),
		foe.total_boxes(), foe.alive, lost_tenths]

	var foe_sig: Array = [foe.alive]
	for s in foe.shields:
		foe_sig.append(int(s))
	for sys in foe.systems:
		foe_sig.append(int(sys["boxes"]))
	now[FOE] = foe_sig

	# Charge to the percent the row prints. The firing REASON is not sampled
	# here on purpose: working it out means a fire check per mount, which is the
	# most expensive thing the interface asks the simulation for. Every input a
	# reason depends on (arc, lock, range, whether the mount is alive) is
	# already covered by the target and systems facets, so the weapons facet
	# borrows them rather than recomputing.
	var weapons: Array = [now[TARGET], systems]
	for w in me.weapons_rt:
		weapons.append(int(float(w["charge"]) * 100.0))
		# Arming is a click rather than a consequence of the sim, so it moves on
		# ticks where nothing else does. Sampled here or the row would keep
		# saying the mount is unarmed until something unrelated changed.
		weapons.append(bool(w.get("overload", false)))
	now[WEAPONS] = weapons

	now[LOG] = log_lines

	_moved = {}
	for facet in now:
		_moved[facet] = _force or not _last.has(facet) or _last[facet] != now[facet]
	_last = now
	_force = false


## Did any of these facets move since the last sample? Variadic by array rather
## than by one call per facet, because every caller depends on more than one and
## an "or" chain at eleven call sites is eleven chances to forget the second.
func moved(facets: Array) -> bool:
	for facet in facets:
		if bool(_moved.get(facet, true)):
			return true
	return false


## How many facets moved this tick. For the debug overlay, which is the only
## thing that should care: a screen where this is 9 every tick has a signature
## that is too wide somewhere, and that is worth being able to see.
func moved_count() -> int:
	var n: int = 0
	for facet in _moved:
		if bool(_moved[facet]):
			n += 1
	return n


func facet_count() -> int:
	return _moved.size()
