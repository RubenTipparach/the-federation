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
## Chunks of any ship that has come apart, still flying. In the sim rather
## than the view because they deal collision damage (CLAUDE.md 5.2): a piece
## of hull is a hazard to whoever is standing next to the blast.
var debris: Array[Debris] = []
## The dice every boarding roll comes from, seeded from the battle's own seed
## at creation: a replay must fight the same deck fight to the same corpse
## count, and drawing from a fresh rng per volley would tie the outcome to
## call order instead of to the seed.
var rolls: RandomNumberGenerator = RandomNumberGenerator.new()

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
	b.rolls.seed = seed_value + 4241
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
		# THE AFTERLIFE. The battle is decided the moment a hull comes apart,
		# but its pieces are still flying, and the winner is usually standing
		# right next to the blast. Debris keeps stepping, and keeps striking,
		# after the verdict: fly in close for the kill and you eat the wreck.
		# Nothing else moves, so a replay that stops at the end tick has lost
		# only this coda.
		_step_debris(dt, Catalog.tuning())
		time += dt
		tick += 1
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
	_step_debris(dt, tuning)
	_step_boarding(dt, tuning)

	_keep_in_arena(tuning)

	for i in range(ships.size()):
		if ships[i].captured_by >= 0 and not over:
			over = true
			winner = ships[i].captured_by
			tractors.clear()
			_events.append({
				"type": "captured", "ship": i, "by": winner, "at": ships[i].pos,
				"log": ["%s CAPTURED, colors struck" % String(
					ships[i].fit.hull()["name"]).to_upper()],
			})
			_events.append({ "type": "end", "winner": winner,
				"reason": "captured" })
			break
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
			debris.append_array(Debris.burst(ships[i], i,
				Catalog.tuning()["combat"], seed_value + tick * 7919 + i))
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
	tractors.append(Tractor.create(attacker, target, tuning))
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


## The wreckage in flight: coast, expire, and strike whoever is in the way.
##
## A piece that hits a hull is spent on it: it shatters against the plating it
## just damaged, so one chunk is one hit. The ship's own collision grace, the
## same one ramming and terrain use, is what stops a cloud of pieces from
## machine gunning a hull every tick.
##
## A strike can kill. When it does after the battle is already decided, the
## verdict stands (the battle was won when the enemy hull came apart, and what
## the wreck does to the winner afterwards is physics, not judgement), but the
## view still gets its "destroyed" event, so the second hull comes apart on
## screen like the first, sheds its own debris, and the comm log tells the
## story.
func _step_debris(dt: float, tuning: Dictionary) -> void:
	if debris.is_empty():
		return
	var combat: Dictionary = tuning["combat"]
	var drag: float = float(combat["debris_drag"])
	var flying: Array[Debris] = []
	# Pieces shed by a ship a strike kills THIS tick. Collected separately and
	# folded in at the end, because appending to the list being walked would
	# either step them a tick early or lose them when the list is rebuilt.
	var shed: Array[Debris] = []
	for piece in debris:
		piece.step(dt, drag)
		if piece.expired():
			continue
		var struck: bool = false
		for i in range(ships.size()):
			var ship: ShipState = ships[i]
			if not ship.alive or ship.collision_grace > 0.0:
				continue
			if piece.pos.distance_to(ship.pos) > ship.radius() + piece.radius:
				continue
			_collide(ship, piece.pos, "debris", piece.damage)
			struck = true
			if not ship.alive:
				_events.append({
					"type": "destroyed", "ship": i, "at": ship.pos,
					"log": ["%s BREAKING UP" % String(
						ship.fit.hull()["name"]).to_upper()],
				})
				shed.append_array(Debris.burst(ship, i, combat,
					seed_value + tick * 7919 + i))
			break
		if not struck:
			flying.append(piece)
	flying.append_array(shed)
	debris = flying


func debris_active() -> bool:
	return not debris.is_empty()


## Send up to `count` of a crew's marines to the enemy deck. Every check is
## Boarding's, so the button and the sim can never disagree about what a legal
## transport is (CLAUDE.md 4.1).
func beam_marines(actor: int, count: int) -> bool:
	if over:
		return false
	var from: ShipState = ships[actor]
	var to: ShipState = ships[1 - actor]
	var combat: Dictionary = Catalog.tuning()["combat"]
	if not bool(Boarding.beam_check(from, to, combat)["ok"]):
		return false
	var sent: int = Boarding.beam(from, mini(count, from.pads_ready().size()),
		combat)
	if sent <= 0:
		return false
	# A fresh team resets the deck's volley clock, so a fight always starts a
	# full interval after the first boots land.
	if ShipState.count_alive(to.away, int(combat["hits_to_kill"])) == 0:
		to.boarding_clock = float(combat["boarding_interval_sec"])
	_events.append({
		"type": "boarding", "ship": 1 - actor, "by": actor,
		"log": ["%d MARINES ABOARD %s" % [sent,
			String(to.fit.hull()["name"]).to_upper()]],
	})
	return true


## Bring the away team home. The same machinery in reverse: each marine coming
## back takes a recharged pad, and the wounded come back wounded.
func recall_marines(actor: int) -> bool:
	if over:
		return false
	var from: ShipState = ships[actor]
	var to: ShipState = ships[1 - actor]
	var combat: Dictionary = Catalog.tuning()["combat"]
	var limit: int = int(combat["hits_to_kill"])
	if ShipState.count_alive(from.away, limit) <= 0:
		return false
	if not bool(Boarding.beam_check(from, to, combat, false)["ok"]):
		return false
	var pads: Array[int] = from.pads_ready()
	var back: int = 0
	for k in range(from.away.size() - 1, -1, -1):
		if back >= pads.size():
			break
		if from.away[k] >= limit:
			continue
		from.marines.append(from.away[k])
		from.away.remove_at(k)
		from.pad_cycles[pads[back]] = float(combat["pad_cycle_sec"])
		back += 1
	if back <= 0:
		return false
	_events.append({
		"type": "boarding", "ship": actor, "by": actor,
		"log": ["%d MARINES RECALLED" % back],
	})
	return true


## The deck fights. Each contested deck has its own clock; every interval both
## sides trade a simultaneous volley (Boarding.volley), and a deck whose last
## defender falls with an attacker still standing changes hands, which ends
## the battle: losing your own deck is losing the ship.
func _step_boarding(dt: float, tuning: Dictionary) -> void:
	var combat: Dictionary = tuning["combat"]
	var limit: int = int(combat["hits_to_kill"])
	for i in range(ships.size()):
		var deck: ShipState = ships[i]
		var raiders: ShipState = ships[1 - i]
		if not deck.alive or deck.captured_by >= 0:
			continue
		if ShipState.count_alive(raiders.away, limit) <= 0:
			continue
		deck.boarding_clock -= dt
		if deck.boarding_clock > 0.0:
			continue
		deck.boarding_clock = float(combat["boarding_interval_sec"])
		var fight: Dictionary = Boarding.volley(deck, raiders.away, rolls, combat)
		var lines: Array[String] = [
			"BOARDING %s: raiders %d shots %d hit, crew %d shots %d hit" % [
				String(deck.fit.hull()["name"]).to_upper(),
				int(fight["att_shots"]), int(fight["att_hits"]),
				int(fight["def_shots"]), int(fight["def_hits"])],
		]
		_events.append({
			"type": "boarding", "ship": i, "by": 1 - i, "log": lines,
		})
		if ShipState.count_alive(deck.marines, limit) == 0 				and ShipState.count_alive(raiders.away, limit) > 0:
			deck.captured_by = 1 - i
			# The verdict itself is spoken by the end-of-step loop, so capture
			# by volley and capture by anything else ever added share one exit.


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
		"beam":
			ok = beam_marines(actor, int(args[0]))
		"recall":
			ok = recall_marines(actor)
		"tractor_plan":
			var beam: Tractor = tractor_on(ship)
			# Only the holder plans. The prisoner does not get to decide where
			# it is being dragged to.
			if beam != null and beam.holder == ship:
				var want_brg: float = Sectors.wrap_deg(float(args[0]))
				var want_off: int = clampi(int(args[1]), 1,
					Tractor.steps(Catalog.tuning()))
				if not is_equal_approx(beam.bearing, want_brg) \
						or beam.standoff != want_off:
					beam.bearing = want_brg
					beam.standoff = want_off
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
