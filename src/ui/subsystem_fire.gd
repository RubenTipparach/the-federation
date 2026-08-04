extends Node3D

## A dead subsystem burning out of one part of a hull: a scorch mark on the
## plate, tongues of flame standing on it, and smoke coming off and trailing
## astern.
##
## PRESENTATION ONLY. Which systems are dead and which sector each sits in are
## already decided by the damage model (ShipState.systems), so this reads that
## and never writes it: a battle plays out identically whether or not anything
## is drawn (CLAUDE.md 5.2). Nothing here is built either. Every node is
## authored in scenes/subsystem_fire.tscn instancing committed meshes; this
## script places, sizes, spins and fades them, which is behaviour rather than
## geometry (CLAUDE.md 5.1).
##
## THE TRAIL IS THE POINT, and it is free. The Plume node is top_level, so a
## puff laid down at the ship's position stays at that world point while the
## ship sails on. Nobody has to know how fast the ship is going, and a ship
## sitting still gets a column of smoke rather than a streak, which is correct.
## The drone's exhaust already works this way.
##
## It runs on SIM TIME, not wall time. A fire is a thing in the world, like a
## torpedo in flight and unlike a beam afterimage, so a paused battle has a
## frozen fire.

## How hot this fire burns. It is a count of dead systems in one sector rather
## than a fraction, because a captain reads "three things in my port quarter
## are gone", and because one dead system must already be plainly visible.
var _intensity: int = 0

## Sim seconds since this fire was placed. Drives the flicker, so two fires
## placed at different times are never in step.
var _age: float = 0.0
var _since_puff: float = 0.0
## Set from the placement seed, so the flicker of the port quarter fire and the
## nose fire are different waves rather than one wave drawn twice.
var _phase: float = 0.0

## How large the ship is, in sim units. Every size below is a fraction of it,
## so a battlecruiser burns bigger than a frigate without a second table, the
## same way the wreck is measured.
var _hull_radius: float = 1.0

## The jitter a puff is thrown with. Its own generator, seeded by the caller
## and never the battle's, for the reason wreck.gd gives: a replay must show
## the same smoke, and drawing it must not disturb what the battle rolls next.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## The authored size of each flame tongue, read once. The scene says what shape
## a flame is and where each tongue stands relative to the plate; the script
## only multiplies the size by how big and how lively this one fire is, and
## never touches the offsets. That is deliberate: a fire burning harder is a
## bigger fire, not one that has climbed out of the hole it is coming from.
var _layer_scale: Array[Vector3] = []
var _layer_mat: Array[ShaderMaterial] = []
var _layer_alpha: PackedFloat32Array = PackedFloat32Array()

## Per puff: its own material, because the fade is written into the alpha, and
## the age it is at. A negative age is a puff that is not in the air.
var _puff_mat: Array[ShaderMaterial] = []
var _puff_age: PackedFloat32Array = PackedFloat32Array()
var _puff_drift: Array[Vector3] = []
var _next_puff: int = 0


static func _tune(key: String) -> float:
	return float(Catalog.tuning()["view"]["fire"][key])


func _ready() -> void:
	for layer in $Flame.get_children():
		var mesh: MeshInstance3D = layer
		_layer_scale.append(mesh.scale)
		# Its own copy of the material, or every fire in the battle would
		# flicker on one beat: a shader parameter belongs to the material and
		# not to the instance drawing it (the bug mat_shield_glow.tres records).
		var mat: ShaderMaterial = mesh.material_override.duplicate()
		mesh.material_override = mat
		_layer_mat.append(mat)
		var authored: Color = mat.get_shader_parameter("tint")
		_layer_alpha.append(authored.a)
	for puff in $Plume.get_children():
		var mesh: MeshInstance3D = puff
		var mat: ShaderMaterial = mesh.material_override.duplicate()
		mesh.material_override = mat
		_puff_mat.append(mat)
		_puff_age.append(-1.0)
		_puff_drift.append(Vector3.ZERO)
	_show(false)


## Put this fire on a part of the hull. `where` is in the ship rig's own space,
## so it turns with the ship; `hull_radius` is how big that ship is drawn.
func place(where: Vector3, hull_radius: float, seed_value: int) -> void:
	position = where
	_hull_radius = hull_radius
	_rng.seed = seed_value
	# Any decimal phase does; what matters is that it differs per fire.
	_phase = _rng.randf() * TAU
	_age = 0.0
	_since_puff = 0.0
	_intensity = 0
	var scar: float = hull_radius * _tune("scar_radius_frac")
	# The scar lies flat on the plate, so its Y is a thickness and not a size.
	$Scar.scale = Vector3(scar, 1.0, scar)
	$Flame.scale = Vector3.ONE * hull_radius * _tune("flame_radius_frac")
	for i in range(_puff_age.size()):
		_puff_age[i] = -1.0
	_show(false)


## How many systems in this part of the hull are out. Zero puts the fire out,
## which is what a repaired box should look like.
func set_intensity(dead_systems: int) -> void:
	_intensity = dead_systems


## Advance by a slice of BATTLE time. Called with sim_delta rather than wall
## delta, so a paused fight has a frozen fire.
func step(delta: float) -> void:
	_age += delta
	var burning: bool = _intensity > 0
	_show(burning)
	if burning:
		_burn(delta)
	# Puffs already in the air finish their lives whether or not the fire is
	# still lit, so putting a fire out leaves its smoke to drift away rather
	# than deleting a trail the player was looking at.
	_drift(delta)


func _show(on: bool) -> void:
	$Scar.visible = on
	$Flame.visible = on


## The flame itself: three tongues, each breathing on its own beat.
func _burn(delta: float) -> void:
	var cap: int = int(_tune("intensity_cap"))
	var heat: float = 1.0 + _tune("intensity_gain") * float(mini(_intensity, cap) - 1)
	var hz: float = _tune("flicker_hz")
	var depth: float = _tune("flicker_depth")
	for i in range(_layer_mat.size()):
		var mesh: MeshInstance3D = $Flame.get_child(i)
		# Each layer on a different multiple of the base rate and a different
		# offset, so the stack writhes instead of pumping as one blob.
		var beat: float = sin((_age * hz * (1.0 + 0.37 * float(i)) + _phase
			+ 2.1 * float(i)) * TAU)
		var wobble: float = 1.0 + depth * beat
		mesh.scale = _layer_scale[i] * heat * wobble
		# The tongues lean, alternately, which is what stops three billboarded
		# discs reading as three billboarded discs.
		var mat: ShaderMaterial = _layer_mat[i]
		mat.set_shader_parameter("spin", beat * depth * (1.0 if i % 2 == 0 else -1.0))
		var tint: Color = mat.get_shader_parameter("tint")
		# Alpha breathes on the opposite beat to the size: a flame that is
		# large is thin, and a flame that has drawn in is bright.
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b,
			clampf(_layer_alpha[i] * (1.0 - depth * beat * 0.6), 0.0, 1.0)))

	var interval: float = _tune("puff_interval_sec") / maxf(heat, 0.001)
	_since_puff += delta
	if _since_puff >= interval:
		_since_puff = 0.0
		_lay_puff()


## Leave a puff of smoke at the world point the fire is at now.
func _lay_puff() -> void:
	if _puff_mat.is_empty():
		return
	var puff: MeshInstance3D = $Plume.get_child(_next_puff)
	var spread: float = _hull_radius * _tune("puff_start_frac")
	# Written in WORLD space, and read back the same way in _drift. Plume is
	# top_level so the two are the same thing, but saying global here is what
	# makes the intent survive somebody unsetting that flag: a puff belongs to
	# the point in space it was made at, not to the ship that made it. That is
	# the whole trick behind the trail.
	puff.global_position = global_position + Vector3(
		_rng.randf_range(-spread, spread), 0.0, _rng.randf_range(-spread, spread))
	var drift: float = _tune("puff_drift")
	_puff_drift[_next_puff] = Vector3(_rng.randf_range(-drift, drift),
		_tune("puff_rise"), _rng.randf_range(-drift, drift))
	_puff_age[_next_puff] = 0.0
	_next_puff = (_next_puff + 1) % _puff_mat.size()


## Every puff in the air: rise, spread and fade.
func _drift(delta: float) -> void:
	var life: float = maxf(_tune("puff_life_sec"), 0.001)
	var start: float = _hull_radius * _tune("puff_start_frac")
	var grow: float = _tune("puff_grow")
	var alpha: float = _tune("puff_alpha")
	for i in range(_puff_age.size()):
		var puff: MeshInstance3D = $Plume.get_child(i)
		if _puff_age[i] < 0.0:
			puff.visible = false
			continue
		_puff_age[i] += delta
		var t: float = _puff_age[i] / life
		if t >= 1.0:
			_puff_age[i] = -1.0
			puff.visible = false
			continue
		puff.visible = true
		puff.global_position += _puff_drift[i] * delta
		var r: float = start * (1.0 + grow * t)
		puff.scale = Vector3(r, r, r)
		var mat: ShaderMaterial = _puff_mat[i]
		var tint: Color = mat.get_shader_parameter("tint")
		# Up fast and down slowly. The rise stops a fresh puff appearing out of
		# nothing at full strength beside the flame, and the long tail is what
		# makes the trail read as one continuous streak rather than as a row of
		# separate dots getting smaller.
		var fade: float = minf(1.0, t * 8.0) * pow(1.0 - t, 1.4)
		mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b,
			alpha * fade))
		mat.set_shader_parameter("spin", float(i) + _age * 0.3)
