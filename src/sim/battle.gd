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
var _events: Array[Dictionary] = []
var _targets: Dictionary = {}


static func create_duel(player_fit: ShipFit, enemy_hull_id: String, seed_value: int) -> Battle:
	var b: Battle = Battle.new()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var tuning: Dictionary = Catalog.tuning()["combat"]
	var sep: float = float(tuning["start_separation"])

	var player: ShipState = ShipState.create(player_fit, rng, false)
	player.pos = Vector2(-sep * 0.5, sep * 0.35)
	player.heading = Sectors.bearing_between(player.pos, Vector2.ZERO)
	player.ordered_heading = player.heading

	var enemy: ShipState = ShipState.create(ShipFit.create_default(enemy_hull_id), rng, true)
	enemy.pos = Vector2(sep * 0.5, -sep * 0.35)
	enemy.heading = Sectors.bearing_between(enemy.pos, Vector2.ZERO)
	enemy.ordered_heading = enemy.heading

	b.ships.append(player)
	b.ships.append(enemy)
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
	for s in ships:
		s.step(dt, tuning)
	_step_seekers(dt, tuning)

	_keep_in_arena(tuning)

	for i in range(ships.size()):
		if not ships[i].alive:
			over = true
			winner = 1 - i
			_events.append({ "type": "end", "winner": winner })
			break
	time += dt
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
			var lines: Array[String] = seeker.target.apply_damage(bearing, float(seeker.damage))
			lines.insert(0, "%s impacts" % [seeker.short])
			_events.append({
				"type": "shot", "weapon": seeker.short, "damage": seeker.damage,
				"hit": true, "range": 0.0, "from_pos": seeker.pos,
				"to_pos": seeker.target.pos, "log": lines,
			})
			continue
		survivors.append(seeker)

	seekers = survivors


func _drain() -> Array[Dictionary]:
	var out: Array[Dictionary] = _events
	_events = []
	return out


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
	_events.append(attacker.fire_at(weapon_index, target))
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
