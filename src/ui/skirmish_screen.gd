extends HBoxContainer

## Skirmish setup: your custom design on the left, the predefined AI ships on
## the right, begin in the middle. The design cards and the enemy cards are
## the same select_card scene with different data (CLAUDE.md 4.1).

signal begin_battle
signal design_selected(hull_id: String)
signal replay_chosen(log: BattleLog)
## The fleet roster's wheel was pressed: the player wants that ship's bridge.
## Routed up to main like a design pick, because taking a helm redresses the
## whole interface, and main owns the screens that have to repaint.
signal helm_taken(index: int)

const SELECT_CARD := preload("res://scenes/ui/select_card.tscn")
const MAP_CARD := preload("res://scenes/ui/map_card.tscn")

var session: Session


func bind_session(p_session: Session) -> void:
	session = p_session
	$Mid/Begin.pressed.connect(func() -> void: begin_battle.emit())
	$Yours/V/Fleet.bind_session(session)
	$Yours/V/Fleet.helm_taken.connect(
		func(index: int) -> void: helm_taken.emit(index))
	refresh()


func refresh() -> void:
	if session == null:
		return
	_fill_yours()
	_fill_foes()
	_fill_maps()
	_fill_replays()
	$Yours/V/Fleet.refresh()


## The map picker: one card per recipe in data/maps.json, in file order. The
## cards are built once and only repainted afterwards, because building one
## means placing a whole arena and that does not need doing on every click.
func _fill_maps() -> void:
	var row: HBoxContainer = $Mid/Maps
	if row.get_child_count() == 0:
		for map_id in Catalog.map_ids():
			var card: Button = MAP_CARD.instantiate()
			row.add_child(card)
			card.setup(String(map_id))
			card.chosen.connect(_on_map_chosen)
	for card in row.get_children():
		card.paint_selected(card.map_id == session.map_id)
	$Mid/MapBlurb.text = String(Catalog.map(session.map_id)["blurb"])
	Paint.tint($Mid/MapBlurb, "font_color", Palette.DIM)
	$Mid/Kind.text = "DUEL / %s" % String(Catalog.map(session.map_id)["name"]).to_upper()


func _on_map_chosen(map_id: String) -> void:
	session.map_id = map_id
	_fill_maps()


## Every battle this machine has recorded, newest first. Watching one is the
## combat screen in replay mode, not a second view (docs/11).
func _fill_replays() -> void:
	var list: VBoxContainer = $Mid/ReplayScroll/ReplayList
	for child in list.get_children():
		child.queue_free()
	var paths: Array[String] = ReplayStore.list_paths()
	if paths.is_empty():
		var empty: Label = Label.new()
		empty.text = "No recordings yet."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		Paint.tint(empty, "font_color", Palette.DIM)
		list.add_child(empty)
		return
	for path in paths:
		var log: BattleLog = BattleLog.load_from(path)
		if log == null:
			continue
		var card: Button = SELECT_CARD.instantiate()
		list.add_child(card)
		card.setup(path, path.get_file().get_basename(), ReplayStore.describe(log),
			Palette.AMBER)
		card.chosen.connect(func(_id: String) -> void: replay_chosen.emit(log))


## Your designs: every hull you may fly, by navy and up the class ladder.
##
## The grouping and the order are HullList's, and so is the opposition list
## below, and so is the fitting screen's hull picker. Three lists of the same
## fleet that each knew how to group it would be three chances to disagree about
## what order it goes in, which is what CLAUDE.md 4.1 is about; what varies here
## is which hulls and what a card says about one, and both are arguments.
##
## Sixty hulls are what make the grouping worth having. Three cards read as one
## run; sixty do not, and the scroll they sit in fixes the panel, not the
## reading (CLAUDE.md 6.4).
func _fill_yours() -> void:
	HullList.fill($Yours/V/Scroll/List, Catalog.playable_hull_ids(), _paint_design)
	var tonnage: int = int(session.fit.hull()["tonnage"])
	var cap: int = int(Catalog.tuning()["skirmish"]["command_tonnage"])
	$Yours/V/Tonnage.text = "COMMAND TONNAGE  %d / %d" % [tonnage, cap]
	Paint.tint($Yours/V/Tonnage, "font_color",
		Palette.CRIT if tonnage > cap else Palette.DIM)


## A design card: the hull as it would be flown, and for the hull already in
## the chair, the fit that is actually on it rather than the catalog blurb.
func _paint_design(card: Button, hull_id: String) -> void:
	var h: Dictionary = Catalog.hull(hull_id)
	var current: bool = hull_id == session.fit.hull_id
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


## The opposition: the same grouped list as your designs, a different set of
## hulls in it and a different tint on the cards.
func _fill_foes() -> void:
	HullList.fill($Foes/V/Scroll/List, Catalog.ai_hull_ids(), _paint_foe)
	$Foes/V/Tonnage.text = "ENEMY TONNAGE  %d" % int(
		Catalog.hull(session.enemy_hull_id)["tonnage"])
	Paint.tint($Foes/V/Tonnage, "font_color", Palette.DIM)


## An enemy card. It says what the catalog says: there is no fit of the
## player's on the other side of the battle to report.
func _paint_foe(card: Button, hull_id: String) -> void:
	var h: Dictionary = Catalog.hull(hull_id)
	card.setup(hull_id, String(h["name"]),
		"%s / %d t / %s" % [String(h["cls"]), int(h["tonnage"]), String(h["note"])],
		Palette.MAGENTA)
	card.button_pressed = hull_id == session.enemy_hull_id
	card.chosen.connect(_on_foe_chosen)


func _on_yours_chosen(hull_id: String) -> void:
	design_selected.emit(hull_id)
	refresh()


func _on_foe_chosen(hull_id: String) -> void:
	session.enemy_hull_id = hull_id
	refresh()
