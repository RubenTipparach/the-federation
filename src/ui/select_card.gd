extends Button

## A pressable card with a title and a subtitle, reused by the hull list, the
## skirmish design list, and the enemy list (CLAUDE.md 4.1: one card, three
## callers, parameterized rather than cloned).

signal chosen(id: String)

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


func _on_pressed() -> void:
	chosen.emit(id)
