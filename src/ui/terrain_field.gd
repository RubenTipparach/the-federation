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
## look. A variant is a whole authored scene rather than a material swapped in
## by code, because what differs between a gas giant and an ice world is not
## only its colour: the gas giant carries no ice caps and a different air, and
## those belong in the scene that draws it (CLAUDE.md 5.2).
const SCENES: Dictionary = {
	"nebula": preload("res://scenes/terrain/nebula.tscn"),
	"asteroid": preload("res://scenes/terrain/asteroid.tscn"),
	"planet/rock": preload("res://scenes/terrain/planet_rock.tscn"),
	"planet/ice": preload("res://scenes/terrain/planet_ice.tscn"),
	"planet/gas": preload("res://scenes/terrain/planet_gas.tscn"),
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


func build(terrain: Terrain) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if terrain == null:
		return
	for feature in terrain.features:
		var scene: PackedScene = scene_for(feature)
		if scene == null:
			continue
		var node: Node3D = scene.instantiate()
		add_child(node)
		node.place(feature)
