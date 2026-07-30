extends SubViewportContainer

## The ship under the ship systems display: the same committed hull mesh the
## tactical view flies, seen from directly above so the six sectors sit on the
## part of the ship they describe. Placement and configuration only, no
## geometry is built here (CLAUDE.md 5.1).


## Show the hull named by a hull entry. The camera pulls back with tonnage so
## a frigate and a battlecruiser both fill the plate.
func show_hull(hull: Dictionary) -> void:
	var path: String = String(hull.get("mesh", ""))
	var mesh_node: MeshInstance3D = $View/Rig/Hull
	if path.is_empty() or not ResourceLoader.exists(path):
		mesh_node.visible = false
		return
	mesh_node.visible = true
	mesh_node.mesh = load(path)
	var tonnage: float = float(hull.get("tonnage", 100))
	var cam: Camera3D = $View/Rig/Camera
	cam.size = clampf(10.5 + tonnage / 200.0 * 3.5, 10.5, 15.0)
	# Straight down with the bow up the screen, the same framing the combat
	# plan inset uses, so the plate and the tactical view agree on which way
	# the ship is pointing.
	cam.look_at_from_position(Vector3(0, 20, 0), Vector3.ZERO, Vector3(0, 0, 1))
