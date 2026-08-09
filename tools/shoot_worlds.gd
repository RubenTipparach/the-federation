extends SceneTree

## Photograph every world the game can place.
##
## Run through scripts/gen-world-plates.sh, which then hands the output to
## tools/gen_world_plates.py to compose the concept plates in docs/images.
##
## It instances the real scenes/terrain/planet.tscn and calls the same place()
## the battle calls, under a light rig copied from scenes/combat_world.tscn, so
## a plate shows what a captain sees rather than a portrait lit for the
## occasion. The camera sits where it has to for the body to fill the frame,
## which is the only thing here the game does not also do.
##
## Three worlds per variant, because src/ui/planet_body.gd derives the shader
## seed from where the simulation put the feature. A different spot IS a
## different world, so these are three real draws rather than one picture shown
## three times. The spots are written here rather than randomised so the plates
## regenerate identically.

const OUT := "res://docs/images/worlds/native/"
const PLANET := preload("res://scenes/terrain/planet.tscn")
const VARIANTS := ["terran", "ice", "barren", "gas"]
const SPOTS := [Vector2(-260.0, 140.0), Vector2(310.0, -90.0), Vector2(70.0, 420.0)]

const SIZE := 360
## The body radius the plates are drawn at, in arena units. data/maps.json gives
## a world a radius between 40 and 55; this is the middle of that.
const BODY: float = 50.0
## The gravity well radius. It is far outside the frame at this magnification,
## but place() wants one and passing a real number keeps the call honest.
const FIELD: float = 180.0

var _view: SubViewport


func _shoot(name: String) -> void:
	_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	for i in range(6):
		await process_frame
	var path: String = "%s%s.png" % [OUT, name]
	_view.get_texture().get_image().save_png(path)
	print("WORLD: %s" % path)


func _initialize() -> void:
	var dir: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)

	_view = SubViewport.new()
	_view.size = Vector2i(SIZE, SIZE)
	_view.transparent_bg = true
	root.add_child(_view)
	var world := Node3D.new()
	_view.add_child(world)

	# The light rig from scenes/combat_world.tscn, so the plates are lit the way
	# the battle is. A world photographed under a nicer sun would be a lie.
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.55, 0.65)
	env.ambient_light_energy = 0.6
	var holder := WorldEnvironment.new()
	holder.environment = env
	world.add_child(holder)
	var sun := DirectionalLight3D.new()
	sun.light_energy = 0.9
	world.add_child(sun)

	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0.0, 30.0, 90.0)
	cam.current = true
	for i in range(4):
		await process_frame
	cam.look_at(Vector3.ZERO, Vector3.UP)

	var written: int = 0
	for variant in VARIANTS:
		for s in range(SPOTS.size()):
			var planet: Node3D = PLANET.instantiate()
			world.add_child(planet)
			planet.place({
				"pos": SPOTS[s],
				"body": BODY,
				"field": FIELD,
				"variant": variant,
			})
			# place() puts a world where the simulation says, which is nowhere
			# near the camera. The plate wants it in front of the lens; the seed
			# it took from that position is already set.
			planet.position = Vector3.ZERO
			# The well ring is edge on from here and paints a hairline across
			# the plate. A concept plate is about the world, not its well.
			planet.get_node("Field").visible = false
			await _shoot("%s-%d" % [variant, s])
			written += 1
			planet.queue_free()
			await process_frame

	# One wider frame of the gas giant, because its ring reaches nearly twice as
	# far as its body and is outside every plate above.
	var giant: Node3D = PLANET.instantiate()
	world.add_child(giant)
	giant.place({"pos": SPOTS[0], "body": BODY, "field": FIELD, "variant": "gas"})
	giant.position = Vector3.ZERO
	giant.get_node("Field").visible = false
	cam.position = Vector3(0.0, 60.0, 180.0)
	for i in range(3):
		await process_frame
	cam.look_at(Vector3.ZERO, Vector3.UP)
	await _shoot("gas-ring")
	written += 1

	print("WORLDS_DONE %d" % written)
	quit(0)
