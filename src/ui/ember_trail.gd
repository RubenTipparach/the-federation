extends Node3D

## A trail of embers behind something flying: sparks laid down at the world
## point the thing passed through, hanging there and burning out while it
## sails on.
##
## Presentation only (CLAUDE.md 5.2): the trail reads positions it is handed
## and never decides one. It runs on the CLOCK IT IS HANDED, which for debris
## is battle time, so a paused fight has frozen sparks hanging behind frozen
## chunks.
##
## Nothing is built here (CLAUDE.md 5.1). The ten puffs are authored in
## scenes/ember_trail.tscn; this script places, fades and recycles them as a
## ring buffer. Each puff gets its own copy of the material at ready, because
## the fade is written into the alpha and a shared resource would fade every
## trail in the battle on one clock.
##
## The subsystem fire's smoke plume (src/ui/subsystem_fire.gd) is this same
## shape and predates this component. If the two converge, they converge here
## (CLAUDE.md 4.1); the plume is not touched now because its smoke has heat
## driven laydown and occluding paint that the ember trail has no use for.

## The rng jitters where a spark lands. Seeded by the caller, never the
## battle's own, so a replay shows the same trail and drawing cannot disturb
## what the battle rolls next.
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _size: float = 1.0
var _since: float = 0.0
var _mats: Array[ShaderMaterial] = []
var _ages: PackedFloat32Array = PackedFloat32Array()
var _next: int = 0


static func _tune(key: String) -> float:
	return float(Catalog.tuning()["view"]["debris_trail"][key])


func _ready() -> void:
	for puff in $Puffs.get_children():
		var mesh: MeshInstance3D = puff
		var mat: ShaderMaterial = mesh.material_override.duplicate()
		mesh.material_override = mat
		_mats.append(mat)
		_ages.append(-1.0)
		mesh.visible = false


## `size` is how large a spark is drawn, in sim units: the caller measures it
## from the piece it trails, so a battlecruiser's wreckage burns bigger than a
## frigate's without a second table.
func setup(seed_value: int, size: float) -> void:
	_rng.seed = seed_value
	_size = size


## Follow the thing being trailed: called every frame with where it is now,
## whether it is still flying, and how much battle time passed. Sparks are
## laid only while it flies; the ones in the air always finish burning out,
## which is what lets a trail end in a taper instead of a cut.
func follow(world_pos: Vector3, flying: bool, sim_delta: float) -> void:
	if flying and sim_delta > 0.0:
		_since += sim_delta
		if _since >= _tune("puff_interval_sec"):
			_since = 0.0
			_lay(world_pos)
	var life: float = maxf(_tune("puff_life_sec"), 0.001)
	var burn_down: float = _tune("burn_down")
	for i in range(_ages.size()):
		var puff: MeshInstance3D = $Puffs.get_child(i)
		if _ages[i] < 0.0:
			puff.visible = false
			continue
		_ages[i] += sim_delta
		var t: float = _ages[i] / life
		if t >= 1.0:
			_ages[i] = -1.0
			puff.visible = false
			continue
		puff.visible = true
		# An ember shrinks as it burns down, the opposite of smoke: it is a
		# cooling point, not an expanding cloud.
		puff.scale = Vector3.ONE * _size * lerpf(1.0, burn_down, t)
		var mat: ShaderMaterial = _mats[i]
		var tint: Color = mat.get_shader_parameter("tint")
		mat.set_shader_parameter("tint",
			Color(tint.r, tint.g, tint.b, _tune("puff_alpha") * (1.0 - t)))


func _lay(world_pos: Vector3) -> void:
	if _mats.is_empty():
		return
	var puff: MeshInstance3D = $Puffs.get_child(_next)
	var jitter: float = _size * _tune("jitter_frac")
	# World space, and kept there by Puffs being top_level: a spark belongs to
	# the point it was shed at, not to the chunk that shed it.
	puff.global_position = world_pos + Vector3(
		_rng.randf_range(-jitter, jitter),
		_rng.randf_range(-jitter, jitter) * 0.4,
		_rng.randf_range(-jitter, jitter))
	_ages[_next] = 0.0
	_next = (_next + 1) % _mats.size()


## True when nothing is left burning, so the owner knows the trail will not be
## cut off mid fade by its own freeing.
func idle() -> bool:
	for age in _ages:
		if age >= 0.0:
			return false
	return true
