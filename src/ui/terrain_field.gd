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

const SCENES: Dictionary = {
	"nebula": preload("res://scenes/terrain/nebula.tscn"),
	"asteroid": preload("res://scenes/terrain/asteroid.tscn"),
	"planet": preload("res://scenes/terrain/planet.tscn"),
}


func build(terrain: Terrain) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if terrain == null:
		return
	for feature in terrain.features:
		var kind: String = String(feature["kind"])
		if not SCENES.has(kind):
			continue
		var node: Node3D = (SCENES[kind] as PackedScene).instantiate()
		add_child(node)
		node.place(feature)
