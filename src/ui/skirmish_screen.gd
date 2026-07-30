extends HBoxContainer

## Skirmish setup: your custom design on the left, the predefined AI ships on
## the right, begin in the middle. The design cards and the enemy cards are
## the same select_card scene with different data (CLAUDE.md 4.1).

signal begin_battle
signal design_selected(hull_id: String)

const SELECT_CARD := preload("res://scenes/ui/select_card.tscn")

var session: Session


func bind_session(p_session: Session) -> void:
	session = p_session
	$Mid/Begin.pressed.connect(func() -> void: begin_battle.emit())
	refresh()


func refresh() -> void:
	if session == null:
		return
	_fill_yours()
	_fill_foes()


func _fill_yours() -> void:
	var list: VBoxContainer = $Yours/V/List
	for child in list.get_children():
		child.queue_free()
	for hull_id in Catalog.playable_hull_ids():
		var h: Dictionary = Catalog.hull(hull_id)
		var current: bool = hull_id == session.fit.hull_id
		var card: Button = SELECT_CARD.instantiate()
		list.add_child(card)
		var d_label: String = String(h["note"])
		if current:
			var d: Dictionary = session.fit.derived()
			d_label = "Your fit: %d/%d mounts, blind %s" % [
				int(d["mounts_fitted"]), int(d["mount_count"]), String(d["blind_label"])]
		card.setup(hull_id, String(h["name"]) + ("  [current]" if current else ""),
			"%s / %d t / %s" % [String(h["cls"]), int(h["tonnage"]), d_label],
			Palette.CYAN)
		card.button_pressed = current
		card.chosen.connect(_on_yours_chosen)
	var tonnage: int = int(session.fit.hull()["tonnage"])
	var cap: int = int(Catalog.tuning()["skirmish"]["command_tonnage"])
	$Yours/V/Tonnage.text = "COMMAND TONNAGE  %d / %d" % [tonnage, cap]
	$Yours/V/Tonnage.add_theme_color_override("font_color",
		Palette.CRIT if tonnage > cap else Palette.DIM)


func _fill_foes() -> void:
	var list: VBoxContainer = $Foes/V/List
	for child in list.get_children():
		child.queue_free()
	for hull_id in Catalog.ai_hull_ids():
		var h: Dictionary = Catalog.hull(hull_id)
		var card: Button = SELECT_CARD.instantiate()
		list.add_child(card)
		card.setup(hull_id, String(h["name"]),
			"%s / %d t / %s" % [String(h["cls"]), int(h["tonnage"]), String(h["note"])],
			Palette.MAGENTA)
		card.button_pressed = hull_id == session.enemy_hull_id
		card.chosen.connect(_on_foe_chosen)
	$Foes/V/Tonnage.text = "ENEMY TONNAGE  %d" % int(
		Catalog.hull(session.enemy_hull_id)["tonnage"])
	$Foes/V/Tonnage.add_theme_color_override("font_color", Palette.DIM)


func _on_yours_chosen(hull_id: String) -> void:
	design_selected.emit(hull_id)
	refresh()


func _on_foe_chosen(hull_id: String) -> void:
	session.enemy_hull_id = hull_id
	refresh()
