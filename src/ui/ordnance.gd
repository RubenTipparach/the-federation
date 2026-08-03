extends Node3D

## One round in flight: a drone crossing the plane, or a photon torpedo on its
## way to a target. Placement and tint only (CLAUDE.md 5.1): every mesh here is
## authored in scenes/ordnance.tscn instancing a committed .obj, and this
## script positions, scales, spins and colours them.
##
## The two kinds do not look alike, deliberately. A drone is a missile: a solid
## body with burning exhaust laid down along the path it actually flew. A
## photon is light: three camera facing star meshes stacked, two ray sets
## turning opposite ways around a core that breathes. Starfleet Command drew
## them that way and a player has to tell at a glance whether the thing coming
## at them can be shot down.
##
## One scene serves both because what varies is which children are shown and
## what they wear, which is configuration rather than a reason for a second
## component (CLAUDE.md 6.1 applied to the world).

const PUFFS: int = 12

const MAT_CORE := preload("res://assets/materials/mat_fx_star_core.tres")
const MAT_RAYS := preload("res://assets/materials/mat_fx_star_rays.tres")
const MAT_OUTER := preload("res://assets/materials/mat_fx_star_outer.tres")
const MAT_PLUME := preload("res://assets/materials/mat_fx_plume.tres")

## How far the round travels between exhaust puffs, and how big a puff is
## against the body it trails. Presentation constants: they describe how this
## file draws, not how anything plays, and nothing outside it reads them.
##
## Spacing is a DISTANCE, not an interval. Sampling on a clock made the trail
## length depend on the frame rate and on how fast the round happened to be
## going, and the first two attempts both came out as a blob sitting on the
## drone rather than a plume behind it. Four units apart, twelve of them, is
## forty four units of trail behind an eight unit body, always.
const PUFF_SPACING: float = 4.0
const PUFF_HEAD_SCALE: float = 0.30
const PUFF_TAIL_SCALE: float = 0.05
const PUFF_HEAD_ALPHA: float = 0.8

## How the star moves. The two ray sets turn at different rates and in
## opposite directions, which is what stops a stack of three meshes reading as
## one static decal, and the core breathes on a slower clock again.
const RAYS_SPIN: float = 2.4
const OUTER_SPIN: float = -1.5
const PULSE_HZ: float = 2.2
const PULSE_DEPTH: float = 0.22
## Each layer against the round's stated length.
const CORE_SCALE: float = 0.34
const RAYS_SCALE: float = 1.0
const OUTER_SCALE: float = 1.5

var _kind: String = ""
var _length: float = 1.0
var _age: float = 0.0

## Where the round has been, newest first, sampled every PUFF_SECONDS of
## battle time. The plume is drawn along this, which is what makes it follow
## the round through a turn instead of sticking out behind it like a stick.
var _path: PackedVector2Array = PackedVector2Array()


## A drone: body forward, exhaust behind.
func wear_drone(body_material: Material, length: float) -> void:
	_kind = "drone"
	_length = length
	$Body.visible = true
	$Body.material_override = body_material
	$Body.scale = Vector3(length, length, length)
	$Star.visible = false
	# Each puff gets its own copy of the material so the plume can fade along
	# its length. A shared resource would fade every drone on screen together.
	for i in range(PUFFS):
		var faded: ShaderMaterial = MAT_PLUME.duplicate()
		var tint: Color = faded.get_shader_parameter("tint")
		var t: float = float(i) / float(PUFFS - 1)
		faded.set_shader_parameter("tint",
			Color(tint.r, tint.g, tint.b, PUFF_HEAD_ALPHA * (1.0 - t)))
		_puff(i).material_override = faded


## A photon torpedo: the star, and nothing else.
func wear_torpedo(length: float) -> void:
	_kind = "torpedo"
	_length = length
	$Body.visible = false
	$Star.visible = true
	# Own copies, because the spin uniform is per round: two torpedoes in
	# flight should not be locked in step with each other.
	$Star/Core.material_override = MAT_CORE.duplicate()
	$Star/Rays.material_override = MAT_RAYS.duplicate()
	$Star/Outer.material_override = MAT_OUTER.duplicate()
	for i in range(PUFFS):
		_puff(i).visible = false


## Put the round on the plane at a bearing, and advance whatever it animates.
##
## `sim_delta` is battle time, not frame time, so a paused fight freezes the
## star mid pulse and stops the plume laying down puffs. See
## combat_world.update_visuals for why those are two different numbers.
func fly(at: Vector2, bearing: float, height: float, sim_delta: float) -> void:
	position = Vector3(at.x, height, at.y)
	rotation.y = deg_to_rad(bearing)
	_age += sim_delta
	if _kind == "torpedo":
		_step_star()
	else:
		_step_plume(at, height)


func _puff(i: int) -> MeshInstance3D:
	return $Plume.get_node("P%d" % i) as MeshInstance3D


func _spin(node: MeshInstance3D, rate: float, scale: float) -> void:
	(node.material_override as ShaderMaterial).set_shader_parameter(
		"spin", _age * rate)
	var size: float = _length * scale
	node.scale = Vector3(size, size, size)


func _step_star() -> void:
	var pulse: float = 1.0 + PULSE_DEPTH * sin(_age * PULSE_HZ * TAU)
	_spin($Star/Rays, RAYS_SPIN, RAYS_SCALE * pulse)
	_spin($Star/Outer, OUTER_SPIN, OUTER_SCALE)
	_spin($Star/Core, 0.0, CORE_SCALE * pulse)


## Lay the exhaust down along the path actually flown.
##
## The puffs are children of this node, which is rotated to the round's
## heading, so each one is placed in LOCAL space: the world position it should
## sit at, brought back through this node's transform. That is what lets a
## drone turn hard and leave its plume behind on the old course, instead of
## dragging a rigid tail round with it.
func _step_plume(at: Vector2, height: float) -> void:
	if _path.is_empty() or _path[0].distance_to(at) >= PUFF_SPACING:
		_path.insert(0, at)
		if _path.size() > PUFFS:
			_path.resize(PUFFS)
	var inverse: Transform3D = global_transform.affine_inverse()
	for i in range(PUFFS):
		var puff: MeshInstance3D = _puff(i)
		if i >= _path.size():
			puff.visible = false
			continue
		puff.visible = true
		puff.position = inverse * Vector3(_path[i].x, height, _path[i].y)
		# Puffs are billboards, so their own rotation never matters; the
		# shader turns them to face the camera whatever this node is doing.
		var t: float = float(i) / float(PUFFS - 1)
		var size: float = _length * lerpf(PUFF_HEAD_SCALE, PUFF_TAIL_SCALE, t)
		puff.scale = Vector3(size, size, size)
