class_name HullList
extends RefCounted

## One grouped list of hulls: a navy's name, then that navy's ships, then the
## next navy. It is the only thing in the game that knows how a list of hulls
## is laid out.
##
## WHY IT IS NOT A METHOD ON A SCREEN.
##
## It began as one on the skirmish screen, which needs it twice: your designs on
## the left and the opposition on the right differ only in what a card says. The
## fitting screen needs it a third time, and the shipyard, the fleet roster and
## the post battle report will each need it again. That is the shape section 6.1
## describes for the ship systems display and the reason section 4.1 gives for
## it: every copy of a list is another chance for two screens to disagree about
## what order the fleet goes in, which is the one thing a player reads across
## screens without thinking about it.
##
## Five hulls did not make this worth having. Sixty five do.
##
## WHAT A CALLER DECIDES, AND WHAT IT DOES NOT.
##
## A caller decides which hulls (`ids`) and what a card says about one
## (`paint`). It does not decide the order: which navy comes first and which
## class comes first are read out of data/factions.json by the catalog
## (CLAUDE.md 5.4), so a screen cannot invent an order of its own.
##
## Nothing here is constructed (CLAUDE.md 5.1). The header and the card are
## authored scenes instanced and configured; this only says how many and in
## what order.

const SELECT_CARD: PackedScene = preload("res://scenes/ui/select_card.tscn")
const LIST_HEADER: PackedScene = preload("res://scenes/ui/list_header.tscn")


## Empty `list` and refill it with `ids`, grouped and ordered.
##
## `paint` is called as paint(card, hull_id) once per hull, after the card is in
## the tree, so it can read the theme and connect the card's signal. Filling
## rather than returning nodes because a caller that had to add them itself
## could add them somewhere else, and then the pinned scroll of section 6.4
## would be around a list that is not the list.
static func fill(list: VBoxContainer, ids: Array[String],
		paint: Callable) -> void:
	for child in list.get_children():
		child.queue_free()
	var by_faction: Dictionary = Catalog.group_by_faction(ids)
	for faction in by_faction:
		var head: Label = LIST_HEADER.instantiate()
		list.add_child(head)
		head.text = Catalog.faction_name(String(faction)).to_upper()
		for hull_id in by_faction[faction]:
			var card: Button = SELECT_CARD.instantiate()
			list.add_child(card)
			paint.call(card, String(hull_id))
