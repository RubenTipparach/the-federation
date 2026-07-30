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
var _events: Array[Dictionary] = []


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
	return ships[1] if ship == ships[0] else ships[0]


## Advance the battle and return the events that happened this step.
func step(dt: float) -> Array[Dictionary]:
	_events = []
	if over:
		return _events
	var tuning: Dictionary = Catalog.tuning()

	CombatAi.act(enemy(), player(), self)
	for s in ships:
		s.step(dt, tuning)

	_keep_in_arena(tuning)

	for i in range(ships.size()):
		if not ships[i].alive:
			over = true
			winner = 1 - i
			_events.append({ "type": "end", "winner": winner })
			break
	time += dt
	return _events


## Fire one weapon if its check passes. Both the player UI and the AI route
## through here so firing rules exist exactly once.
func try_fire(attacker: ShipState, weapon_index: int) -> bool:
	if over:
		return false
	var target: ShipState = foe_of(attacker)
	var check: Dictionary = attacker.fire_check(weapon_index, target.pos)
	if not bool(check["ok"]):
		return false
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
