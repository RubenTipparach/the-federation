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
