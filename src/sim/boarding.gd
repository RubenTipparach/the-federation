class_name Boarding
extends RefCounted

## The fight for a deck: docs/01 section 8 made concrete. Marines are beamed
## through a downed shield onto the enemy hull, and while the deck is
## contested both sides trade volleys on a fixed interval until one side has
## nobody left standing. A crew that loses its own deck loses its ship.
##
## Every rule is a number in data/tuning.json's combat block, and every roll
## comes from the RandomNumberGenerator the battle owns and seeds, so a
## replay fights the same fight to the same corpse count (CLAUDE.md 5.2).
##
## No Node dependencies. Battle owns the clocks and the commands; this file
## holds the checks and the arithmetic, the way TractorLib does for the beam.


## Whether `from` can beam marines onto `to` right now, and if not, why, in
## the fire_check style every station shares: { "ok": bool, "reason": String }.
##
## The preconditions are the design's (docs/01 section 8): both hulls alive,
## the target inside transporter range, and the target's shield ON THE FACING
## TOWARD THE ATTACKER down. Plus the machinery: a recharged pad, and a living
## marine to put on it.
##
## `outbound` false is a recall: the same beam pointed home, so everything
## holds except the home deck check, because bringing the team back is exactly
## what an empty home deck wants to do.
static func beam_check(from: ShipState, to: ShipState,
		combat: Dictionary, outbound: bool = true) -> Dictionary:
	if not from.alive or not to.alive:
		return { "ok": false, "reason": "destroyed" }
	if from.pos.distance_to(to.pos) > float(combat["transporter_range"]):
		return { "ok": false, "reason": "range" }
	var facing: int = Sectors.facing_of_relative_bearing(Sectors.relative_bearing(
		Sectors.bearing_between(to.pos, from.pos), to.heading))
	if to.shields[facing] > 0.0:
		return { "ok": false, "reason": "shielded" }
	if from.pads_ready().is_empty():
		return { "ok": false, "reason": "cycling" }
	if outbound and ShipState.count_alive(
			from.marines, int(combat["hits_to_kill"])) <= 0:
		return { "ok": false, "reason": "no marines" }
	return { "ok": true, "reason": "ready" }


## Move up to `count` living marines from `from`'s deck to its away team,
## spending one recharged pad per marine. Returns how many actually went, so
## the caller can log the truth rather than the request.
static func beam(from: ShipState, count: int, combat: Dictionary) -> int:
	var limit: int = int(combat["hits_to_kill"])
	var pads: Array[int] = from.pads_ready()
	var going: Array[int] = []
	for i in range(from.marines.size()):
		if going.size() >= count or going.size() >= pads.size():
			break
		if from.marines[i] < limit:
			going.append(i)
	# Collected first, removed back to front, so the indices stay true while
	# the list shrinks under them.
	for k in range(going.size() - 1, -1, -1):
		from.away.append(from.marines[going[k]])
		from.marines.remove_at(going[k])
	for s in range(going.size()):
		from.pad_cycles[pads[s]] = float(combat["pad_cycle_sec"])
	return going.size()


## One volley on `deck`'s own floor: the away team aboard it and its home
## marines fire SIMULTANEOUSLY, each living marine spending shots_per_marine
## shots, each shot hitting on hit_chance, each hit landing on a random living
## enemy. Simultaneous means both sides' shots are counted before any hit
## lands, so two last marines can absolutely kill each other.
##
## Returns the narration numbers: shots and hits each way, and the dead.
static func volley(deck: ShipState, attackers: Array[int],
		rng: RandomNumberGenerator, combat: Dictionary) -> Dictionary:
	var limit: int = int(combat["hits_to_kill"])
	var per: int = int(combat["shots_per_marine"])
	var chance: float = float(combat["hit_chance"])

	var att_shots: int = ShipState.count_alive(attackers, limit) * per
	var def_shots: int = ShipState.count_alive(deck.marines, limit) * per
	var att_hits: int = 0
	var def_hits: int = 0
	for i in range(att_shots):
		if rng.randf() < chance:
			att_hits += 1
	for i in range(def_shots):
		if rng.randf() < chance:
			def_hits += 1

	var att_dead: int = _land(deck.marines, att_hits, rng, limit)
	var def_dead: int = _land(attackers, def_hits, rng, limit)
	return {
		"att_shots": att_shots, "att_hits": att_hits, "att_dead": att_dead,
		"def_shots": def_shots, "def_hits": def_hits, "def_dead": def_dead,
	}


## Deal `hits` hits to random living members of `squad`. Returns how many died
## of it. A hit with nobody left alive to take it is wasted, which is correct:
## you cannot shoot a man twice into a fourth wound.
static func _land(squad: Array[int], hits: int,
		rng: RandomNumberGenerator, limit: int) -> int:
	var dead: int = 0
	for h in range(hits):
		var living: Array[int] = []
		for i in range(squad.size()):
			if squad[i] < limit:
				living.append(i)
		if living.is_empty():
			break
		var target: int = living[rng.randi_range(0, living.size() - 1)]
		squad[target] += 1
		if squad[target] >= limit:
			dead += 1
	return dead
