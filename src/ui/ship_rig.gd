extends Node3D

## The 3D presence of one ship: authored hull mesh, 12 authored wedge
## instances, 6 authored shield segments, one range ring. This script does
## PLACEMENT AND TINT ONLY (CLAUDE.md 5.1): rotate the authored unit meshes
## into their sectors, scale them to weapon range, pick an authored material.
## All geometry is committed .obj; nothing is generated here.

const MAT_SHIELD_OK := preload("res://assets/materials/mat_shield_ok.tres")
const MAT_SHIELD_WARN := preload("res://assets/materials/mat_shield_warn.tres")
const MAT_SHIELD_DOWN := preload("res://assets/materials/mat_shield_down.tres")
const MAT_WEDGE_FRIEND := preload("res://assets/materials/mat_wedge_friend.tres")
const MAT_WEDGE_FOE := preload("res://assets/materials/mat_wedge_foe.tres")
const MAT_RING_FRIEND := preload("res://assets/materials/mat_ring_friend.tres")
const MAT_RING_FOE := preload("res://assets/materials/mat_ring_foe.tres")
const MAT_HULL_FRIEND := preload("res://assets/materials/mat_hull_friend.tres")
const MAT_HULL_FOE := preload("res://assets/materials/mat_hull_foe.tres")
const MAT_SHIELD_GLOW := preload("res://assets/materials/mat_shield_glow.tres")
const MAT_TURN_ARC := preload("res://assets/materials/mat_turn_arc.tres")

## The shield ring and the turn arc are sized in sim units, and the turn arc
## sits well outside the shield band: at close radii the two read as one
## confusing ring in the same colour. Both live in data/tuning.json rather than
## here, because when the arena grew they had to move with everything else that
## measures a distance (CLAUDE.md 5.4).
static func _view(key: String) -> float:
	return float(Catalog.tuning()["view"][key])

var _state: ShipState
## The arc is only drawn for the player's own ship: it shows an ORDER, and the
## enemy's orders are not something the player should be able to read off the
## screen before the ship acts on them.
var _friendly: bool = false

## Impact energy per facing, 1.0 the moment a shield is struck and decaying to
## 0. Presentation only: the sim never reads this, so a battle plays out the
## same whether or not anything is drawn.
var _flare: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])


func bind_ship(state: ShipState, friendly: bool) -> void:
	_state = state
	$Hull.material_override = MAT_HULL_FRIEND if friendly else MAT_HULL_FOE
	$RangeRing.material_override = MAT_RING_FRIEND if friendly else MAT_RING_FOE
	var wedge_mat: Material = MAT_WEDGE_FRIEND if friendly else MAT_WEDGE_FOE
	for i in range(12):
		var w: MeshInstance3D = $Wedges.get_node("W%d" % i)
		# wedge30.obj is authored CENTERED on +Z (bearings -15 to +15), while
		# sector i spans [i*30, i*30+30). The half sector offset aligns the
		# rendered wedge with the arc fire_check enforces; without it every
		# displayed arc edge is 15 degrees off, which the review reproduced.
		w.rotation.y = deg_to_rad(float(i) * Sectors.SECTOR_DEG + Sectors.SECTOR_DEG * 0.5)
		w.material_override = wedge_mat
	for f in range(6):
		var seg: MeshInstance3D = $Shields.get_node("S%d" % f)
		seg.rotation.y = deg_to_rad(float(f) * 60.0)
		var ring: float = _view("shield_ring_radius")
		seg.scale = Vector3(ring, 1, ring)
		# The flare sits over the same facing, wider, and gets its OWN material.
		# A shared resource would mean one ship's hit lighting every ship's
		# shields, because a shader parameter belongs to the material and not
		# to the instance that draws it.
		var glow: MeshInstance3D = $ShieldGlow.get_node("G%d" % f)
		glow.rotation.y = seg.rotation.y
		glow.scale = seg.scale
		glow.material_override = MAT_SHIELD_GLOW.duplicate()
		glow.visible = false
	# Own material for the same reason: the sweep is this ship's, not shared.
	# Amber rather than the allegiance colour, because this is a helm gauge and
	# not a shield: sharing the shields' cyan is what made the first cut
	# unreadable.
	_friendly = friendly
	$TurnArc.material_override = MAT_TURN_ARC.duplicate()
	var arc: float = _view("turn_arc_radius")
	$TurnArc.scale = Vector3(arc, 1.0, arc)
	$TurnArc.material_override.set_shader_parameter("arc_color", Palette.AMBER)
	# The hull mesh is named by the hull's own data, so a Federation cruiser and
	# a Kthaari raider are two committed .obj files and one placement path
	# (CLAUDE.md 2 and 5.1). No geometry is built here.
	var mesh_path: String = String(state.fit.hull().get("mesh", ""))
	if not mesh_path.is_empty() and ResourceLoader.exists(mesh_path):
		$Hull.mesh = load(mesh_path)

	# A hull that ships its own painted material keeps it. Only untextured
	# hulls fall back to the allegiance tint, so a painted ship looks painted
	# rather than being flooded with team colour.
	var material_path: String = String(state.fit.hull().get("material", ""))
	if not material_path.is_empty() and ResourceLoader.exists(material_path):
		$Hull.material_override = load(material_path)

	# Bigger hulls read bigger: scale by tonnage, presentation only.
	var tonnage: float = float(state.fit.hull()["tonnage"])
	var s: float = clampf(0.8 + tonnage / 200.0 * 0.8, 0.8, 1.8) * _view("hull_scale")
	$Hull.scale = Vector3(s, s, s)
	refresh()


## How far the ship is rolled into its turn, eased so it settles rather than
## snapping. Presentation only: the sim has no roll, ships fly on a plane.
var _bank_deg: float = 0.0


func update_bank(delta: float) -> void:
	if _state == null:
		return
	var combat: Dictionary = Catalog.tuning()["combat"]
	# Rolling toward the side it is turning to: a positive turn delta is
	# clockwise seen from above, which banks the starboard wing down.
	var want: float = clampf(
		Sectors.turn_delta(_state.heading, _state.ordered_heading), -90.0, 90.0)
	var target: float = -want / 90.0 * _state.turn_rate() * float(
		combat["bank_deg_per_turn_rate"])
	_bank_deg = lerpf(_bank_deg, target, clampf(
		delta * float(combat["bank_ease"]), 0.0, 1.0))
	$Hull.rotation.z = deg_to_rad(_bank_deg)


## A shot landed on this facing. The facing comes from the damage model's own
## report (ShipState.apply_damage), never recomputed here, so the shield that
## lights up is always the shield that absorbed.
func flash_shield(facing: int) -> void:
	if facing < 0 or facing >= _flare.size():
		return
	_flare[facing] = 1.0


## Fade the flares. Separate from refresh() because it is the one part of the
## rig that depends on elapsed time rather than on sim state, which keeps
## refresh() safe to call when scrubbing a replay to an arbitrary tick.
func update_flares(delta: float) -> void:
	var fade: float = float(Catalog.tuning()["combat"]["shield_flash_sec"])
	for f in range(_flare.size()):
		var glow: MeshInstance3D = $ShieldGlow.get_node("G%d" % f)
		if _flare[f] <= 0.0:
			glow.visible = false
			continue
		_flare[f] = maxf(0.0, _flare[f] - delta / maxf(fade, 0.001))
		# Squared so the flare drops away fast and leaves a soft tail, rather
		# than dimming at a constant rate that reads as a fading lamp.
		glow.visible = _flare[f] > 0.0 and _state != null and _state.alive
		glow.material_override.set_shader_parameter("glow", _flare[f] * _flare[f])


## Half the width a hull is drawn at, in sim units. The wreck that replaces a
## destroyed ship is sized from this, so a battlecruiser leaves a bigger wreck
## than a frigate without anyone writing that down twice.
func hull_radius() -> float:
	return $Hull.scale.x * 1.6


func hull_material() -> Material:
	return $Hull.material_override


## The pieces this hull comes apart into, or an empty list for a hull that has
## none. Paths are derived from the hull mesh rather than listed in ships.json,
## because a fragment is not a design decision a hull gets to make separately:
## it is the same mesh, cut up by the same generator, and the two are written in
## the same breath (shiplib.Obj.write_fragments).
func hull_fragments() -> Array[Mesh]:
	var out: Array[Mesh] = []
	var mesh_path: String = String(_state.fit.hull().get("mesh", ""))
	if mesh_path.is_empty():
		return out
	var stem: String = mesh_path.trim_suffix(".obj")
	var index: int = 0
	while true:
		var path: String = "%s_frag_%d.obj" % [stem, index]
		if not ResourceLoader.exists(path):
			break
		out.append(load(path))
		index += 1
	return out


## How large the hull is drawn, so a wreck made of its own fragments can be
## drawn at the same size the ship was.
func hull_draw_scale() -> float:
	return $Hull.scale.x


## Everything this rig draws, gone at once. Called when the ship comes apart:
## the wreck takes over from here, and a shield ring hanging in the air where a
## hull used to be would say the ship is still there.
func stand_down() -> void:
	for child in get_children():
		(child as Node3D).visible = false


func refresh() -> void:
	if _state == null or not _state.alive:
		return
	position = Vector3(_state.pos.x, 0, _state.pos.y)
	# Rotating +Y by b maps the mesh's +Z nose to (sin b, 0, cos b), which is
	# exactly the sim's bearing convention, so the sign is positive. Verified:
	# at +90 degrees, +Z maps to +X, and bearing 090 is +X.
	rotation.y = deg_to_rad(_state.heading)

	# Sector wedges: visible where a fitted weapon bears, scaled to the
	# longest range that covers the sector. The same fit code the shipyard
	# uses decides this; the rig just poses meshes.
	var ring_range: float = 0.0
	for i in range(12):
		var w: MeshInstance3D = $Wedges.get_node("W%d" % i)
		var r: float = 0.0
		if _state.alive:
			for j in range(_state.weapons_rt.size()):
				if _state.mount_disabled(j):
					continue
				var weapon: Dictionary = _state.weapons_rt[j]["weapon"]
				if weapon.is_empty():
					continue
				if _state.fit.effective_field(_state.weapons_rt[j]["mount"]).has(i):
					r = maxf(r, WeaponModel.max_range(weapon))
		w.visible = r > 0.0
		if r > 0.0:
			w.scale = Vector3(r, 1, r)
		ring_range = maxf(ring_range, r)

	$RangeRing.visible = ring_range > 0.0
	if ring_range > 0.0:
		$RangeRing.scale = Vector3(ring_range, 1, ring_range)

	# Material by shield band. The thresholds live in Palette.shield_band,
	# shared with every 2D shield readout, so the 3D ring can never disagree
	# with the bars about what counts as weak.
	for f in range(6):
		var seg: MeshInstance3D = $Shields.get_node("S%d" % f)
		var frac: float = _state.shields[f] / _state.shield_max
		seg.visible = _state.alive
		match Palette.shield_band(frac):
			"down":
				seg.material_override = MAT_SHIELD_DOWN
			"warn":
				seg.material_override = MAT_SHIELD_WARN
			_:
				seg.material_override = MAT_SHIELD_OK

	# How far the helm still has to bring the ship round. The rig is already
	# rotated to the current heading, so the arc is the signed turn delta and
	# the shader needs nothing else to place it.
	var sweep: float = Sectors.turn_delta(_state.heading, _state.ordered_heading)
	$TurnArc.visible = _state.alive and _friendly
	if $TurnArc.visible:
		$TurnArc.material_override.set_shader_parameter("sweep_deg", sweep)

	$Hull.visible = true
	if not _state.alive:
		$Hull.rotation.z = deg_to_rad(18.0)
