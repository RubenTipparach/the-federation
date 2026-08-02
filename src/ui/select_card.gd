extends Button

## A pressable card with a title and a subtitle, reused by the hull list, the
## skirmish design list, the enemy list and the settings panel's saved designs
## (CLAUDE.md 4.1: one card, four callers, parameterized rather than cloned).

signal chosen(id: String)
## Only the settings panel connects this, and only after allow_delete. A card
## that cannot be deleted never emits it.
signal delete_requested(id: String)

## How far the body pulls in when the delete button is showing, so a long
## subtitle wraps beside the button instead of running underneath it: the
## button's authored width and margins, and nothing else.
const DELETE_INSET: float = -108.0
const PLAIN_INSET: float = -14.0

var id: String = ""


func setup(p_id: String, title: String, meta: String, accent: Color) -> void:
	id = p_id
	$Body/Title.text = title
	Paint.tint($Body/Title, "font_color", Color.WHITE)
	$Body/Meta.text = meta
	Paint.tint($Body/Meta, "font_color", Palette.DIM)
	Paint.tint(self, "font_color", accent)
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)


## Show the delete button, for the one list whose rows can be thrown away. Off
## by default, so the three lists that only choose are unchanged.
func allow_delete(on: bool) -> void:
	$Delete.visible = on
	$Body.offset_right = DELETE_INSET if on else PLAIN_INSET
	if on:
		Paint.tint($Delete, "font_color", Palette.CRIT)
		if not $Delete.pressed.is_connected(_on_delete):
			$Delete.pressed.connect(_on_delete)


func _on_pressed() -> void:
	chosen.emit(id)


func _on_delete() -> void:
	delete_requested.emit(id)
