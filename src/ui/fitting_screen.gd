extends HBoxContainer

## The fitting screen: pick a hull, fit weapons into its mounts, watch the
## four budgets, and dry fire the damage model against the design. Thin
## wiring only (CLAUDE.md 5.2): every number shown here is computed by the sim
## library, and the dry dock demo runs the same ShipState.apply_damage that a
## real battle uses.

signal design_changed

const SELECT_CARD := preload("res://scenes/ui/select_card.tscn")
const SECTOR_PANEL := preload("res://scenes/ui/sector_panel.tscn")
const MOUNT_ITEM := preload("res://scenes/ui/mount_fit_item.tscn")

var session: Session
var _demo: ShipState
var _wired: bool = false
var _panels: Array = []  # six facings then the hull core, index is the sector


## Safe to call again when the session's fit is replaced from another screen:
## signal wiring happens once, the data views rebuild every time.
func bind_session(p_session: Session) -> void:
	session = p_session
	refresh_from_session()
	if _wired:
		return
	_wired = true
	var volleys: Array = Catalog.tuning()["fitting_demo"]["volleys"]
	var buttons: Array = [$Center/V/Controls/Fire0, $Center/V/Controls/Fire1,
		$Center/V/Controls/Fire2]
	for i in range(buttons.size()):
		var dmg: int = int(volleys[i]) if i < volleys.size() else 8 * (i + 1)
		buttons[i].text = "Fire (%d)" % dmg
		buttons[i].pressed.connect(_on_fire.bind(dmg))
	$Center/V/Controls/Reset.pressed.connect(_reset_demo)
	$Center/V/Ring.facing_selected.connect(func(f: int) -> void: _log(
		"Attack facing #%d selected" % (f + 1), Palette.CYAN))


func refresh_from_session() -> void:
	_build_hull_list()
	_rebuild_all()


func _build_hull_list() -> void:
	for child in $Left/HullPanel/V/HullList.get_children():
		child.queue_free()
	for hull_id in Catalog.playable_hull_ids():
		var h: Dictionary = Catalog.hull(hull_id)
		var card: Button = SELECT_CARD.instantiate()
		$Left/HullPanel/V/HullList.add_child(card)
		card.setup(hull_id, String(h["name"]),
			"%s / %d t / %d mounts" % [String(h["cls"]), int(h["tonnage"]),
				Array(h["mounts"]).size()],
			Palette.CYAN)
		card.button_pressed = hull_id == session.fit.hull_id
		card.chosen.connect(_on_hull_chosen)


func _on_hull_chosen(hull_id: String) -> void:
	if hull_id != session.fit.hull_id:
		session.fit = ShipFit.create_default(hull_id)
		design_changed.emit()
	_build_hull_list()
	_rebuild_all()


func _on_slot_changed(mount_id: String, weapon_id: String) -> void:
	if session.fit.set_slot(mount_id, weapon_id):
		design_changed.emit()
	_rebuild_all()


func _rebuild_all() -> void:
	_reset_demo()
	_rebuild_mounts()
	_refresh_budgets()


func _reset_demo() -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 20260730
	_demo = ShipState.create(session.fit, rng)
	_rebuild_internals()
	_refresh_state_views()
	$Center/V/Log.clear()
	var h: Dictionary = session.fit.hull()
	_log("%s (%s) in dry dock. Shields %d per facing." % [
		String(h["name"]), String(h["cls"]), int(h["shield_per_facing"])], Palette.CYAN)
	_log("Select a facing on the ring, then fire.", Palette.DIM)


func _rebuild_internals() -> void:
	# The plate: one panel per shield facing arranged around the ring in the
	# ship's own geometry, plus the hull core in the middle. Panels are
	# instances of a committed scene dropped into anchors authored in
	# fitting.tscn, so nothing here builds a node tree (CLAUDE.md 5.1).
	_panels = []
	for sector in range(Sectors.FACING_COUNT + 1):
		var is_core: bool = sector == Sectors.FACING_COUNT
		var anchor: Control = $Center/V/Ring.get_node(
			"Core" if is_core else "Sector%d" % sector)
		for child in anchor.get_children():
			child.queue_free()
		var panel: PanelContainer = SECTOR_PANEL.instantiate()
		anchor.add_child(panel)
		# Centre the panel on its anchor point once it has been sized.
		panel.set_anchors_preset(Control.PRESET_CENTER)
		var key: int = ShipState.CORE if is_core else sector
		panel.build(
			"CORE" if is_core else str(sector + 1),
			"Hull core" if is_core else Sectors.facing_name(sector),
			"no shield" if is_core else Sectors.facing_arc_label(sector),
			_demo.systems_in(key))
		_panels.append(panel)


func _refresh_state_views() -> void:
	$Center/V/Ring.show_state(_demo.shields, _demo.shield_max)
	for sector in range(_panels.size()):
		var is_core: bool = sector == Sectors.FACING_COUNT
		_panels[sector].refresh(
			0.0 if is_core else _demo.shields[sector], _demo.shield_max, not is_core)
	$Center/V/Head.text = "SHIP SYSTEM DISPLAY  %s" % String(
		session.fit.hull()["name"]).to_upper()


func _rebuild_mounts() -> void:
	var list: VBoxContainer = $Right/MountsPanel/V/Scroll/MountList
	for child in list.get_children():
		child.queue_free()
	for mount in session.fit.mounts():
		var item: PanelContainer = MOUNT_ITEM.instantiate()
		list.add_child(item)
		item.setup(mount, session.fit)
		item.slot_changed.connect(_on_slot_changed)


func _refresh_budgets() -> void:
	var b: Dictionary = session.fit.budgets()
	$Right/BudgetsPanel/V/Space.paint("Space", b["space"]["used"], b["space"]["max"], Palette.CYAN)
	$Right/BudgetsPanel/V/Power.paint("Power", b["power"]["used"], b["power"]["max"], Palette.BLUE)
	$Right/BudgetsPanel/V/Mass.paint("Mass", b["mass"]["used"], b["mass"]["max"], Palette.AMBER)
	$Right/BudgetsPanel/V/Crew.paint("Crew", b["crew"]["used"], b["crew"]["max"], Palette.MAGENTA)
	var d: Dictionary = session.fit.derived()
	$Right/BudgetsPanel/V/ArcSummary.text = "Covered %d / %d   Blind %s" % [
		int(d["covered"]), int(d["total_sectors"]), String(d["blind_label"])]
	$Right/BudgetsPanel/V/ArcSummary.add_theme_color_override("font_color",
		Palette.OK if d["blind"].is_empty() else Palette.CRIT)


func _on_fire(damage: int) -> void:
	var facing: int = $Center/V/Ring.selected_facing
	var bearing: float = Sectors.facing_center_bearing(facing)
	_log("Incoming %d on facing #%d" % [damage, facing + 1], Palette.CYAN)
	var lines: Array[String] = _demo.apply_damage(bearing, float(damage))
	for line in lines:
		var hue: Color = Palette.DIM
		if line.contains("DOWN") or line.contains("DESTROYED"):
			hue = Palette.CRIT
		_log("  " + line, hue)
	_refresh_state_views()


func _log(text: String, hue: Color) -> void:
	$Center/V/Log.push_color(hue)
	$Center/V/Log.add_text(text + "\n")
	$Center/V/Log.pop()
