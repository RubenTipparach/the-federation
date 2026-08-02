extends Node3D

## A world, drawn as pixel art and shown on a card facing the camera.
##
## The art comes from Deep-Fold's PixelPlanets shaders, vendored under
## assets/vendor/pixel_planets and documented in docs/14. Those are 2D shaders,
## so each world is rendered into its own small viewport and that viewport is
## put on a billboarded sprite in the 3D scene.
##
## A billboard is not a compromise here, it is the correct shape: a sphere
## projects to a circle from every direction, so a card that always faces the
## camera is exactly what a sphere looks like. It also buys the thing a shaded
## 3D ball could not, which is that a planet is now made of the same chunky
## pixels as the ships and the panels.
##
## Every colour is a data/palette.json entry from the `worlds` role map, and the
## shaders never blend: each pixel they emit is one of those colours, dithered
## against its neighbour. So a world is palette entries and nothing else
## (CLAUDE.md 3.1).
##
## This is the same `place(feature)` seam TerrainField calls on every other
## feature scene. Nothing here is constructed: the viewport, the vendored planet
## and the sprite are all authored in the scene, and this script sets sizes,
## colours and a seed.

## How many art pixels across the planet BODY is. The vendored shaders take this
## as their `pixels` uniform, and a scene whose world carries a ring sizes its
## viewport larger than this to leave the ring room.
const PLANET_PX: float = 100.0


func place(feature: Dictionary) -> void:
	var at: Vector2 = feature["pos"]
	position = Vector3(at.x, 0.0, at.y)

	var art: Control = $Render/Planet
	art.set_pixels(PLANET_PX)
	art.set_colors(_palette_for(String(feature.get("variant", ""))))

	# Seeded from where the world sits, so two worlds in one arena differ and a
	# replay shows the same world twice. The simulation places the feature, so
	# its position is already reproducible.
	#
	# The vendored set_seed does sd % 1000 / 100, and its shaders declare the
	# result in the range 1 to 10. Landing on zero there flattens the noise and
	# the world comes out as a plain disc, which is what a world at the arena's
	# exact centre did before this line kept the value off the floor.
	var hashed: int = absi(int(at.x * 31.0) ^ int(at.y * 17.0))
	art.set_seed(100 + hashed % 900)
	# The light comes from up and to the left, which is where the battle view's
	# sun is. It stays put as the camera orbits: a planet whose terminator swung
	# round with the camera would draw the eye to the camera rather than to the
	# fight.
	art.set_light(Vector2(0.36, 0.36))

	var sprite: Sprite3D = $Body
	sprite.texture = ($Render as SubViewport).get_texture()
	# One art pixel is this many sim units, so the body ends up exactly the
	# radius the simulation says it is, whatever else the viewport holds.
	sprite.pixel_size = float(feature["body"]) * 2.0 / PLANET_PX

	# The viewport renders ONCE rather than every frame, so placing a world has
	# to ask for that one frame explicitly. Everything above changed what the
	# shaders will draw, and this is the moment they draw it.
	($Render as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE

	var reach: Node3D = get_node_or_null("Field")
	if reach != null:
		var field: float = float(feature["field"])
		reach.scale = Vector3(field, 1.0, field)
		reach.position.y = float(Catalog.tuning()["terrain_view"]["field_y"])


## The ordered colour list this world's shaders want, resolved from the palette.
static func _palette_for(variant: String) -> PackedColorArray:
	var out: PackedColorArray = PackedColorArray()
	for role in Palette.world_roles(variant):
		out.append(Palette.named(String(role)))
	return out
