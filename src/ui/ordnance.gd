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

const MAT_CORE := preload("res://assets/materials/mat_fx_star_core.tres")
const MAT_RAYS := preload("res://assets/materials/mat_fx_star_rays.tres")
const MAT_OUTER := preload("res://assets/materials/mat_fx_star_outer.tres")
const MAT_PLUME := preload("res://assets/materials/mat_ordnance_drone.tres")

## How long the exhaust cone is against the body it trails, and how wide.
## A wake rather than a string of puffs laid along the path flown: the puff
## version measured correct in every number it could report, spanning forty
## seven units with twelve instances visible and materialed, and drew nothing
## at all on screen. Solid mesh, billboarded mesh, tint material, billboard
## material and world space placement were each ruled out one at a time, which
## leaves the offset subtree itself, and that was not worth more of the
## budget. A cone behind the engine is what the reference shows anyway.
const WAKE_LENGTH: float = 3.2
const WAKE_WIDTH: float = 0.55
## See through, or the drone reads as a dart rather than as a body with
## something streaming off it.
const WAKE_ALPHA: float = 0.45

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



## A drone: body forward, exhaust behind.
func wear_drone(body_material: Material, length: float) -> void:
	_kind = "drone"
	_length = length
	$Body.visible = true
	$Body.material_override = body_material
	$Body.scale = Vector3(length, length, length)
	$Star.visible = false
	$Wake.visible = true
	# Its own copy, because the alpha is dropped on the wake and a shared
	# resource would fade every other round on screen with it.
	var faded: ShaderMaterial = MAT_PLUME.duplicate()
	var tint: Color = faded.get_shader_parameter("tint")
	faded.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, WAKE_ALPHA))
	$Wake.material_override = faded
	$Wake.scale = Vector3(length * WAKE_WIDTH, length * WAKE_WIDTH,
		length * WAKE_LENGTH)


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
	$Wake.visible = false


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

