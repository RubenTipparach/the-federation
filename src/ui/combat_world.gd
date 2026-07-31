extends Node3D

## The 3D battle view. Ships manoeuvre on the plane; only the camera is 3D
## (docs/01 section 1). The camera is clamped downward only, 25 to 90 degrees,
## through exactly ONE clamp function that every input path calls, because per
## caller clamping is how one path drifts and allows an illegal camera.

const MAT_BEAM := preload("res://assets/materials/mat_beam.tres")

var _az_deg: float = 0.0
var _pitch_deg: float = 55.0
var _distance: float = 46.0
var _beam_ttl: Array[float] = [0.0, 0.0, 0.0]
var _next_beam: int = 0
var _battle: Battle


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


func update_visuals(delta: float, events: Array[Dictionary]) -> void:
	$PlayerRig.refresh()
	$EnemyRig.refresh()
	for e in events:
		if String(e["type"]) == "shot":
			_flash_beam(e["from_pos"], e["to_pos"])
			# Light the shield that took it. Which facing and whose ship both
			# come from the event, so the view never re-derives what the damage
			# model already decided.
			var facing: int = int(e.get("facing", -1))
			if facing >= 0:
				var rig: Node = $PlayerRig if bool(e.get("target_player", false)) else $EnemyRig
				rig.flash_shield(facing)
	$PlayerRig.update_flares(delta)
	$EnemyRig.update_flares(delta)
	var fade: float = float(Catalog.tuning()["combat"]["beam_fade_sec"])
	for i in range(3):
		if _beam_ttl[i] > 0.0:
			_beam_ttl[i] -= delta
			var beam: MeshInstance3D = $Beams.get_node("B%d" % i)
			beam.scale.x = maxf(_beam_ttl[i] / fade, 0.01) * 0.3
			beam.visible = _beam_ttl[i] > 0.0


func _flash_beam(from_pos: Vector2, to_pos: Vector2) -> void:
	var beam: MeshInstance3D = $Beams.get_node("B%d" % _next_beam)
	_beam_ttl[_next_beam] = float(Catalog.tuning()["combat"]["beam_fade_sec"])
	_next_beam = (_next_beam + 1) % 3
	var d: Vector2 = to_pos - from_pos
	beam.position = Vector3(from_pos.x, 0.6, from_pos.y)
	beam.rotation.y = deg_to_rad(Sectors.bearing_between(from_pos, to_pos))
	beam.scale = Vector3(0.3, 1, maxf(d.length(), 0.1))
	beam.visible = true


## Screen position of a plane point, for the combat HUD's screen space labels
## (world space label offsets collapse at plan pitch, docs/06 9.1).
func screen_pos(plane_pos: Vector2, height: float = 1.2) -> Vector2:
	return $Camera.unproject_position(Vector3(plane_pos.x, height, plane_pos.y))


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
