extends Node3D

## The 3D presence of one ship: authored hull mesh, 12 authored arc run
## instances, 6 authored shield segments, one range ring. This script does
## PLACEMENT AND TINT ONLY (CLAUDE.md 5.1): rotate the authored unit meshes
## into their sectors, scale them to weapon range, pick an authored material.
## All geometry is committed .obj; nothing is generated here.
##
## The firing envelope is drawn as CONTIGUOUS RUNS at true reach. Which sectors
## group into which run, and how far each run reaches, is decided by
## ShipState.envelope_runs; this file only poses one authored disc per run and
## tells its shader how wide the run is and which of the three states it is in.
## Twelve nodes because twelve sectors is the worst case, so the pool covers a
## ship whose every sector is covered by different guns and nothing is ever
## constructed at play time.

const MAT_SHIELD_OK := preload("res://assets/materials/mat_shield_ok.tres")
const MAT_SHIELD_WARN := preload("res://assets/materials/mat_shield_warn.tres")
const MAT_SHIELD_DOWN := preload("res://assets/materials/mat_shield_down.tres")
const MAT_ARC_RUN := preload("res://assets/materials/mat_arc_run.tres")
const MAT_RING_FRIEND := preload("res://assets/materials/mat_ring_friend.tres")
const MAT_RING_FOE := preload("res://assets/materials/mat_ring_foe.tres")
const MAT_HULL_FRIEND := preload("res://assets/materials/mat_hull_friend.tres")
const MAT_HULL_FOE := preload("res://assets/materials/mat_hull_foe.tres")
const MAT_SHIELD_GLOW := preload("res://assets/materials/mat_shield_glow.tres")
const MAT_TURN_ARC := preload("res://assets/materials/mat_turn_arc.tres")

## Seeds the flicker phase and the smoke jitter of the hull fires. Fixed
## numbers rather than a draw, for the reason wreck.gd gives: a replay must
## show the same fire as the battle it recorded, and drawing one must never
## disturb what the simulation rolls next.
const FIRE_SEED: int = 6151
const FIRE_SEED_SIDE: int = 977

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

## The mount the player is pointing at in the ship systems display, or "" for
## none. Every run that mount bears into is drawn in the boldest state, which is
## how a captain finds out where one gun can shoot without reading a table.
var _hovered_mount: String = ""

## Who this ship is shooting at, for readiness. Held rather than passed so that
## refresh() keeps the signature every caller already uses, and it is the same
## ShipState the battle resolves a shot against (Battle.target_for), never a
## second idea of who the target is.
var _target: ShipState = null

## Impact energy per facing, 1.0 the moment a shield is struck and decaying to
## 0. Presentation only: the sim never reads this, so a battle plays out the
## same whether or not anything is drawn.
var _flare: PackedFloat32Array = PackedFloat32Array([0, 0, 0, 0, 0, 0])


func bind_ship(state: ShipState, friendly: bool) -> void:
	_state = state
	$Hull.material_override = MAT_HULL_FRIEND if friendly else MAT_HULL_FOE
	$RangeRing.material_override = MAT_RING_FRIEND if friendly else MAT_RING_FOE
	# The range ring is retired by arcs drawn at true reach. It existed to carry
	# the absolute figure the old fixed radius rosette could not, and a circle at
	# the longest gun's reach now contradicts the outline of every run that does
	# not reach that far. The node stays authored in the scene because the plan
	# inset convention and the shield rings are built around it.
	$RangeRing.visible = false
	for i in range(12):
		var arc: MeshInstance3D = $Arcs.get_node("A%d" % i)
		# arc_run.obj is authored STARTING at +Z and sweeping clockwise, and a
		# run starts on a sector boundary, so the rotation is the run's first
		# sector with no half sector offset. The old wedge needed one because it
		# was authored centred; getting that wrong put every drawn arc edge 15
		# degrees off the arc fire_check enforces.
		#
		# Every run needs its own span, state and colour, so each node gets its
		# own material. A shared resource would mean the last run drawn decided
		# what all twelve looked like, the same reason the shield flare and the
		# turn arc duplicate theirs.
		arc.material_override = MAT_ARC_RUN.duplicate()
		arc.material_override.set_shader_parameter("line_color",
			Palette.CYAN if friendly else Palette.MAGENTA)
		arc.material_override.set_shader_parameter("tick_px", _view("arc_tick_px"))
		arc.material_override.set_shader_parameter("tick_frac", _view("arc_tick_frac"))
		arc.material_override.set_shader_parameter("tick_len", _view("arc_tick_len"))
		arc.material_override.set_shader_parameter("fill_edge", _view("arc_fill_edge"))
		arc.visible = false
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
	_place_fires()
	refresh()


## Where on the hull each sector's fire stands. Done once per binding, because
## it depends on how big this hull is drawn and on nothing that changes during
## a battle.
##
## A facing's fire sits out along that facing's own centre bearing, at the same
## angles the shield segments above use (Sectors.facing_center_bearing), so the
## shield that is down and the fire burning under it are in the same place. The
## core's fire sits amidships, because the core is the volume behind every
## facing and has no bearing of its own.
func _place_fires() -> void:
	var radius: float = hull_radius()
	var out: float = radius * float(Catalog.tuning()["view"]["fire"]["hull_radius_frac"])
	# The plate the fire is standing on: the top of the hull mesh as drawn.
	# Read off the mesh rather than written down, so a taller hull burns from
	# its own deck and not from a number that was measured once on a cruiser.
	var deck: float = $Hull.position.y + $Hull.get_aabb().end.y * $Hull.scale.y
	# The two ships get different seeds, or both hulls flicker on one beat and
	# throw their smoke the same way, which reads as a rendering artefact.
	var side: int = FIRE_SEED if _friendly else FIRE_SEED + FIRE_SEED_SIDE
	for f in range(Sectors.FACING_COUNT):
		var b: float = deg_to_rad(Sectors.facing_center_bearing(f))
		var fire: Node3D = $Fires.get_node("F%d" % f)
		fire.place(Vector3(sin(b) * out, deck, cos(b) * out), radius, side + f)
	$Fires/FCore.place(Vector3(0.0, deck, 0.0), radius,
		side + Sectors.FACING_COUNT)


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


## Set the hull fires from the damage model and advance them by a slice of
## BATTLE time, not wall time: a fire is a thing in the world, like a torpedo
## in flight and unlike a beam afterimage, so a paused fight has a frozen fire.
##
## What lights a fire is the damage model's own record, read and never
## recomputed: a system with no boxes left is out, and the sector it sits in is
## the sector ShipState put it in. There is no second opinion here about what
## counts as destroyed (CLAUDE.md 4.1).
func update_fires(sim_delta: float) -> void:
	var dead: Dictionary = {}
	if _state != null and _state.alive:
		for sys in _state.systems:
			if int(sys["boxes"]) > 0 or int(sys["boxes_max"]) <= 0:
				continue
			var sector: int = int(sys["sector"])
			dead[sector] = int(dead.get(sector, 0)) + 1
	for f in range(Sectors.FACING_COUNT):
		var fire: Node3D = $Fires.get_node("F%d" % f)
		fire.set_intensity(int(dead.get(f, 0)))
		fire.step(sim_delta)
	$Fires/FCore.set_intensity(int(dead.get(ShipState.CORE, 0)))
	$Fires/FCore.step(sim_delta)


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


## Who this ship is shooting at, so a run can say whether it could fire this
## instant. Set by the view from Battle.target_for, and null outside a battle.
func set_target(target: ShipState) -> void:
	_target = target


## Which mount the ship display is being pointed at, or "" for none. The rig
## only draws it; what a hover MEANS is the display's business.
func set_hovered_mount(mount_id: String) -> void:
	_hovered_mount = mount_id


## Which of the three states one run is drawn in. Readiness is
## ShipState.fire_check, the same answer the readiness chips show and the same
## one a real shot is resolved against, so a lit arc can never disagree with
## whether the trigger works (CLAUDE.md 4.1).
##
## Hover outranks ready because it answers a question the player is asking right
## now, and the run is lit for the whole mount rather than only where it bears
## on the target: pointing at a gun should show where that gun reaches.
func _run_state(run: Dictionary) -> String:
	var mounts: Array = run["mounts"]
	if not _hovered_mount.is_empty():
		for j in mounts:
			if String(_state.weapons_rt[int(j)]["mount"]["id"]) == _hovered_mount:
				return "hover"
	if _target != null and _target.alive:
		for j in mounts:
			if bool(_state.fire_check(int(j), _target.pos)["ok"]):
				return "ready"
	return "fitted"


## Whether the run next door stops at the same distance this one does. A tenth
## of a sim unit is well inside the rounding of any two reaches that are meant
## to be the same and well outside the gap between two that are not.
func _same_reach(reach_of: Dictionary, sector: int, reach: float) -> bool:
	var neighbour: int = posmod(sector, Sectors.COUNT)
	if not reach_of.has(neighbour):
		return false
	return absf(float(reach_of[neighbour]) - reach) < 0.1


func refresh() -> void:
	if _state == null or not _state.alive:
		return
	position = Vector3(_state.pos.x, 0, _state.pos.y)
	# Rotating +Y by b maps the mesh's +Z nose to (sin b, 0, cos b), which is
	# exactly the sim's bearing convention, so the sign is positive. Verified:
	# at +90 degrees, +Z maps to +X, and bearing 090 is +X.
	rotation.y = deg_to_rad(_state.heading)

	# The firing envelope, at TRUE reach. The sim groups the sectors into runs
	# and says how far each one shoots (ShipState.envelope_runs); this loop only
	# poses one authored disc per run and hands its shader the span and the
	# state. Nothing about arcs or ranges is decided here.
	#
	# Drawn at true scale a filled sector was a slab most of the arena wide,
	# which is a colour wash over the battle rather than a readout. What makes
	# true scale survivable is that a run is a wire outline over a fill of about
	# five percent: the shape is carried by three lines instead of by an area,
	# so the reach can be honest and the battle stays visible through it.
	var runs: Array[Dictionary] = _state.envelope_runs()
	# How far the run covering each sector reaches, so a run can tell whether
	# the neighbour it butts against stops where it does. Where two runs reach
	# the same distance the edge between them is a seam rather than the edge of
	# the envelope, and it is drawn as one.
	var reach_of: Dictionary = {}
	for run in runs:
		for s in run["sectors"]:
			reach_of[int(s)] = float(run["reach"])
	for i in range(12):
		var arc: MeshInstance3D = $Arcs.get_node("A%d" % i)
		arc.visible = i < runs.size()
		if not arc.visible:
			continue
		var run: Dictionary = runs[i]
		var sectors: Array = run["sectors"]
		var reach: float = float(run["reach"])
		arc.rotation.y = deg_to_rad(float(int(sectors[0])) * Sectors.SECTOR_DEG)
		arc.scale = Vector3(reach, 1, reach)
		var mat: ShaderMaterial = arc.material_override
		mat.set_shader_parameter("span_deg",
			float(sectors.size()) * Sectors.SECTOR_DEG)
		mat.set_shader_parameter("inner_r", _view("shield_ring_radius") / reach)
		var state: String = _run_state(run)
		var weights: Dictionary = Catalog.tuning()["view"]["arc_states"][state]
		mat.set_shader_parameter("fill_alpha", float(weights["fill"]))
		mat.set_shader_parameter("line_alpha", float(weights["line"]))
		mat.set_shader_parameter("line_px", float(weights["px"]))
		# A hovered run keeps both its edges at full weight whatever its
		# neighbours do: the player is asking where exactly this gun bears, and
		# a softened edge is the one thing that answer must not have.
		var seam: bool = state != "hover"
		mat.set_shader_parameter("start_seam", 1.0 if seam and _same_reach(
			reach_of, int(sectors[0]) - 1, reach) else 0.0)
		mat.set_shader_parameter("end_seam", 1.0 if seam and _same_reach(
			reach_of, int(sectors[-1]) + 1, reach) else 0.0)

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
