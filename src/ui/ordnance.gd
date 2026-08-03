extends Node3D

## One round in flight: a drone crossing the plane, or a torpedo bolt on its
## way to a target. Placement and tint only (CLAUDE.md 5.1): the body and its
## trail are authored MeshInstance3Ds in scenes/ordnance.tscn instancing the
## committed ordnance.obj, and this script rotates and scales them.
##
## The two things it draws are the same mesh at two scales, nose to nose. The
## second one is flipped along Z in the scene, so it is a tapered wake behind
## the round rather than a second round.

## How much longer the wake is than the body, and how much thinner.
const TRAIL_LENGTH: float = 3.4
const TRAIL_WIDTH: float = 0.45
## The wake is see through, or a drone reads as a stick rather than a body
## with something streaming off it.
const TRAIL_ALPHA: float = 0.35


## Wear a kind of round: the authored material for a torpedo or a drone, and
## how long the body is drawn in sim units.
func wear(material: Material, length: float) -> void:
	$Body.material_override = material
	$Body.scale = Vector3(length, length, length)
	# Its own copy, because the alpha is dropped on the trail and a shared
	# resource would fade every other round on screen with it.
	var faded: Material = material.duplicate()
	var tint: Color = faded.get_shader_parameter("tint")
	faded.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, TRAIL_ALPHA))
	$Trail.material_override = faded
	$Trail.scale = Vector3(length * TRAIL_WIDTH, length * TRAIL_WIDTH,
		length * TRAIL_LENGTH)


## Put it on the plane at a bearing. Height is the deck line the beams already
## fly at, so ordnance and fire read as being in the same layer of the world.
func fly(at: Vector2, bearing: float, height: float) -> void:
	position = Vector3(at.x, height, at.y)
	rotation.y = deg_to_rad(bearing)
