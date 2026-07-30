extends HBoxContainer

## The fitting screen: pick a hull, fit weapons into its mounts, watch the
## four budgets, and dry fire the damage model against the design. Thin
## wiring only (CLAUDE.md 5.2): every number shown here is computed by the sim
## library, and the dry dock demo runs the same ShipState.apply_damage that a
## real battle uses.

signal design_changed

const SELECT_CARD := preload("res://scenes/ui/select_card.tscn")
const SYS_BOX := preload("res://scenes/ui/sys_box.tscn")
const SYS_ROW := preload("res://scenes/ui/sys_row.tscn")
const MOUNT_ITEM := preload("res://scenes/ui/mount_fit_item.tscn")

var session: Session
var _demo: ShipState
var _wired: bool = false
var _boxes: Array = []  # index aligned with _demo.systems


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
	var grid: VBoxContainer = $Center/V/Ring/InternalsAnchor/Internals
	for child in grid.get_children():
		child.queue_free()
	_boxes = []
	var row_nodes: Dictionary = {}
	for sys in _demo.systems:
		var row: int = int(sys["row"])
		if not row_nodes.has(row):
			var row_node: HBoxContainer = SYS_ROW.instantiate()
			grid.add_child(row_node)
			row_nodes[row] = row_node
		var box: Panel = SYS_BOX.instantiate()
		row_nodes[row].add_child(box)
		_boxes.append(box)


func _refresh_state_views() -> void:
	$Center/V/Ring.show_state(_demo.shields, _demo.shield_max)
	for i in range(_demo.systems.size()):
		var sys: Dictionary = _demo.systems[i]
		_boxes[i].paint(String(sys["code"]), int(sys["boxes"]),
			int(sys["boxes_max"]), String(sys["family"]))
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
