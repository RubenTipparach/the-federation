extends Node3D

## Everything in the arena that is not a ship, drawn once when a battle starts.
##
## The simulation decides what is there and where (src/sim/terrain.gd). This
## node instances the authored scene for each feature and places it, which is
## what CLAUDE.md 5.1 asks for: prebuilt scenes instantiated and configured,
## never node trees assembled here.
##
## It rebuilds only on bind, because terrain does not move. Both cameras looking
## at this world see it, so the plan inset gets the map for free rather than
## through a second painter that could disagree with this one.

## Keyed by kind, and by "kind/variant" where a kind comes in more than one
## look. The four worlds all name the same scene: one shader draws every kind of
## world now, and what separates a gas giant from an ice world is four colours
## and six numbers, both of them data. They stay listed one by one rather than
## collapsing to "planet", because scene_for() naming a variant nothing can draw
## is how a typo in data/maps.json is caught (CLAUDE.md 4.1).
const SCENES: Dictionary = {
	"nebula": preload("res://scenes/terrain/nebula.tscn"),
	"asteroid": preload("res://scenes/terrain/asteroid.tscn"),
	"planet/terran": preload("res://scenes/terrain/planet.tscn"),
	"planet/jungle": preload("res://scenes/terrain/planet.tscn"),
	"planet/volcanic": preload("res://scenes/terrain/planet.tscn"),
	"planet/ice": preload("res://scenes/terrain/planet.tscn"),
	"planet/barren": preload("res://scenes/terrain/planet.tscn"),
	"planet/gas": preload("res://scenes/terrain/planet.tscn"),
	"planet/moon": preload("res://scenes/terrain/planet.tscn"),
}


## The scene that draws one feature: its variant's if it has one, its kind's
## otherwise. A feature naming a variant nothing can draw is a data error, so it
## is simply not drawn rather than silently falling back to the wrong world.
static func scene_for(feature: Dictionary) -> PackedScene:
	var kind: String = String(feature["kind"])
	var variant: String = String(feature.get("variant", ""))
	if not variant.is_empty():
		return SCENES.get("%s/%s" % [kind, variant], null)
	return SCENES.get(kind, null)


## The scene's key light, as a direction pointing AT it, resolved once per
## build and handed to the features that light themselves.
##
## This used to be a lookup by group, and it failed in a real battle: the group
## still held the previous world's Sun, freed, so every planet quietly fell back
## to a default direction and lit itself from the wrong side. A sibling lookup
## cannot go stale, because it is resolved from the tree we are standing in.
func _sun_direction() -> Vector3:
	var parent: Node = get_parent()
	if parent != null:
		var light: Node = parent.get_node_or_null("Sun")
		if light is DirectionalLight3D:
			return (light as DirectionalLight3D).global_transform.basis.z.normalized()
	return Vector3(0.0, 0.0, 1.0)


func build(terrain: Terrain) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if terrain == null:
		return
	var sun: Vector3 = _sun_direction()
	for feature in terrain.features:
		var scene: PackedScene = scene_for(feature)
		if scene == null:
			continue
		var node: Node3D = scene.instantiate()
		add_child(node)
		# Only a world lights itself; a cloud and a rock take the scene's light
		# like everything else does.
		if "sun_direction" in node:
			node.sun_direction = sun
		# Stamped so the debug overlay can find the clouds and the worlds again
		# without asking each scene what it is.
		node.set_meta("terrain_kind", String(feature["kind"]))
		node.place(feature)
