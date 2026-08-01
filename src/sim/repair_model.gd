class_name RepairModel
extends RefCounted

## What it costs to put a box back. The one implementation, used by the sim
## while a battle runs and by the tactical view to price a job before the
## player commits to it (CLAUDE.md 4.1). Two copies of this would let the
## panel promise a repair the ship cannot actually afford.
##
## Federation Commander 5G3 prices a repair by what kind of box it is, and
## 5G4 adds three constraints we keep: the cost is per box and not per system,
## one box has to be finished before work moves elsewhere, and shields are not
## repaired this way at all. Where we differ is the currency. Their repair
## points regenerate every turn forever, because a scenario ends. Ours is a
## ship that flies out and comes home, so the income becomes a stock of spare
## parts that empties and has to be restocked at a base. See
## docs/09-reference-federation-commander.md section 5.

## Families a repair party can work on. Shields are absent on purpose: they
## are bought with energy instead (ShipState._step_shield_regen).
const REPAIRABLE: PackedStringArray = ["weapon", "power", "control", "hull"]


static func _table(tuning: Dictionary, key: String) -> Dictionary:
	return tuning["repair"][key]


## Parts to restore one box of this family. Unknown families fall back to the
## cheapest rate rather than to free, so a new family added to the ship data
## still costs something before anyone remembers to price it.
static func parts_per_box(family: String, tuning: Dictionary) -> int:
	return int(_table(tuning, "parts_per_box").get(family, 1))


static func seconds_per_box(family: String, tuning: Dictionary) -> float:
	return float(_table(tuning, "seconds_per_box").get(family, 3.0))


## A system is worth queueing when it has lost boxes and its family can be
## worked on at all.
static func repairable(system: Dictionary, tuning: Dictionary) -> bool:
	if int(system["boxes"]) >= int(system["boxes_max"]):
		return false
	return REPAIRABLE.has(String(system["family"]))


static func missing_boxes(system: Dictionary) -> int:
	return maxi(0, int(system["boxes_max"]) - int(system["boxes"]))


## Parts to take this system all the way back to full. This is what the queue
## shows against a job, and it is per box: a five box warp core costs five
## times a single box, never once (5G4).
static func job_cost(system: Dictionary, tuning: Dictionary) -> int:
	return missing_boxes(system) * parts_per_box(String(system["family"]), tuning)


## Parts every job in a queue would take together, so a panel can say plainly
## when more has been ordered than the hold can pay for.
static func queue_cost(systems: Array[Dictionary], queue: Array[int],
		tuning: Dictionary) -> int:
	var total: int = 0
	for index in queue:
		if index >= 0 and index < systems.size():
			total += job_cost(systems[index], tuning)
	return total
