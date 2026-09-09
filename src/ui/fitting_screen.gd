extends HBoxContainer

## The fitting screen: pick a hull, fit weapons into its mounts, watch the
## four budgets, and dry fire the damage model against the design. Thin
## wiring only (CLAUDE.md 5.2): every number shown here is computed by the sim
## library, and the dry dock demo runs the same ShipState.apply_damage that a
## real battle uses.

signal design_changed
## A saved design was loaded. Reported rather than applied, because it replaces
## the hull as well as the loadout and main owns the session and the three other
## screens that have to repaint (CLAUDE.md 4.2).
signal design_chosen(fit: ShipFit)

const SELECT_CARD := preload("res://scenes/ui/select_card.tscn")
const SECTOR_PANEL := preload("res://scenes/ui/sector_panel.tscn")

## How far out along a facing's bearing a sector panel sits, as a fraction of
## the shield band's inner radius. Presentation, so it lives here rather than
## in tuning.json, but it is the one place the number appears.
const PLATE_RING_FRAC: float = 0.62
const MOUNT_ITEM := preload("res://scenes/ui/mount_fit_item.tscn")

var session: Session
var _demo: ShipState
var _wired: bool = false
var _panels: Array = []  # six facings then the hull core, index is the sector
## The saved design the display is currently showing, or empty when the fit was
## built from a hull rather than loaded from disk. Only that one can be
## discarded, and only while its file is still there and still names the hull
## on screen, which is what _validate_loaded checks.
var _loaded_path: String = ""


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
	$Center/V/Ring.resized.connect(_layout_plate)
	$Left/DesignsPanel/V/Save.pressed.connect(_on_save_design)
	$Center/V/Head/Discard.pressed.connect(_on_discard_design)


func refresh_from_session() -> void:
	_validate_loaded()
	_build_hull_list()
	_build_design_list()
	_rebuild_all()


## Forget the loaded design when it stops being the one on screen. Checked
## against the file rather than tracked through every path that could change
## the fit, because those paths are in four screens and one of them will be
## added without this being remembered.
func _validate_loaded() -> void:
	if not _loaded_path.is_empty():
		var saved: ShipFit = DesignStore.read(_loaded_path)
		if saved == null or saved.hull_id != session.fit.hull_id:
			_loaded_path = ""
	# Outside the branch on purpose: this also runs after a discard, when the
	# path has just been cleared and the button has to go dark with it.
	$Center/V/Head/Discard.disabled = _loaded_path.is_empty()


## Every saved design, newest first. Choosing one loads it and marks it, which
## is what arms the discard button on the display. The store is DesignStore,
## which a headless tool can read the same files through.
func _build_design_list() -> void:
	var list: VBoxContainer = $Left/DesignsPanel/V/Scroll/DesignList
	for child in list.get_children():
		child.queue_free()
	var shown: int = 0
	for path in DesignStore.list_paths():
		var fit: ShipFit = DesignStore.read(path)
		if fit == null:
			continue
		var card: Button = SELECT_CARD.instantiate()
		list.add_child(card)
		card.setup(path, String(fit.hull()["name"]), DesignStore.describe(fit),
			Palette.AMBER)
		card.button_pressed = path == _loaded_path
		card.chosen.connect(_on_design_card.bind(path, fit))
		shown += 1
	$Left/DesignsPanel/V/Empty.visible = shown == 0


## Loading a design is also what puts it under the discard button, so the
## button always throws away the thing the display is showing.
func _on_design_card(_id: String, path: String, fit: ShipFit) -> void:
	_loaded_path = path
	design_chosen.emit(fit)


func _on_save_design() -> void:
	_loaded_path = DesignStore.save(session.fit,
		int(Time.get_unix_time_from_system()))
	_validate_loaded()
	_build_design_list()


func _on_discard_design() -> void:
	if _loaded_path.is_empty():
		return
	DesignStore.remove(_loaded_path)
	_loaded_path = ""
	_validate_loaded()
	_build_design_list()


## The hulls a design can be built on, by navy and up the class ladder.
##
## The grouping and the order are HullList's, which is the skirmish screen's
## list too: two pickers of the same fleet that disagreed about what order it
## goes in would be exactly the divergence CLAUDE.md 4.1 is about, and a player
## reads that order across screens without thinking about it.
func _build_hull_list() -> void:
	HullList.fill($Left/HullPanel/V/Scroll/HullList,
		Catalog.playable_hull_ids(), _paint_hull)


## What a hull card says here: the class, the weight and how many guns it can
## carry, which is what a hull is being chosen ON in this screen. The skirmish
## screen's card says something else, which is why painting is the caller's.
func _paint_hull(card: Button, hull_id: String) -> void:
	var h: Dictionary = Catalog.hull(hull_id)
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


func _rebuild_internals() -> void:
	# The plate: one panel per shield facing arranged around the ring in the
	# ship's own geometry, plus the hull core in the middle. Panels are
	# instances of a committed scene dropped into anchors authored in
	# fitting.tscn, so nothing here builds a node tree (CLAUDE.md 5.1).
	var ring: Control = $Center/V/Ring
	for panel in _panels:
		panel.queue_free()
	_panels = []
	for sector in range(Sectors.FACING_COUNT + 1):
		var is_core: bool = sector == Sectors.FACING_COUNT
		var panel: PanelContainer = SECTOR_PANEL.instantiate()
		ring.add_child(panel)
		panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
		var key: int = ShipState.CORE if is_core else sector
		panel.build(
			"CORE" if is_core else Sectors.facing_mark(sector),
			"Hull core" if is_core else Sectors.facing_name(sector),
			"no shield" if is_core else Sectors.facing_arc_label(sector),
			_demo.systems_in(key))
		_panels.append(panel)
	$Center/V/Ring/HullView.show_hull(session.fit.hull())
	_layout_plate.call_deferred()


## Place each sector panel on the part of the ship it describes: at its
## facing's centre bearing, inside the shield band, using the ring's own
## geometry so a panel can never overlap a shield. The core sits amidships.
## Called on every resize because the ring's radius follows the control.
func _layout_plate() -> void:
	if _panels.is_empty():
		return
	var ring: Control = $Center/V/Ring
	var centre: Vector2 = ring.centre()
	var r: float = ring.inner_radius()
	var hull_view: Control = ring.get_node("HullView")
	# The ship fills the space inside the shields. The ring places it, because
	# the ring is what knows where its shields are.
	ring.fit_inside(hull_view)
	hull_view.request_frame()
	for sector in range(_panels.size()):
		var panel: Control = _panels[sector]
		panel.size = panel.get_combined_minimum_size()
		var offset: Vector2 = Vector2.ZERO
		if sector < Sectors.FACING_COUNT:
			var bearing: float = Sectors.facing_center_bearing(sector)
			var dir: Vector2 = Vector2(sin(deg_to_rad(bearing)), -cos(deg_to_rad(bearing)))
			offset = dir * r * PLATE_RING_FRAC
		panel.position = centre + offset - panel.size * 0.5


func _on_ring_resized() -> void:
	_layout_plate()


func _refresh_state_views() -> void:
	$Center/V/Ring.show_state(_demo.shields, _demo.shield_max)
	for sector in range(_panels.size()):
		var is_core: bool = sector == Sectors.FACING_COUNT
		_panels[sector].refresh(
			0.0 if is_core else _demo.shields[sector], _demo.shield_max, not is_core)
	$Center/V/Head/Title.text = "SHIP SYSTEM DISPLAY  %s" % String(
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
	Paint.tint($Right/BudgetsPanel/V/ArcSummary, "font_color",
		Palette.OK if d["blind"].is_empty() else Palette.CRIT)


## The dry dock still fires: the shot resolves through the same damage model a
## battle uses, and the SSD repaints to show what it did. What it no longer
## does is narrate. Narration is a combat instrument (CLAUDE.md 6.3), and out
## of a battle there is no stream of events to follow, so the panel that used
## to accumulate lines here is gone.
##
## The sim still RETURNS its log lines. They are ignored here rather than
## removed at the source, because removing them would force the combat screen
## to rebuild the same strings from raw fields, which is the duplication
## CLAUDE.md 4.1 forbids. Fix the consumer, not the producer.
func _on_fire(damage: int) -> void:
	var facing: int = $Center/V/Ring.selected_facing
	var bearing: float = Sectors.facing_center_bearing(facing)
	_demo.apply_damage(bearing, float(damage))
	_refresh_state_views()
