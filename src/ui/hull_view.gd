extends SubViewportContainer

## The ship under the ship systems display: the same committed hull mesh the
## tactical view flies, seen from directly above so the six sectors sit on the
## part of the ship they describe. Placement and configuration only, no
## geometry is built here (CLAUDE.md 5.1).
##
## Two ways to draw it, one component (4.1). The shipyard shows the PAINTED
## hull, because there the display is the identity view and the identity
## includes the paint. A combat readout shows the WIREFRAME, because there the
## display is an instrument: a photograph of a ship competes with the damage
## drawn over it, and a line drawing does not.

## The wireframe hull, from tools/gen_wireframes.py. The name is the painted
## mesh's with a suffix, which is the contract that generator keeps, so a hull
## does not have to name its wireframe in data/ships.json as well.
const WIRE_SUFFIX: String = "_wire.obj"
const WIRE_MATERIAL: ShaderMaterial = preload(
	"res://assets/materials/mat_hull_wire.tres")


## Show the hull named by a hull entry, painted.
func show_hull(hull: Dictionary) -> void:
	var mesh_node: MeshInstance3D = $View/Rig/Hull
	if not _load_mesh(String(hull.get("mesh", ""))):
		return
	# A hull that ships a painted material shows it here too.
	var material_path: String = String(hull.get("material", ""))
	if not material_path.is_empty() and ResourceLoader.exists(material_path):
		mesh_node.material_override = load(material_path)
	else:
		mesh_node.material_override = null
	$View/Rig/Key.visible = true
	_frame(hull)


## Show the hull as a top down wireframe in one colour.
##
## The material is duplicated per view rather than shared, because the own ship
## and the target are two of these on screen at once and they must not be able
## to end up the same colour. A ShaderMaterial copy is a handful of bytes and
## it happens when the ship changes, not per frame.
func show_wireframe(hull: Dictionary, tint: Color) -> void:
	var mesh_node: MeshInstance3D = $View/Rig/Hull
	var path: String = String(hull.get("mesh", ""))
	if not _load_mesh(path.get_basename() + WIRE_SUFFIX):
		return
	var mat: ShaderMaterial = WIRE_MATERIAL.duplicate()
	mat.set_shader_parameter("tint", tint)
	mesh_node.material_override = mat
	# Nothing to light: the shader is unshaded, so the key is dead weight.
	$View/Rig/Key.visible = false
	_frame(hull)


func _load_mesh(path: String) -> bool:
	var mesh_node: MeshInstance3D = $View/Rig/Hull
	if path.is_empty() or not ResourceLoader.exists(path):
		mesh_node.visible = false
		return false
	mesh_node.visible = true
	mesh_node.mesh = load(path)
	return true


## Point the camera and take the one frame this viewport needs.
func _frame(hull: Dictionary) -> void:
	# The mesh is drawn to fill the frame it is given: hulls differ in length by
	# more than three to one, so a fixed camera size would leave a frigate as a
	# speck. Tonnage only nudges it, so a battlecruiser still reads as bigger.
	var tonnage: float = float(hull.get("tonnage", 100))
	var cam: Camera3D = $View/Rig/Camera
	cam.size = clampf(7.0 + tonnage / 200.0 * 2.2, 7.0, 9.5)
	# Straight down with the bow up the screen, the same framing the combat
	# plan inset uses, so the plate and the tactical view agree on which way
	# the ship is pointing.
	cam.look_at_from_position(Vector3(0, 20, 0), Vector3.ZERO, Vector3(0, 0, 1))
	request_frame()


## Draw once more. The viewport renders on demand rather than continuously,
## because nothing in it moves, so anything that changes what it should show
## has to ask. Resizing the container is one of those things, which is why the
## callers that place this also call here.
func request_frame() -> void:
	($View as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE
