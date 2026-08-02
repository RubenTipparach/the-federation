class_name Paint
extends RefCounted

## Apply a value to a Control only when it is not already that value.
##
## This exists because of one measured fact: `add_theme_color_override` costs
## about 37 microseconds and does NOT early out when the colour it is handed is
## the colour already there. Assigning `Label.text` costs 0.8 microseconds when
## the string changes and 0.2 when it does not, because `Label` DOES compare
## first. So a screen that repaints itself from ship state is paying a hundred
## times more for its colours than for its numbers, and paying it every tick
## for values that change a handful of times in a whole battle.
##
## Measured on the combat screen before this existed: the two station tab
## strips alone called `add_theme_color_override` eighty times per tick, which
## is 2,979 microseconds. Guarded, the same eighty calls cost 24. The whole
## HUD refresh was 5,524 microseconds against a 16,666 microsecond frame at
## sixty a second, on a desktop, so a phone never stood a chance.
##
## The guard reads back through Godot's own override table rather than keeping
## a shadow copy. A cache would be marginally faster and would eventually
## disagree with the node, and a paint helper that lies about what colour
## something is would be worse than no helper at all.
##
## Every per-frame paint in the interface goes through here (CLAUDE.md 4.1).
## Do not hand roll the comparison at a call site: a second implementation is
## how one of them stops matching.

## The theme colour slots a Button uses, as one list, because a tab that tints
## its label and forgets its icon is the bug this list prevents.
const BUTTON_SLOTS: Array = ["font_color", "font_disabled_color",
	"font_pressed_color", "icon_normal_color", "icon_disabled_color",
	"icon_pressed_color", "icon_hover_color"]


## One theme colour slot. The whole reason this file exists.
static func tint(node: Control, slot: StringName, color: Color) -> void:
	if node.has_theme_color_override(slot) and node.get_theme_color(slot) == color:
		return
	# The one place in the interface that calls this directly. Everywhere else
	# goes through here, so the guard cannot be forgotten at a call site.
	node.add_theme_color_override(slot, color)


## Every slot a Button paints, in one call, so no caller can paint a partial
## set and leave a tab whose icon and label disagree.
static func button_tint(node: Button, color: Color) -> void:
	for slot in BUTTON_SLOTS:
		tint(node, StringName(slot), color)


## A station tab's icon and its mark, in one call. Same reason BUTTON_SLOTS is
## one list rather than seven call sites: a tab whose glyph says the box is
## dead and whose mark says it is fine is exactly the bug worth designing out.
## The icon is a white alpha mask, so it takes the colour as a modulate.
static func stencil(icon: CanvasItem, mark: Control, color: Color) -> void:
	shade(icon, color)
	tint(mark, "font_color", color)


## Modulate. `CanvasItem.set_modulate` does not compare either, and it dirties
## the item and every child of it when it is set.
static func shade(node: CanvasItem, color: Color) -> void:
	if node.modulate != color:
		node.modulate = color


## Tooltip text. Building the string is usually the cost rather than storing
## it, so callers that format one should check `changed` first and skip the
## formatting entirely; this is for the cheap cases.
static func tip(node: Control, text: String) -> void:
	if node.tooltip_text != text:
		node.tooltip_text = text


## True when the value differs from what was last passed under this key, and
## records it. For the cases where the expensive part is COMPUTING the value,
## not applying it: a caller wraps the whole block, not just the assignment.
##
## Keyed on the node so two panels watching the same field do not shadow each
## other, and stored in node metadata so it dies with the node rather than
## accumulating in a table that outlives the screen.
static func changed(node: Node, key: StringName, value: Variant) -> bool:
	var slot: StringName = StringName("_paint_" + key)
	if node.has_meta(slot) and node.get_meta(slot) == value:
		return false
	node.set_meta(slot, value)
	return true
