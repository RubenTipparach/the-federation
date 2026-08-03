class_name Battle
extends RefCounted

## The authoritative combat resolution loop. Pure simulation: no nodes, no
## rendering, steps by dt and returns events for whatever front end is
## watching. The combat scene, the headless tests, and one day the dedicated
## server all drive battles through this one class (CLAUDE.md 4.1, 5.2).

var ships: Array[ShipState] = []
var time: float = 0.0
var over: bool = false
var winner: int = -1
var seekers: Array[Seeker] = []

## What is in the arena besides the ships. Always present: an "open" battle
## flies in an empty Terrain rather than in a null one, so nothing downstream
## needs a special case for a bare arena.
var terrain: Terrain = Terrain.new()

## Tractor beams currently up, at most one per holder. See Tractor and docs/13
## section 6.
var tractors: Array[Tractor] = []

## Seconds left before a pair may latch each other again after a beam snapped,
## keyed by the two ship indices. A pair, not a ship: breaking one grip should
## not stop a third party latching on.
var _relatch: Dictionary = {}

## Fixed step counter. Commands are stamped with it, never with wall clock
## time, because that is what makes a log replayable (see BattleLog).
var tick: int = 0

## The seed this battle was created from, so a recording can reproduce it.
var seed_value: int = 0

## Set to record this battle. Every command routed through apply_command is
## written down, so a recording cannot miss an input that changed the outcome.
var log: BattleLog = null
var _events: Array[Dictionary] = []
var _targets: Dictionary = {}


## Where the two sides start, in the fixed order [player, enemy]. Terrain
## placement keeps these clear and the map picker previews them, so they exist
## once here rather than being worked out again by whoever needs them
## (CLAUDE.md 4.1).
static func start_positions() -> Array[Vector2]:
	var sep: float = float(Catalog.tuning()["combat"]["start_separation"])
	return [Vector2(-sep * 0.5, sep * 0.35), Vector2(sep * 0.5, -sep * 0.35)]


## map_id names a recipe in data/maps.json. It defaults to the empty arena, and
## an "open" battle draws nothing at all from the rng for terrain, so every
## battle recorded before terrain existed still replays bit for bit.
static func create_duel(player_fit: ShipFit, enemy_hull_id: String, seed_value: int,
		map_id: String = "open") -> Battle:
	var b: Battle = Battle.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	b.seed_value = seed_value
	var starts: Array[Vector2] = Battle.start_positions()

	var player: ShipState = ShipState.create(player_fit, rng, false)
	player.pos = starts[0]
	player.heading = Sectors.bearing_between(player.pos, Vector2.ZERO)
	player.ordered_heading = player.heading

	var enemy: ShipState = ShipState.create(ShipFit.create_default(enemy_hull_id), rng, true)
	enemy.pos = starts[1]
	enemy.heading = Sectors.bearing_between(enemy.pos, Vector2.ZERO)
	enemy.ordered_heading = enemy.heading

	b.ships.append(player)
	b.ships.append(enemy)

	# Terrain is drawn last, from the same rng, so it is reproduced by the seed
	# along with everything else. Both starting positions are kept clear.
	b.terrain = Terrain.create(map_id, rng, [player.pos, enemy.pos])
	for s in b.ships:
		s.terrain = b.terrain
	return b


func player() -> ShipState:
	return ships[0]


func enemy() -> ShipState:
	return ships[1]


func foe_of(ship: ShipState) -> ShipState:
	return target_for(ship)


## Every hostile still flying, in a stable order so cycling targets is
## predictable. A duel has one, a squadron battle will have several.
func foes_of(ship: ShipState) -> Array[ShipState]:
	var out: Array[ShipState] = []
	for s in ships:
		if s != ship and s.alive:
			out.append(s)
	return out


## Who this ship is shooting at. Selection is remembered per attacker and
## falls back to the first living hostile, so the AI needs no target logic and
## the player's choice survives a step.
func target_for(ship: ShipState) -> ShipState:
	var chosen: ShipState = _targets.get(ship, null) as ShipState
	if chosen != null and chosen.alive:
		return chosen
	var living: Array[ShipState] = foes_of(ship)
	return living[0] if not living.is_empty() else (ships[1] if ship == ships[0] else ships[0])


func set_target(ship: ShipState, target: ShipState) -> void:
	_targets[ship] = target


## Advance the battle and return every event since the last step, including
## events appended between steps by player fire commands. The buffer is
## drained at the END, never cleared at the start: clearing first silently
## discarded player shots that arrived from UI signals between physics frames,
## so their beams never flashed while identical AI shots did.
func step(dt: float) -> Array[Dictionary]:
	if over:
		return _drain()
	var tuning: Dictionary = Catalog.tuning()

	CombatAi.act(enemy(), player(), self)
	# Tows are cleared and rewritten every step, so a beam that snapped this
	# frame stops pulling without anything having to remember it was there.
	for s in ships:
		s.tow_target = Vector2.ZERO
	_step_tractors(dt, tuning)
	for s in ships:
		s.step(dt, tuning)
	_step_seekers(dt, tuning)
	_step_terrain(dt)
	_step_contacts()

	_keep_in_arena(tuning)

	for i in range(ships.size()):
		if not ships[i].alive:
			over = true
			winner = 1 - i
			# Nothing steps again once the battle is over, so a beam left up
			# here would sit in the panel forever showing a contest that has
			# stopped being fought.
			tractors.clear()
			# Which hull came apart and where, so the view can put a wreck
			# there. The sim says what happened; how a wreck looks is not its
			# business, so nothing about the explosion is described here.
			_events.append({
				"type": "destroyed", "ship": i, "at": ships[i].pos,
				"log": ["%s BREAKING UP" % String(ships[i].fit.hull()["name"]).to_upper()],
			})
			_events.append({ "type": "end", "winner": winner })
			break
	time += dt
	tick += 1
	if over and log != null and log.end_tick < 0:
		log.close(self)
	return _drain()


## Weapons in flight: fly, then let point defense shoot at them, then land the
## ones that arrived. Point defense fires for free, without spending the
## defending weapon's capacitor, which is what makes a light beam worth its
## space (docs/01 section 5.2).
func _step_seekers(dt: float, tuning: Dictionary) -> void:
	var combat: Dictionary = tuning["combat"]
	var hit_radius: float = float(combat["seeker_hit_radius"])
	var lifetime: float = float(combat["seeker_lifetime"])
	var survivors: Array[Seeker] = []

	for seeker in seekers:
		if not seeker.alive():
			continue
		seeker.step(dt)

		# Everything hostile to the seeker with point defense in range shoots.
		for defender in ships:
			if defender == seeker.owner or not defender.alive:
				continue
			var dps: float = defender.point_defense_dps(seeker.pos)
			if dps <= 0.0:
				continue
			seeker.hp -= dps * dt
			if seeker.hp <= 0.0:
				_events.append({
					"type": "seeker_killed",
					"weapon": seeker.short,
					"at": seeker.pos,
					"log": ["%s shot down by point defense" % [seeker.short]],
				})
				break

		if seeker.hp <= 0.0:
			continue
		if seeker.age > lifetime:
			_events.append({ "type": "seeker_lost", "weapon": seeker.short,
				"at": seeker.pos, "log": ["%s ran out of fuel" % [seeker.short]] })
			continue
		if seeker.distance_to_target() <= hit_radius:
			var bearing: float = Sectors.bearing_between(seeker.target.pos, seeker.pos)
			var result: Dictionary = seeker.target.apply_damage(bearing, float(seeker.damage))
			var lines: Array[String] = result["log"]
			lines.insert(0, "%s impacts" % [seeker.short])
			_events.append({
				"type": "shot", "weapon": seeker.short, "damage": seeker.damage,
				"hit": true, "facing": int(result["facing"]),
				"target_player": seeker.target == player(),
				"range": 0.0, "from_pos": seeker.pos,
				"to_pos": seeker.target.pos, "log": lines,
			})
			continue
		survivors.append(seeker)

	seekers = survivors


## Work every beam that is up: resolve its contest, and let the survivors tow.
## A beam that snaps starts the pair's relatch cooldown, so a captain who has
## just wrenched free is not grabbed again on the next tick.
func _step_tractors(dt: float, tuning: Dictionary) -> void:
	for key in _relatch.keys():
		_relatch[key] = maxf(0.0, float(_relatch[key]) - dt)
	if tractors.is_empty():
		return
	var survivors: Array[Tractor] = []
	for beam in tractors:
		var snap: String = beam.step(dt, tuning)
		if snap.is_empty():
			beam.apply_tow(tuning)
			survivors.append(beam)
			continue
		_relatch[_pair_key(beam.holder, beam.held)] = float(
			tuning["tractor"]["relatch_cooldown"])
		_events.append({
			"type": "tractor", "state": "released", "reason": snap,
			"holder_player": beam.holder == player(),
			"log": ["Tractor lost, %s" % [snap]],
		})
	tractors = survivors


## Order a beam onto a target. Refused for the same reasons a shot is, plus a
## pair that is still on its relatch cooldown and a hull that is already holding
## something: one emitter, one grip.
func latch_tractor(attacker: ShipState, target: ShipState) -> bool:
	if over:
		return false
	var tuning: Dictionary = Catalog.tuning()
	if float(_relatch.get(_pair_key(attacker, target), 0.0)) > 0.0:
		return false
	for beam in tractors:
		if beam.holder == attacker or beam.held == attacker:
			return false
		if beam.holder == target and beam.held == attacker:
			return false
	if not bool(Tractor.latch_check(attacker, target, tuning)["ok"]):
		return false
	tractors.append(Tractor.create(attacker, target))
	_events.append({
		"type": "tractor", "state": "latched",
		"holder_player": attacker == player(),
		"log": ["Tractor locked on"],
	})
	return true


## Let go. A voluntary release carries no cooldown: it was the holder's choice.
func release_tractor(attacker: ShipState) -> bool:
	for i in range(tractors.size()):
		if tractors[i].holder != attacker:
			continue
		tractors.remove_at(i)
		_events.append({
			"type": "tractor", "state": "released", "reason": "released",
			"holder_player": attacker == player(),
			"log": ["Tractor released"],
		})
		return true
	return false


## The beam on this ship, whether it is holding or being held. Nothing keeps two
## copies of the answer: the panel, the AI, and the renderer all ask here.
func tractor_on(ship: ShipState) -> Tractor:
	for beam in tractors:
		if beam.holder == ship or beam.held == ship:
			return beam
	return null


func _pair_key(a: ShipState, b: ShipState) -> String:
	var i: int = ships.find(a)
	var j: int = ships.find(b)
	return "%d-%d" % [mini(i, j), maxi(i, j)]


## What the arena does to the ships in it. Gravity is deliberately not here: a
## pull is a drift the ship carries and integrates with its own motion
## (ShipState._step_drift), so there is one integration rather than two.
##
## Hazard damage resolves through apply_damage exactly as a shot does, so
## shields absorb it and internals take the remainder under the one damage rule
## this project has (CLAUDE.md 4.1).
func _step_terrain(dt: float) -> void:
	if terrain.features.is_empty():
		return
	for s in ships:
		if not s.alive:
			continue
		_apply_grind(s, dt)
		_apply_collision(s)


## Micrometeor dust wears at the facing pointing along the ship's motion, since
## that is the facing meeting it.
##
## Damage is banked until it is worth a whole point rather than applied every
## tick. A tick's worth is a fraction of a box, and apply_internal turns a
## fraction into a random chance of a box, so applying it sixty times a second
## would spend the battle's rng on dust and fill the comm log with lines saying
## nothing happened.
func _apply_grind(ship: ShipState, dt: float) -> void:
	var motion: Vector2 = ship.velocity()
	ship.grind_credit += terrain.grind_at(ship.pos, motion.length()) * dt
	if ship.grind_credit < 1.0:
		return
	var whole: float = floorf(ship.grind_credit)
	ship.grind_credit -= whole
	var ahead: Vector2 = motion if motion.length() > 0.001 else ship.heading_vector()
	var result: Dictionary = ship.apply_damage(
		Sectors.bearing_between(ship.pos, ship.pos + ahead), whole)
	var lines: Array[String] = result["log"]
	lines.insert(0, "Micrometeor wash, %d damage" % [int(whole)])
	_events.append({
		"type": "hazard", "hazard": Terrain.KIND_ASTEROID, "damage": whole,
		"facing": int(result["facing"]), "target_player": ship == player(),
		"at": ship.pos, "log": lines,
	})


## Touching a solid body costs a lump of damage and most of the ship's speed.
## There is no bounce and no contact physics: a collision is an event with a
## price (docs/13 section 3.2).
func _apply_collision(ship: ShipState) -> void:
	if ship.collision_grace > 0.0:
		return
	var hit: Dictionary = terrain.collision_at(ship.pos)
	if hit.is_empty():
		return
	_collide(ship, Vector2(hit["pos"]), String(hit["kind"]), float(hit["damage"]))


## Two hulls occupying the same space. The price is the same shape as running
## into a rock, and it is paid through the same code, because there is one
## collision rule and forking it would let a ship survive a battlecruiser it
## could not survive an asteroid (CLAUDE.md 4.1).
##
## What is different is that a rock does not care and another ship does, so the
## damage is shared out by tonnage: the light hull comes off worse, which is
## why ramming a frigate is a tactic and ramming a battlecruiser is suicide.
## Closing speed sets the severity, so drifting together at rest is a scrape
## and meeting head on at full throttle is not.
func _step_contacts() -> void:
	var combat: Dictionary = Catalog.tuning()["combat"]
	for i in range(ships.size()):
		for j in range(i + 1, ships.size()):
			var a: ShipState = ships[i]
			var b: ShipState = ships[j]
			if not a.alive or not b.alive:
				continue
			if not a.touching(b):
				continue
			# Both grace timers, or the pair would trade damage every tick for
			# as long as they stayed overlapped.
			if a.collision_grace > 0.0 or b.collision_grace > 0.0:
				continue
			var closing: float = maxf(0.0,
				(a.velocity() - b.velocity()).length())
			var severity: float = clampf(closing / float(combat["ram_speed_ref"]),
				float(combat["ram_speed_floor"]), 1.0)
			var base: float = float(combat["ram_damage"]) * severity
			var mass_a: float = maxf(1.0, float(a.fit.hull()["tonnage"]))
			var mass_b: float = maxf(1.0, float(b.fit.hull()["tonnage"]))
			var total: float = mass_a + mass_b
			# Each share is the OTHER hull's fraction of the pair, doubled so
			# that two equal ships take ram_damage each rather than half of it.
			# The shares sum to 2, so neither can ever exceed twice the base.
			var pos_a: Vector2 = a.pos
			_collide(a, b.pos, "ship", base * 2.0 * mass_b / total)
			_collide(b, pos_a, "ship", base * 2.0 * mass_a / total)


## Pay for one collision: the grace, the speed lost, the damage from the
## bearing it arrived on, and the line the comm log prints.
func _collide(ship: ShipState, with_pos: Vector2, kind: String, amount: float) -> void:
	var terrain_tuning: Dictionary = Catalog.tuning()["terrain"]
	ship.collision_grace = float(terrain_tuning["collision_cooldown"])
	ship.speed *= float(terrain_tuning["collision_speed_frac"])
	var result: Dictionary = ship.apply_damage(
		Sectors.bearing_between(ship.pos, with_pos), amount)
	var lines: Array[String] = result["log"]
	lines.insert(0, "COLLISION, %s, %d damage" % [kind, int(amount)])
	_events.append({
		"type": "hazard", "hazard": kind, "damage": amount,
		"facing": int(result["facing"]), "target_player": ship == player(),
		"at": ship.pos, "log": lines,
	})


func _drain() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events
	_events = []
	return out


## The one door into a battle. Every order, from a button, a stick, the AI, or
## a replay, arrives here, which is why a log written from this point is
## complete by construction (CLAUDE.md 4.1).
##
## record is false when a replay is feeding commands back in, so replaying a
## log does not append to it.
func apply_command(actor: int, kind: String, args: Array, record: bool = true) -> bool:
	if actor < 0 or actor >= ships.size():
		return false
	var ship: ShipState = ships[actor]
	var ok: bool = false
	match kind:
		"order":
			ship.set_order(float(args[0]), float(args[1]))
			ok = true
		"fire":
			ok = try_fire(ship, int(args[0]))
		"fire_family":
			ok = fire_family(ship, String(args[0])) > 0
		"reinforce":
			ok = ship.reinforce(int(args[0]), Catalog.tuning())
		"shield_bias":
			ship.shield_bias = int(args[0])
			ok = true
		"overload":
			ok = ship.set_overload(int(args[0]), bool(args[1]))
		"repair_queue":
			ok = ship.queue_repair(int(args[0]), Catalog.tuning())
		"repair_drop":
			ok = ship.drop_repair(int(args[0]))
		"transfer_shield":
			ok = ship.transfer_shield(int(args[0]), int(args[1]), Catalog.tuning())
		"power":
			ship.set_alloc_units(String(args[0]), float(args[1]))
			ok = true
		"target":
			var index: int = int(args[0])
			if index >= 0 and index < ships.size():
				set_target(ship, ships[index])
				ok = true
		"tractor_latch":
			var on: int = int(args[0])
			if on >= 0 and on < ships.size():
				ok = latch_tractor(ship, ships[on])
		"tractor_release":
			ok = release_tractor(ship)
		"tractor_mode":
			var beam: Tractor = tractor_on(ship)
			# Only the holder chooses. The prisoner does not get to decide whether
			# it is being reeled in.
			if beam != null and beam.holder == ship and beam.mode != String(args[0]):
				beam.mode = String(args[0])
				ok = true
	# Only what actually happened is written down. A fire order that found no
	# weapon bearing, or a transfer the shields refused, changed nothing, and
	# recording it would make a replay differ from the battle it came from by
	# replaying orders that were never carried out.
	if ok and record and log != null:
		log.record(tick, actor, kind, args)
	return ok


## Fire one weapon if its check passes. Both the player UI and the AI route
## through here so firing rules exist exactly once.
func try_fire(attacker: ShipState, weapon_index: int) -> bool:
	if over:
		return false
	var target: ShipState = target_for(attacker)
	var check: Dictionary = attacker.fire_check(weapon_index, target.pos)
	if not bool(check["ok"]):
		return false
	var weapon: Dictionary = attacker.weapons_rt[weapon_index]["weapon"]
	if bool(weapon.get("seeking", false)):
		attacker.weapons_rt[weapon_index]["charge"] = 0.0
		seekers.append(Seeker.launch(attacker, target, weapon))
		_events.append({
			"type": "launch", "weapon": String(weapon["short"]),
			"from_pos": attacker.pos, "to_pos": target.pos,
			"log": ["%s launched" % [String(weapon["short"])]],
		})
		return true
	# fire_at knows what it hit but not whose ship it is; only the battle holds
	# both sides, so the side is stamped here rather than threaded through the
	# ship. The view uses it to pick which rig lights up.
	var shot: Dictionary = attacker.fire_at(weapon_index, target)
	shot["target_player"] = target == player()
	_events.append(shot)
	return true


## Fire every ready weapon of one family that bears: the "fire beams" button.
func fire_family(attacker: ShipState, family: String) -> int:
	var fired: int = 0
	for i in range(attacker.weapons_rt.size()):
		var w: Dictionary = attacker.weapons_rt[i]["weapon"]
		if w.is_empty():
			continue
		var fam: String = String(w["family"])
		var match_family: bool = fam == family or (family == "beam" and fam == "special")
		if match_family and try_fire(attacker, i):
			fired += 1
	return fired


func _keep_in_arena(tuning: Dictionary) -> void:
	var half: float = float(tuning["combat"]["arena_half_extent"])
	for s in ships:
		s.pos.x = clampf(s.pos.x, -half, half)
		s.pos.y = clampf(s.pos.y, -half, half)
