extends Node3D

## A world: a real sphere, ray traced by the shader rather than modelled.
##
## The art is assets/vendor/realtime_planet, documented in docs/14. It is a
## spatial shader that ignores the mesh it is drawn on and intersects a sphere
## with terrain noise added to its radius, so the limb is a true circle at any
## zoom, the surface compresses correctly toward the edge, and mountains break
## the silhouette. The mesh is only a volume to get fragments generated in,
## which is why it is drawn slightly larger than the world it contains and why
## it needs no texture coordinates.
##
## ONE scene draws every kind of world, because one shader does: what separates
## a volcanic world from an ice one is nine colours and twenty one numbers, and
## both of those are data (data/palette.json worlds, data/tuning.json
## terrain_view.planets). Adding a world type touches those two files and
## data/maps.json, and nothing here.
##
## This is the same `place(feature)` seam TerrainField calls on every other
## feature scene. Nothing is constructed: the meshes, their materials and the
## noise texture are all authored in the scene, and this script sets sizes,
## colours and a seed.

## Which worlds are drawn with a ring. It is a committed mesh in the scene; this
## only says who gets to show theirs.
const RINGED: Array[String] = ["gas"]

## The group the scene's key light belongs to. A world has to know where the sun
## is, because it does its own lighting: it is drawn unshaded so that it can put
## an atmosphere and a night side on itself, and neither of those is something
## Godot's light loop can express. Finding the light by group rather than by
## path keeps the planet from knowing what scene it is in.
const SUN_GROUP: StringName = &"sun"

## The colour slots the shader takes, and the uniform each one feeds. Written
## once here so a slot cannot be added to the palette file and quietly not
## reach the shader.
const COLOR_SLOTS: Dictionary = {
	"abyss": "abyssColor",
	"sea": "seaColor",
	"shore": "shoreColor",
	"land": "landColor",
	"peak": "peakColor",
	"cap": "capColor",
	"cloud": "cloudColor",
	"glow": "glowColor",
}

## The shape numbers, and the uniform each one feeds.
const SHAPE_VALUES: Dictionary = {
	"terrain_scale": "terrainScale",
	"noise_strength": "noiseStrength",
	"water_level": "waterLevel",
	"sand_level": "sandLevel",
	"tree_level": "treeLevel",
	"rock_level": "rockLevel",
	"ice_level": "iceLevel",
	"transition": "transitionWidth",
	"clouds_density": "cloudsDensity",
	"clouds_scale": "cloudsScale",
	"clouds_speed": "cloudsSpeed",
	"sun_intensity": "sunIntensity",
	"ambient": "ambientLight",
	"glow_level": "glowLevel",
	"bands": "bands",
	"distortion": "distortionStrength",
	"spin": "spin",
	"relief": "reliefStrength",
}


func place(feature: Dictionary) -> void:
	var at: Vector2 = feature["pos"]
	position = Vector3(at.x, 0.0, at.y)

	var body: float = float(feature["body"])
	var variant: String = String(feature.get("variant", "terran"))
	var view: Dictionary = Catalog.tuning()["terrain_view"]
	var shape: Dictionary = view["planets"][variant]
	var sun: Vector3 = _sun_direction()

	# The mesh has to CONTAIN the sphere the shader traces, and that sphere is
	# the world plus its tallest mountain, so the slack is not decoration.
	var ball: MeshInstance3D = $Body
	ball.scale = Vector3.ONE * body * float(view["mesh_slack"])

	var mat: ShaderMaterial = ball.material_override
	mat.set_shader_parameter("radius", body)
	mat.set_shader_parameter("sunDirection", sun)
	for slot in COLOR_SLOTS:
		mat.set_shader_parameter(StringName(COLOR_SLOTS[slot]),
			Palette.world_color(variant, String(slot)))
	for key in SHAPE_VALUES:
		mat.set_shader_parameter(StringName(SHAPE_VALUES[key]),
			float(shape[key]))
	mat.set_shader_parameter("bandScale",
		Vector2(float(shape["band_x"]), float(shape["band_y"])))

	# Seeded from where the world sits, so two worlds in one arena differ and a
	# replay shows the same world twice. The simulation places the feature, so
	# its position is already reproducible. The seed turns the world rather than
	# reseeding the noise, which costs nothing: the same field is read from a
	# different angle.
	var hashed: int = absi(int(at.x * 31.0) ^ int(at.y * 17.0))
	mat.set_shader_parameter("worldSeed", float(hashed % 977) * 0.37)

	# The air. Its shell is scaled past the body so the haze has somewhere to
	# reach; a world with no atmosphere simply does not draw it.
	var air: MeshInstance3D = $Atmosphere
	var density: float = float(shape["atmosphere_density"])
	air.visible = density > 0.0
	if air.visible:
		air.scale = Vector3.ONE * body * float(shape["shell"])
		var air_mat: ShaderMaterial = air.material_override
		air_mat.set_shader_parameter("radius", body)
		air_mat.set_shader_parameter("sunDirection", sun)
		air_mat.set_shader_parameter("sunIntensity", float(shape["sun_intensity"]))
		air_mat.set_shader_parameter("atmosphereDensity", density)
		air_mat.set_shader_parameter("atmosphereColor",
			Palette.world_color(variant, "rim"))

	var ring: MeshInstance3D = $Ring
	ring.visible = variant in RINGED
	if ring.visible:
		var reach: float = body * float(view["ring_span"])
		ring.scale = Vector3(reach, 1.0, reach)
		var ring_mat: StandardMaterial3D = ring.material_override
		# Alpha stays where the scene set it: how solid a ring is, is art. Only
		# its hue follows the world it belongs to.
		var hue: Color = Palette.world_color(variant, "land")
		hue.a = ring_mat.albedo_color.a
		ring_mat.albedo_color = hue

	var field: Node3D = get_node_or_null("Field")
	if field != null:
		var span: float = float(feature["field"])
		# A moon's well is small enough to be noise on the display, and the
		# simulation gives it none, so it simply has no ring.
		field.visible = span > 0.0
		field.scale = Vector3(maxf(span, 0.001), 1.0, maxf(span, 0.001))
		field.position.y = float(view["field_y"])


## Where the sun is, as a direction pointing AT it. A DirectionalLight3D shines
## along its own -Z, so the way back to it is +Z of its basis. With no light in
## the scene a world is lit from the camera's side of the arena, which is wrong
## but visible: a black disc would look like a bug rather than like a mistake.
func _sun_direction() -> Vector3:
	var light: Node = get_tree().get_first_node_in_group(SUN_GROUP)
	if light is DirectionalLight3D:
		return (light as DirectionalLight3D).global_transform.basis.z.normalized()
	return Vector3(0.0, 0.0, 1.0)
