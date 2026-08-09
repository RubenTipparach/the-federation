extends Node3D

## A world: a real sphere, ray traced by the shader rather than modelled.
##
## The art is Simple Spatial Planet, vendored under assets/vendor/simple_planet
## and documented in docs/14. It is a spatial shader that ignores the mesh it is
## drawn on and intersects a sphere analytically, so the limb is a true circle
## at any zoom and the surface compresses correctly toward the edge. The mesh is
## only a volume to get fragments generated in, which is why it is drawn
## slightly larger than the world it contains and why it needs no texture
## coordinates.
##
## ONE scene draws all four world types, because one shader does: what separates
## a gas giant from an ice world here is four colours and six numbers, and both
## of those are data (data/palette.json worlds, data/tuning.json
## terrain_view.planets). This replaced four scenes wrapping four different
## vendored shaders, and CLAUDE.md 4.1 is the reason it is one now.
##
## This is the same `place(feature)` seam TerrainField calls on every other
## feature scene. Nothing here is constructed: the mesh, its material and the
## well ring are all authored in the scene, and this script sets sizes, colours
## and a seed.

## The gas giant's ring is drawn, the other three worlds have none. It is a
## committed mesh in the scene rather than anything procedural; this only says
## who gets to show theirs.
const RINGED: Array[String] = ["gas"]


func place(feature: Dictionary) -> void:
	var at: Vector2 = feature["pos"]
	position = Vector3(at.x, 0.0, at.y)

	var body: float = float(feature["body"])
	var variant: String = String(feature.get("variant", "terran"))
	var view: Dictionary = Catalog.tuning()["terrain_view"]
	var shape: Dictionary = view["planets"][variant]

	# The mesh has to CONTAIN the sphere the shader traces, or the fragments
	# near the limb are never generated and the world is drawn with a bite out
	# of it. Slack rather than an exact fit for the same reason.
	var ball: MeshInstance3D = $Body
	ball.scale = Vector3.ONE * body * float(view["mesh_slack"])

	var mat: ShaderMaterial = ball.material_override
	mat.set_shader_parameter("radius", body)
	mat.set_shader_parameter("groundLow", Palette.world_color(variant, "low"))
	mat.set_shader_parameter("groundMid", Palette.world_color(variant, "mid"))
	mat.set_shader_parameter("groundHigh", Palette.world_color(variant, "high"))
	mat.set_shader_parameter("rimColor", Palette.world_color(variant, "rim"))
	mat.set_shader_parameter("groundSplit", float(shape["split"]))
	mat.set_shader_parameter("distortionStrength", float(shape["distortion"]))
	mat.set_shader_parameter("bandScale",
		Vector2(float(shape["band_x"]), float(shape["band_y"])))
	mat.set_shader_parameter("rimRetraction", float(shape["rim_retraction"]))
	mat.set_shader_parameter("rimBrightness", float(shape["rim_brightness"]))
	mat.set_shader_parameter("animationSpeed", float(shape["spin"]))

	# Seeded from where the world sits, so two worlds in one arena differ and a
	# replay shows the same world twice. The simulation places the feature, so
	# its position is already reproducible. The seed enters the shader where
	# TIME does, which costs nothing: it reads the same noise field somewhere
	# else.
	var hashed: int = absi(int(at.x * 31.0) ^ int(at.y * 17.0))
	mat.set_shader_parameter("worldSeed", float(hashed % 977) * 0.37)

	var ring: MeshInstance3D = $Ring
	ring.visible = variant in RINGED
	if ring.visible:
		var reach: float = body * float(view["ring_span"])
		ring.scale = Vector3(reach, 1.0, reach)
		var ring_mat: StandardMaterial3D = ring.material_override
		# Alpha stays where the scene set it: how solid a ring is, is art. Only
		# its hue follows the world it belongs to.
		var hue: Color = Palette.world_color(variant, "mid")
		hue.a = ring_mat.albedo_color.a
		ring_mat.albedo_color = hue

	var field: Node3D = get_node_or_null("Field")
	if field != null:
		var span: float = float(feature["field"])
		field.scale = Vector3(span, 1.0, span)
		field.position.y = float(view["field_y"])
