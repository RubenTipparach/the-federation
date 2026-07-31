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

const SHIELD_RING_RADIUS := 3.4

var _state: ShipState


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
		seg.scale = Vector3(SHIELD_RING_RADIUS, 1, SHIELD_RING_RADIUS)
	# The hull mesh is named by the hull's own data, so a Federation cruiser and
	# a Kthaari raider are two committed .obj files and one placement path
	# (CLAUDE.md 2 and 5.1). No geometry is built here.
	var mesh_path: String = String(state.fit.hull().get("mesh", ""))
	if not mesh_path.is_empty() and ResourceLoader.exists(mesh_path):
		$Hull.mesh = load(mesh_path)

	# Bigger hulls read bigger: scale by tonnage, presentation only.
	var tonnage: float = float(state.fit.hull()["tonnage"])
	var s: float = clampf(0.8 + tonnage / 200.0 * 0.8, 0.8, 1.8)
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


func refresh() -> void:
	if _state == null:
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

	$Hull.visible = true
	if not _state.alive:
		$Hull.rotation.z = deg_to_rad(18.0)
