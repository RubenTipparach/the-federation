extends Node3D

## What is left of a ship: a fireball and the plates it came apart into.
##
## Presentation only. The simulation has already decided the ship is dead and
## has stopped stepping it (ShipState.alive), so nothing here can change the
## outcome of a battle. That is deliberate: a battle must play out identically
## whether or not anything is drawn (CLAUDE.md 5.2).
##
## Nothing is built here. The blast sphere and the debris plates are committed
## meshes instanced by wreck.tscn; this script gives each plate a direction, a
## tumble and a speed, then flies them apart and fades the fire, which is
## behaviour rather than geometry.
##
## The tumble is drawn from a RandomNumberGenerator seeded by the caller, never
## from the battle's own rng and never from randf(): a replay must show the same
## wreck as the battle it recorded, and it must not be able to change what the
## battle rolled next.

const MAT_BLAST := preload("res://assets/materials/mat_blast.tres")

var _age: float = 0.0
var _life: float = 1.0
## Per plate: direction, spin axis, spin rate. Index aligned with the authored
## children of Chunks.
var _drift: Array[Vector3] = []
var _spin: Array[Vector3] = []
var _blast_from: float = 1.0
var _blast_to: float = 1.0


## radius is how big the ship was, in sim units: everything else is measured
## from it, so a battlecruiser leaves a bigger wreck than a frigate without a
## second table of sizes.
func burst(at: Vector2, radius: float, hull_material: Material, seed_value: int) -> void:
	var view: Dictionary = Catalog.tuning()["wreck"]
	position = Vector3(at.x, 0.0, at.y)
	_life = float(view["seconds"])
	_age = 0.0
	_blast_from = radius * float(view["blast_start_radii"])
	_blast_to = radius * float(view["blast_end_radii"])

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	var blast: MeshInstance3D = $Blast
	# Duplicated, because progress belongs to this wreck and not to every wreck
	# that will ever be drawn.
	blast.material_override = MAT_BLAST.duplicate()
	blast.scale = Vector3.ONE * _blast_from

	var speed: float = radius * float(view["plate_speed_radii"])
	var spread: float = float(view["plate_rise"])
	var chunks: Node3D = $Chunks
	_drift = []
	_spin = []
	for i in range(chunks.get_child_count()):
		var plate: MeshInstance3D = chunks.get_child(i)
		if hull_material != null:
			plate.material_override = hull_material
		# Thrown outward on the plane, with only a little lift: the ships fly on
		# a plane and a wreck that fountained upward would read as a different
		# game (docs/01, the simulation is planar).
		var bearing: float = rng.randf_range(0.0, TAU)
		var out: Vector3 = Vector3(sin(bearing), rng.randf_range(-spread, spread), cos(bearing))
		_drift.append(out.normalized() * speed * rng.randf_range(0.55, 1.0))
		_spin.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)).normalized() * float(view["plate_spin_deg"]))
		plate.position = Vector3.ZERO
		plate.rotation = Vector3(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU),
			rng.randf_range(0.0, TAU))
		plate.scale = Vector3.ONE * radius * rng.randf_range(
			float(view["plate_scale_min"]), float(view["plate_scale_max"]))
		plate.visible = true


func _process(delta: float) -> void:
	if _life <= 0.0:
		return
	_age += delta
	var t: float = clampf(_age / _life, 0.0, 1.0)

	var blast: MeshInstance3D = $Blast
	blast.scale = Vector3.ONE * lerpf(_blast_from, _blast_to, sqrt(t))
	var mat: ShaderMaterial = blast.material_override
	if mat != null:
		mat.set_shader_parameter("progress", t)

	# Plates coast outward and slow, the way a piece of hull thrown clear by an
	# explosion does once the blast front has passed it.
	var chunks: Node3D = $Chunks
	var drag: float = 1.0 - t * t
	for i in range(mini(chunks.get_child_count(), _drift.size())):
		var plate: MeshInstance3D = chunks.get_child(i)
		plate.position += _drift[i] * drag * delta
		plate.rotation += _spin[i] * drag * delta
		# Fading a lit material would need a second material per plate, so the
		# plates simply shrink away instead, which reads as burning down.
		plate.scale *= (1.0 - delta * 0.25 * t)

	if _age >= _life:
		queue_free()
