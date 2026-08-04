extends Node3D

## The 3D battle view. Ships manoeuvre on the plane; only the camera is 3D
## (docs/01 section 1). The camera is clamped downward only, 25 to 90 degrees,
## through exactly ONE clamp function that every input path calls, because per
## caller clamping is how one path drifts and allows an illegal camera.

const MAT_BEAM := preload("res://assets/materials/mat_beam.tres")
const MAT_DRONE := preload("res://assets/materials/mat_ordnance_drone.tres")
const WRECK := preload("res://scenes/wreck.tscn")
const ORDNANCE := preload("res://scenes/ordnance.tscn")

var _az_deg: float = 0.0
var _pitch_deg: float = 55.0
var _distance: float = 46.0
var _beam_ttl: Array[float] = [0.0, 0.0, 0.0]
var _next_beam: int = 0
var _battle: Battle

## One drawn round per drone the simulation is flying, keyed on the Seeker
## itself. The sim owns where they are and when they die; this is a mirror of
## that list, so a drone cannot be on screen after it has been shot down.
var _drones: Dictionary = {}

## Torpedo bolts crossing the plane. Presentation only, and that is worth
## being clear about: a torpedo is direct fire, so the shot was resolved the
## moment it was fired and nothing about the battle waits for the bolt to
## arrive. What the bolt carries is the shield flash, held back until it lands
## so the two halves of the depiction agree with each other.
var _bolts: Array = []


func _ready() -> void:
	var cam: Dictionary = Catalog.tuning()["camera"]
	_az_deg = float(cam["default_azimuth_deg"])
	_distance = float(cam["distance"])
	set_pitch(float(cam["default_pitch_deg"]))
	$Sun.rotation_degrees = Vector3(-52, 30, 0)
	var half: float = float(Catalog.tuning()["combat"]["arena_half_extent"])
	$Grid.scale = Vector3(half * 4.0, 1, half * 4.0)
	for i in range(3):
		$Beams.get_node("B%d" % i).material_override = MAT_BEAM
	_apply_camera()


func bind_battle(battle: Battle) -> void:
	_battle = battle
	# A new battle starts with a clean field: any wreck still burning from the
	# last one is not part of this one.
	for old_wreck in $Wrecks.get_children():
		$Wrecks.remove_child(old_wreck)
		old_wreck.queue_free()
	# Ordnance from the last battle is not in flight in this one, and the drone
	# table holds Seekers from a battle that has stopped existing.
	for round_in_flight in $Ordnance.get_children():
		$Ordnance.remove_child(round_in_flight)
		round_in_flight.queue_free()
	_drones.clear()
	_bolts.clear()
	for rig_name in ["PlayerRig", "EnemyRig"]:
		for child in get_node(rig_name).get_children():
			(child as Node3D).visible = true
	# Terrain is placed once, because it does not move. Both cameras looking at
	# this world get it, which is why the plan inset needs no painter of its own.
	$Terrain.build(battle.terrain)
	$PlayerRig.bind_ship(battle.player(), true)
	$EnemyRig.bind_ship(battle.enemy(), false)


## The single pitch clamp. 25 degrees is above the angle where arc geometry
## foreshortens into slivers, so legibility is guaranteed structurally.
func clamp_pitch(deg: float) -> float:
	var cam: Dictionary = Catalog.tuning()["camera"]
	return clampf(deg, float(cam["pitch_floor_deg"]), float(cam["pitch_ceil_deg"]))


func set_pitch(deg: float) -> void:
	_pitch_deg = clamp_pitch(deg)
	_apply_camera()


func pitch() -> float:
	return _pitch_deg


func at_pitch_floor() -> bool:
	return _pitch_deg <= float(Catalog.tuning()["camera"]["pitch_floor_deg"]) + 0.01


func orbit(delta_az_deg: float, delta_pitch_deg: float) -> void:
	_az_deg = fposmod(_az_deg + delta_az_deg, 360.0)
	set_pitch(_pitch_deg + delta_pitch_deg)


## The single distance clamp, the counterpart of clamp_pitch. Every zoom path
## goes through it, so no input route can push the camera inside the ship or
## out past the arena.
func clamp_distance(d: float) -> float:
	var cam: Dictionary = Catalog.tuning()["camera"]
	return clampf(d, float(cam["distance_min"]), float(cam["distance_max"]))


func set_distance(d: float) -> void:
	_distance = clamp_distance(d)
	_apply_camera()


func distance() -> float:
	return _distance


## Zoom by a fraction of the current distance rather than a fixed number of
## units, so one notch feels the same close in as far out.
func zoom(amount: float) -> void:
	set_distance(_distance * (1.0 + amount))


## The point the camera orbits: the player's ship, so turning and closing keep
## the ship in the middle instead of sliding it off the edge of the arena.
func pivot() -> Vector3:
	if _battle == null or _battle.ships.is_empty():
		return Vector3.ZERO
	var p: Vector2 = _battle.player().pos
	return Vector3(p.x, 0.0, p.y)


func _apply_camera() -> void:
	var az: float = deg_to_rad(_az_deg)
	var el: float = deg_to_rad(_pitch_deg)
	var focus: Vector3 = pivot()
	var pos: Vector3 = focus + Vector3(
		cos(el) * sin(az), sin(el), cos(el) * cos(az)) * _distance
	$Camera.position = pos
	# At exactly 90 degrees the camera looks along -Y and the default up axis
	# is degenerate, so use +Z as up there: bearing 000 points up the screen,
	# matching the plan inset convention.
	if _pitch_deg > 89.0:
		$Camera.look_at_from_position(pos, focus, Vector3(0, 0, 1))
	else:
		$Camera.look_at_from_position(pos, focus, Vector3.UP)


## Called every frame by the screen: the camera stays on the player and both
## ships lean into their turns.
func follow_pivot(delta: float = 0.0) -> void:
	_apply_camera()
	if delta > 0.0:
		for rig_name in ["PlayerRig", "EnemyRig"]:
			var rig: Node = get_node_or_null(rig_name)
			if rig != null:
				rig.update_bank(delta)


## Two deltas, and the difference between them matters. `delta` is wall time,
## which is what a beam fade and a shield flare run on: those are afterimages
## and they should finish even if the battle is stopped. `sim_delta` is how
## much battle the last frame actually advanced, zero while paused, which is
## what ordnance in flight runs on, because a torpedo frozen in mid air is the
## only honest thing to draw over a frozen battle.
func update_visuals(delta: float, sim_delta: float,
		events: Array[Dictionary]) -> void:
	# Each rig is told who its ship is shooting at, so its arcs can light where
	# a weapon could fire this instant. Both sides come from Battle.target_for,
	# the same choice a shot is resolved against, so a lit arc is never the
	# view's own opinion about who is being engaged.
	$PlayerRig.set_target(_battle.target_for(_battle.player()))
	$EnemyRig.set_target(_battle.target_for(_battle.enemy()))
	$PlayerRig.refresh()
	$EnemyRig.refresh()
	for e in events:
		if String(e["type"]) == "destroyed":
			_break_up(int(e["ship"]), e["at"])
		if String(e["type"]) == "shot":
			# Which facing was struck and whose ship it was both come from the
			# event, so the view never re-derives what the damage model already
			# decided. What differs between a beam and a torpedo is only WHEN
			# the shield lights: at once for a beam, on arrival for a bolt.
			var facing: int = int(e.get("facing", -1))
			var on_player: bool = bool(e.get("target_player", false))
			if String(e.get("family", "")) == "torpedo":
				_launch_bolt(e["from_pos"], e["to_pos"], facing, on_player)
			else:
				_flash_beam(e["from_pos"], e["to_pos"])
				if facing >= 0:
					_rig_of(on_player).flash_shield(facing)
	_step_bolts(sim_delta)
	_sync_drones(sim_delta)
	$PlayerRig.update_flares(delta)
	$EnemyRig.update_flares(delta)
	var fade: float = float(Catalog.tuning()["combat"]["beam_fade_sec"])
	for i in range(3):
		if _beam_ttl[i] > 0.0:
			_beam_ttl[i] -= delta
			var beam: MeshInstance3D = $Beams.get_node("B%d" % i)
			beam.scale.x = maxf(_beam_ttl[i] / fade, 0.01) \
				* float(Catalog.tuning()["view"]["beam_width"])
			beam.visible = _beam_ttl[i] > 0.0


## A ship comes apart: its rig stands down and a wreck takes its place.
##
## The tumble is seeded from the battle's tick rather than from randf(), so a
## replay shows the same wreck as the battle it recorded, and drawing it cannot
## disturb what the simulation rolls next (CLAUDE.md 5.2).
func _break_up(index: int, at: Vector2) -> void:
	var rig: Node3D = $PlayerRig if index == 0 else $EnemyRig
	var wreck: Node3D = WRECK.instantiate()
	$Wrecks.add_child(wreck)
	wreck.burst(at, rig.hull_radius(), rig.hull_material(),
		_battle.tick * 7919 + index, rig.hull_fragments(),
		_battle.ships[index].heading, rig.hull_draw_scale())
	rig.stand_down()




## Which rig belongs to which side. One place, because "player rig or enemy
## rig" was being decided at three call sites and a fourth would have got it
## backwards eventually.
func _rig_of(player_side: bool) -> Node:
	return $PlayerRig if player_side else $EnemyRig


## The height ordnance and fire fly at: the deck line of a hull, which the
## beams already use. Ordnance sharing it is what makes a bolt read as being
## in the same world as the beam it flew beside.
func _deck_line() -> float:
	return float(Catalog.tuning()["view"]["beam_width"]) * 2.0


## Send a torpedo bolt across the plane. It carries the shield flash rather
## than the damage: the damage happened when the trigger was pulled.
func _launch_bolt(from_pos: Vector2, to_pos: Vector2, facing: int,
		on_player: bool) -> void:
	var view: Dictionary = Catalog.tuning()["view"]
	var node: Node3D = ORDNANCE.instantiate()
	$Ordnance.add_child(node)
	node.wear_torpedo(float(view["ordnance_bolt_length"]))
	var bearing: float = Sectors.bearing_between(from_pos, to_pos)
	node.fly(from_pos, bearing, _deck_line(), 0.0)
	_bolts.append({
		"node": node, "from": from_pos, "to": to_pos, "bearing": bearing,
		"travelled": 0.0, "facing": facing, "on_player": on_player,
	})


func _step_bolts(delta: float) -> void:
	if _bolts.is_empty():
		return
	var speed: float = float(Catalog.tuning()["view"]["ordnance_bolt_speed"])
	var height: float = _deck_line()
	var flying: Array = []
	for bolt in _bolts:
		bolt["travelled"] = float(bolt["travelled"]) + speed * delta
		var span: float = Vector2(bolt["from"]).distance_to(Vector2(bolt["to"]))
		if float(bolt["travelled"]) >= span:
			# Arrived. Light the shield it struck, then it is gone: there is no
			# impact object, because the impact is already in the damage model.
			var facing: int = int(bolt["facing"])
			if facing >= 0:
				_rig_of(bool(bolt["on_player"])).flash_shield(facing)
			(bolt["node"] as Node3D).queue_free()
			continue
		var at: Vector2 = Vector2(bolt["from"]).lerp(Vector2(bolt["to"]),
			float(bolt["travelled"]) / maxf(span, 0.001))
		(bolt["node"] as Node3D).fly(at, float(bolt["bearing"]), height, delta)
		flying.append(bolt)
	_bolts = flying


## One drawn drone per drone the simulation is flying. The sim owns the list,
## so a drone shot down by point defense leaves the screen because it left the
## battle, not because the view decided it had (CLAUDE.md 5.2).
func _sync_drones(sim_delta: float) -> void:
	if _battle == null:
		return
	var length: float = float(Catalog.tuning()["view"]["ordnance_drone_length"])
	var height: float = _deck_line()
	var live: Dictionary = {}
	for seeker in _battle.seekers:
		if not seeker.alive():
			continue
		live[seeker] = true
		var node: Node3D = _drones.get(seeker)
		if node == null:
			node = ORDNANCE.instantiate()
			$Ordnance.add_child(node)
			node.wear_drone(MAT_DRONE, length)
			_drones[seeker] = node
		node.fly(seeker.pos, seeker.heading, height, sim_delta)
	for seeker in _drones.keys():
		if live.has(seeker):
			continue
		(_drones[seeker] as Node3D).queue_free()
		_drones.erase(seeker)


func _flash_beam(from_pos: Vector2, to_pos: Vector2) -> void:
	var beam: MeshInstance3D = $Beams.get_node("B%d" % _next_beam)
	_beam_ttl[_next_beam] = float(Catalog.tuning()["combat"]["beam_fade_sec"])
	_next_beam = (_next_beam + 1) % 3
	var width: float = float(Catalog.tuning()["view"]["beam_width"])
	var d: Vector2 = to_pos - from_pos
	# Beams fly at the deck line of a hull, which moved when hulls did.
	beam.position = Vector3(from_pos.x, width * 2.0, from_pos.y)
	beam.rotation.y = deg_to_rad(Sectors.bearing_between(from_pos, to_pos))
	beam.scale = Vector3(width, 1, maxf(d.length(), 0.1))
	beam.visible = true


## Screen position of a plane point, for the combat HUD's screen space labels
## (world space label offsets collapse at plan pitch, docs/06 9.1).
func screen_pos(plane_pos: Vector2, height: float = -1.0) -> Vector2:
	# Labels float above a hull, so the default lift is a fraction of how
	# large hulls are drawn rather than a number that had to be found again
	# every time the world changed scale.
	var lift: float = height if height >= 0.0 \
		else float(Catalog.tuning()["view"]["hull_scale"]) * 1.2
	return $Camera.unproject_position(Vector3(plane_pos.x, lift, plane_pos.y))


## The plane point under a viewport pixel, or NAN Vector2 when off the plane.
func plane_point(screen: Vector2) -> Vector2:
	var origin: Vector3 = $Camera.project_ray_origin(screen)
	var dir: Vector3 = $Camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector2(NAN, NAN)
	var t: float = -origin.y / dir.y
	if t < 0.0:
		return Vector2(NAN, NAN)
	var hit: Vector3 = origin + dir * t
	return Vector2(hit.x, hit.z)
