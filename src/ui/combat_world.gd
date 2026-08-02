extends Node3D

## The 3D battle view. Ships manoeuvre on the plane; only the camera is 3D
## (docs/01 section 1). The camera is clamped downward only, 25 to 90 degrees,
## through exactly ONE clamp function that every input path calls, because per
## caller clamping is how one path drifts and allows an illegal camera.

const MAT_BEAM := preload("res://assets/materials/mat_beam.tres")
const WRECK := preload("res://scenes/wreck.tscn")

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
	# A new battle starts with a clean field: any wreck still burning from the
	# last one is not part of this one.
	for old_wreck in $Wrecks.get_children():
		$Wrecks.remove_child(old_wreck)
		old_wreck.queue_free()
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


func update_visuals(delta: float, events: Array[Dictionary]) -> void:
	$PlayerRig.refresh()
	$EnemyRig.refresh()
	for e in events:
		if String(e["type"]) == "destroyed":
			_break_up(int(e["ship"]), e["at"])
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
