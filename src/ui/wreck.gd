extends Node3D

## What is left of a ship: a fireball and the plates it came apart into.
##
## Presentation only. The simulation has already decided the ship is dead and
## has stopped stepping it (ShipState.alive), so nothing here can change the
## outcome of a battle. That is deliberate: a battle must play out identically
## whether or not anything is drawn (CLAUDE.md 5.2).
##
## Nothing is built here. The blast sphere and the plates are committed meshes;
## this script gives each plate a direction, a tumble and a speed, then flies
## them apart and fades the fire, which is behaviour rather than geometry.
##
## A ship comes apart into ITS OWN pieces where it has them. Every painted hull
## is written twice by its generator: once whole and once as eight fragments cut
## out of the same triangles (shiplib.Obj.write_fragments), so the wreckage
## carries that hull's atlas mapping and that hull's paint. Because a fragment
## keeps the hull's own coordinates, the eight of them start out reassembled
## into the intact ship, and the direction each one flies is simply away from
## where it already was, read off its own mesh. The generic plates in wreck.tscn
## are the fallback for a hull that has no fragments.
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
func burst(at: Vector2, radius: float, hull_material: Material, seed_value: int,
		fragments: Array[Mesh] = [], heading_deg: float = 0.0,
		hull_scale: float = 1.0) -> void:
	var view: Dictionary = Catalog.tuning()["wreck"]
	position = Vector3(at.x, 0.0, at.y)
	# The wreck inherits the dead ship's heading and drawn size, so its own
	# fragments start out exactly where the hull they were cut from was.
	rotation.y = deg_to_rad(heading_deg)
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
	var real: bool = not fragments.is_empty()
	var chunks: Node3D = $Chunks
	_drift = []
	_spin = []
	for i in range(chunks.get_child_count()):
		var plate: MeshInstance3D = chunks.get_child(i)
		# A hull with fragments uses as many slots as it has pieces and leaves
		# the rest dark; the generic plates fill every slot.
		if real and i >= fragments.size():
			plate.visible = false
			_drift.append(Vector3.ZERO)
			_spin.append(Vector3.ZERO)
			continue
		if hull_material != null:
			plate.material_override = hull_material
		var out: Vector3
		if real:
			plate.mesh = fragments[i]
			plate.scale = Vector3.ONE * hull_scale
			plate.position = Vector3.ZERO
			plate.rotation = Vector3.ZERO
			# Away from where this piece sat on the hull, which is what makes
			# the ship look like it burst rather than like parts were thrown at
			# random. The centre of the fragment's own bounds is that position,
			# so nothing has to be written down alongside the mesh.
			out = plate.mesh.get_aabb().get_center()
			if out.length() < 0.001:
				out = Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0))
			# Flattened toward the plane after normalising, not before, so the
			# lift is the same fraction of the throw for every piece.
			out = out.normalized()
			out.y *= spread
			out = out.normalized()
		else:
			# Thrown outward on the plane, with only a little lift: the ships fly
			# on a plane and a wreck that fountained upward would read as a
			# different game (docs/01, the simulation is planar).
			var bearing: float = rng.randf_range(0.0, TAU)
			out = Vector3(sin(bearing), rng.randf_range(-spread, spread), cos(bearing))
			plate.position = Vector3.ZERO
			plate.rotation = Vector3(rng.randf_range(0.0, TAU),
				rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
			plate.scale = Vector3.ONE * radius * rng.randf_range(
				float(view["plate_scale_min"]), float(view["plate_scale_max"]))
		_drift.append(out.normalized() * speed * rng.randf_range(0.7, 1.0))
		_spin.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)).normalized() * float(view["plate_spin_deg"]))
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
