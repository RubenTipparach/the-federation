extends Node3D

## One piece of terrain in the 3D battle view: a cloud bank, a rock, or a world.
##
## The three feature scenes under scenes/terrain/ all carry THIS script. What
## differs between them is authored structure and authored materials, not
## behaviour: a nebula is a sphere with the cloud material, a rock is a sphere
## and a filled halo, a world is a sphere and a ring. Three scripts that each
## scaled a sphere would be three chances to disagree about what "field radius"
## means (CLAUDE.md 4.1).
##
## Nothing here builds geometry or node trees. Every mesh is a committed .obj
## instanced by an authored scene, and this script only positions and scales
## what the scene already contains, which is the placement pattern CLAUDE.md
## section 7 allows for tactical overlays.

## Sizes come from the simulation, which is the authority on where a feature is
## and how far it reaches. Only the vertical proportion is a view decision, and
## it lives in data/tuning.json rather than in an inspector field (5.4).
func place(feature: Dictionary) -> void:
	var at: Vector2 = feature["pos"]
	position = Vector3(at.x, 0.0, at.y)

	var view: Dictionary = Catalog.tuning()["terrain_view"]
	var body_r: float = float(feature["body"])
	var field_r: float = float(feature["field"])

	var solid: Node3D = get_node_or_null("Body")
	if solid != null:
		# A cloud has no solid body, so its volume is its whole field. A rock
		# has a floor on its drawn size, because a body radius under half a unit
		# is a dot nobody can see coming.
		var radius: float = body_r
		var flatten: float = 1.0
		if radius <= 0.0:
			radius = field_r
			flatten = float(view["nebula_flatten"])
		else:
			radius = maxf(radius, float(view["body_min_radius"]))
		solid.scale = Vector3(radius, radius * flatten, radius)

	var reach: Node3D = get_node_or_null("Field")
	if reach != null:
		reach.scale = Vector3(field_r, 1.0, field_r)
		reach.position.y = float(view["field_y"])
