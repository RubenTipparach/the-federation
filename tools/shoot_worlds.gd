extends SceneTree

## Photograph every world the game can place, at its native art size.
##
## Run through scripts/gen-world-plates.sh, which then hands the output to
## tools/gen_world_plates.py to compose the concept plates in docs/images.
##
## It grabs each planet scene's SubViewport rather than the 3D view, so the art
## arrives at exactly the pixel size the shaders drew it, on a transparent
## ground and with no camera or lighting between. That is what a concept plate
## wants, and it is also the only honest way to show the art: what a screenshot
## of the battle would show is this same texture on a billboard.
##
## Three worlds per variant, because src/ui/pixel_planet.gd derives the shader
## seed from where the simulation put the feature. A different spot IS a
## different world, so these are three real draws rather than one picture shown
## three times. The spots are written here rather than randomised so the plates
## regenerate identically.

const OUT := "res://docs/images/worlds/native/"
const VARIANTS := ["terran", "ice", "barren", "gas"]
const SPOTS := [Vector2(-260.0, 140.0), Vector2(310.0, -90.0), Vector2(70.0, 420.0)]

## The body radius the plates are drawn at, in arena units. data/maps.json gives
## a world a radius between 40 and 55; this is the middle of that.
const BODY: float = 50.0
## The gravity well radius. It does not appear in these plates, since the well
## ring lies on the combat plane rather than on the planet's card, but place()
## wants one.
const FIELD: float = 180.0


func _initialize() -> void:
	var dir: String = ProjectSettings.globalize_path(OUT)
	DirAccess.make_dir_recursive_absolute(dir)
	var holder := Node3D.new()
	root.add_child(holder)
	for i in range(3):
		await process_frame

	var written: int = 0
	for variant in VARIANTS:
		var scene: PackedScene = load("res://scenes/terrain/planet_%s.tscn" % variant)
		for s in range(SPOTS.size()):
			var world: Node3D = scene.instantiate()
			holder.add_child(world)
			world.place({
				"pos": SPOTS[s],
				"body": BODY,
				"field": FIELD,
				"variant": variant,
			})
			# The viewport renders ONCE, so wait for the frame it renders on.
			for i in range(6):
				await process_frame
			var view: SubViewport = world.get_node("Render")
			var img: Image = view.get_texture().get_image()
			var path: String = "%s%s-%d.png" % [OUT, variant, s]
			img.save_png(path)
			print("WORLD: %s  %dx%d" % [path, img.get_width(), img.get_height()])
			written += 1
			world.queue_free()
			await process_frame

	print("WORLDS_DONE %d" % written)
	quit(0)
