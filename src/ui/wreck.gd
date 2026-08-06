extends Node3D

## What is left of a ship: an explosion and the plates it came apart into.
##
## Presentation only, and since debris moved into the simulation that phrase
## means something sharper than it used to. The plates on screen are drawn
## WHEREVER Battle.debris says the pieces are: the sim decides where every
## chunk is and what it strikes, and this node's own job is reduced to
## meshes, tumble, and fade. A battle plays out identically whether or not
## anything here is drawn (CLAUDE.md 5.2), and a chunk that damages the
## survivor does so because the sim flew it there, never because a plate
## happened to be drawn overlapping a hull.
##
## The fire is not drawn here either. scenes/explosion.tscn owns every part
## of a detonation and this scene instances it; the wreck's own job is the
## debris.
##
## A ship comes apart into ITS OWN pieces where it has them. Every painted
## hull is written twice by its generator: once whole and once as eight
## fragments cut out of the same triangles (shiplib.Obj.write_fragments), so
## the wreckage carries that hull's atlas mapping and paint. Each fragment
## keeps the hull's coordinates, so the eight start out reassembled into the
## intact ship. Which sim piece a fragment rides is decided once, by bearing:
## the piece thrown to port carries the fragment that sat to port, which is
## what makes the ship read as bursting rather than as shuffling.
##
## The tumble is the one part of the motion that stays here, because a spin
## is presentation: the sim's piece is a point, and how the mesh turns around
## it cannot strike anyone. It advances on SIM time handed through
## sync_debris, so a paused battle has frozen wreckage, matching the pieces
## it rides. The rng that seeds the tumble is the caller's, never the
## battle's, for the reason the header always gave: a replay must show the
## same wreck, and drawing must not disturb what the battle rolls next.

const MAT_INTERIOR := preload("res://assets/materials/mat_debris_interior.tres")

var _age: float = 0.0
## Per plate: spin axis and rate (view only), the mesh's own centre so the
## tumble can pivot around the chunk rather than around the hull origin it
## was cut in, a small vertical drift so the pieces do not all slide on one
## plane, and the materials to fade.
var _spin: Array[Vector3] = []
var _pivot: Array[Vector3] = []
var _lift: Array[float] = []
var _mats: Array[Array] = []
## Accumulated view rotation per plate, advanced on sim time in sync_debris.
var _turned: Array[Vector3] = []
## Which sim piece each plate rides, matched once by bearing on the first
## sync. -1 is a plate with no piece (a generic slot beyond the piece count).
var _ride: Array[int] = []
var _matched: bool = false
## True once every ridden piece has left the sim, which with the explosion out
## is what lets the node free itself.
var _pieces_done: bool = false


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
	_age = 0.0

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	# The wreck's own rotation is the dead ship's heading, so the explosion is
	# lit inside a turned node. That is harmless and deliberate: the fire is
	# thrown around a full circle, so turning the whole thing turns which piece
	# went where and nothing else.
	$Explosion.burst(radius, seed_value)

	var spread: float = float(view["plate_rise"])
	var trail_size: float = radius * float(
		Catalog.tuning()["view"]["debris_trail"]["size_frac"])
	var real: bool = not fragments.is_empty()
	var chunks: Node3D = $Chunks
	_spin = []
	_pivot = []
	_lift = []
	_mats = []
	_turned = []
	_ride = []
	_matched = false
	_pieces_done = false
	for i in range(chunks.get_child_count()):
		var plate: MeshInstance3D = chunks.get_child(i)
		# A hull with fragments uses as many slots as it has pieces and leaves
		# the rest dark; the generic plates fill every slot.
		if real and i >= fragments.size():
			plate.visible = false
			_spin.append(Vector3.ZERO)
			_pivot.append(Vector3.ZERO)
			_lift.append(0.0)
			_mats.append([])
			_turned.append(Vector3.ZERO)
			continue
		# EVERY MATERIAL IS THIS PLATE'S OWN COPY, because the fade at the end
		# of the debris' life is written into the material, and the hull's
		# atlas material is shared with every living ship of the class. Fading
		# the original would fade the fleet.
		var mats: Array = []
		if real:
			plate.mesh = fragments[i]
			# A fragment is two surfaces, split by the cutter: 0 is the hull's
			# own skin, 1 is the capped tear wearing the shared burning
			# interior. Per surface, because an override would paint the caps
			# in exterior hull plate and the tear would disappear.
			plate.material_override = null
			var skin: Material = hull_material.duplicate() \
				if hull_material != null else null
			plate.set_surface_override_material(0, skin)
			if skin != null:
				mats.append(skin)
			if plate.mesh.get_surface_count() > 1:
				var interior: Material = MAT_INTERIOR.duplicate()
				plate.set_surface_override_material(1, interior)
				mats.append(interior)
			plate.scale = Vector3.ONE * hull_scale
			plate.position = Vector3.ZERO
			plate.rotation = Vector3.ZERO
			_pivot.append(plate.mesh.get_aabb().get_center() * hull_scale)
		else:
			# The generic plates are one closed surface with no tear to paint.
			if hull_material != null:
				var solo: Material = hull_material.duplicate()
				plate.material_override = solo
				mats.append(solo)
			plate.position = Vector3.ZERO
			plate.rotation = Vector3(rng.randf_range(0.0, TAU),
				rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
			plate.scale = Vector3.ONE * radius * rng.randf_range(
				float(view["plate_scale_min"]), float(view["plate_scale_max"]))
			_pivot.append(Vector3.ZERO)
		_mats.append(mats)
		_spin.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)).normalized() * float(view["plate_spin_deg"]))
		_lift.append(rng.randf_range(-spread, spread))
		_turned.append(plate.rotation)
		$Trails.get_child(i).setup(seed_value + i * 131, trail_size)
		plate.visible = true


## Put every plate where its sim piece is. Called by the combat world each
## frame with Battle's own debris for this wreck's ship, which is the one
## place plate positions come from.
##
## `sim_delta` is battle time, so the tumble freezes with the pieces when the
## fight is paused. `fade_seconds` is how much of the end of a piece's life is
## spent fading, from the view's own tuning: how long a chunk EXISTS is the
## sim's number, how it leaves the stage is presentation.
func sync_debris(pieces: Array, sim_delta: float, fade_seconds: float) -> void:
	var chunks: Node3D = $Chunks
	if not _matched:
		_match(pieces)
	var seen: int = 0
	for i in range(mini(chunks.get_child_count(), _ride.size())):
		var plate: MeshInstance3D = chunks.get_child(i)
		if _ride[i] < 0:
			continue
		var trail: Node3D = $Trails.get_child(i)
		var piece: Debris = null
		for candidate in pieces:
			if candidate.bearing == _bearing_key(i):
				piece = candidate
				break
		if piece == null:
			plate.visible = false
			# The chunk is gone; the sparks it already shed finish burning.
			trail.follow(Vector3.ZERO, false, sim_delta)
			continue
		seen += 1
		plate.visible = true
		_turned[i] += _spin[i] * sim_delta
		plate.rotation = _turned[i]
		# The piece is where the CHUNK is, and the tumble must pivot around
		# the chunk rather than around the hull origin the fragment was cut
		# in, or a spinning plate would orbit its own ship. Rotating first and
		# then placing the rotated centre onto the piece is that pivot.
		var target: Vector3 = to_local(Vector3(piece.pos.x, 0.0, piece.pos.y))
		target.y = _lift[i] * minf(piece.age, 6.0)
		plate.position = target - plate.basis * _pivot[i]
		# The last seconds of a piece's life are its fade. Alpha rather than
		# the old shrink, because a chunk that lasted half a minute has been
		# LOOKED AT, and a solid thing quietly getting smaller reads as
		# flying away; a thing going transparent reads as done.
		var remaining: float = piece.ttl - piece.age
		var alpha: float = clampf(remaining / maxf(fade_seconds, 0.001), 0.0, 1.0)
		# The trail follows the chunk's centre and stops being fed once the
		# piece begins to fade: embers off something already going transparent
		# would outshine the thing shedding them.
		trail.follow(to_global(plate.position + plate.basis * _pivot[i]),
			alpha >= 1.0, sim_delta)
		for mat in _mats[i]:
			var plain: StandardMaterial3D = mat
			plain.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA \
				if alpha < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
			var albedo: Color = plain.albedo_color
			plain.albedo_color = Color(albedo.r, albedo.g, albedo.b, alpha)
	if _matched and seen == 0:
		_pieces_done = true


## Decide once which sim piece each plate rides: the piece thrown closest to
## the bearing the fragment already sat on. Greedy nearest, deterministic
## because both lists are in a deterministic order.
func _match(pieces: Array) -> void:
	if pieces.is_empty():
		return
	var chunks: Node3D = $Chunks
	var taken: Array[bool] = []
	taken.resize(pieces.size())
	_ride.resize(chunks.get_child_count())
	_ride.fill(-1)
	for i in range(chunks.get_child_count()):
		var plate: MeshInstance3D = chunks.get_child(i)
		if not plate.visible or plate.mesh == null:
			continue
		var centre: Vector3 = plate.mesh.get_aabb().get_center()
		var world: Vector3 = global_transform.basis * centre
		var want: float = rad_to_deg(atan2(world.x, world.z))
		var best: int = -1
		var best_off: float = 0.0
		for j in range(pieces.size()):
			if taken[j]:
				continue
			var off: float = absf(wrapf(
				float(pieces[j].bearing) - want, -180.0, 180.0))
			if best < 0 or off < best_off:
				best = j
				best_off = off
		if best >= 0:
			taken[best] = true
			_ride[i] = best
			_bearing_keys[i] = float(pieces[best].bearing)
		else:
			plate.visible = false
	_matched = true


## The spawn bearing of the piece plate i rides, which is the stable identity
## a piece keeps while the list it lives in shrinks around it.
var _bearing_keys: Dictionary = {}


func _bearing_key(i: int) -> float:
	return float(_bearing_keys.get(i, -1000.0))


## Ready to leave: the fire is out and every ridden piece has left the sim.
## The combat world checks this rather than the node freeing itself, because
## in a replay the sim stops at the end tick, the pieces never age, and a
## wreck that freed itself on a timer would take still frozen debris with it.
func done() -> bool:
	if $Explosion.burning() or not _pieces_done:
		return false
	# The last sparks finish burning before the node goes: a trail cut off by
	# its own owner's freeing would pop.
	for trail in $Trails.get_children():
		if not trail.idle():
			return false
	return true


func _process(delta: float) -> void:
	_age += delta
	# The fire is an afterimage of a recorded result and runs on frame time;
	# the debris under it runs on the sim's, through sync_debris. The two
	# clocks agree except under pause, where fire drifting on while the
	# pieces freeze is exactly the split the explosion's own header asks for.
	$Explosion.step(delta)
	if done():
		queue_free()
