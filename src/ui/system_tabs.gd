class_name SystemTabs
extends VBoxContainer

## A strip of subsystem station tabs. The tactical view has two of them: the
## systems a player reaches for under fire sit on the right beside the target,
## and the ship's business sits on the left beside the log. Both are this one
## component with a different side (CLAUDE.md 4.1), so a tab behaves the same
## wherever it is drawn.
##
## A column, sixty pixels wide, standing beside the panel it opens. A tab shows
## its box's icon over a short mark rather than a name, which is what lets the
## strip be this narrow, and the mark is in data/stations.json beside the name
## rather than trimmed from it here.
##
## Every station has an authored button in system_tabs.tscn and a strip shows
## only the ones its side asks for. Nothing is constructed here: this script
## configures authored nodes from data/stations.json and paints their state
## (CLAUDE.md 5.1 and 5.2).
##
## A tab is the console for a box, so it wears that box's committed icon and
## reads that box's health from the same systems array the ship display paints.
## That is what lets a tab go dark when its hardware does: the strip is never
## told a station is out, it looks.

signal tab_selected(id: String)
## The player asked to repair the hardware behind a tab, from the button the
## panel shows when the station is damaged.
signal repair_requested(system_index: int)

const ICON_DIR: String = "res://assets/icons/"

var _ids: PackedStringArray = PackedStringArray()
var _selected: String = ""
## The systems array the last refresh painted from, so a click on a tab's
## repair button can name the box without the strip holding a ship.
var _last_systems: Array[Dictionary] = []


## Show the stations belonging to one side. Called once per screen: which tabs
## a strip carries does not change while a battle runs.
func setup(side: String) -> void:
	_ids = Catalog.station_ids(side)
	for child in get_children():
		var id: String = String(child.name)
		var wanted: bool = _ids.has(id)
		child.visible = wanted
		if not wanted:
			continue
		var spec: Dictionary = Catalog.station(id)
		var b: Button = child
		# The mark, not the name. Sixty pixels does not hold "Shields", and a
		# name trimmed to fit would put the same four letters there by accident
		# rather than by a decision recorded in the data file.
		b.get_node("Stack/Mark").text = String(spec["mark"])
		var path: String = ICON_DIR + String(spec["icon"]) + ".png"
		var icon: TextureRect = b.get_node("Stack/Icon")
		icon.texture = load(path) if ResourceLoader.exists(path) else null
		if not b.pressed.is_connected(_on_pressed):
			b.pressed.connect(_on_pressed.bind(id))
			b.get_node("Fix").pressed.connect(_on_fix.bind(id))
	if not _ids.is_empty():
		select(String(_ids[0]))


func select(id: String) -> void:
	if not _ids.has(id):
		return
	_selected = id
	for child in get_children():
		(child as Button).button_pressed = String(child.name) == id
	tab_selected.emit(id)


func selected() -> String:
	return _selected


func _on_fix(id: String) -> void:
	# The strip does not know the ship, so it reports the index and the screen
	# turns that into a command. Resolved against the systems the last refresh
	# saw, which is the same array the screen will command against.
	if _last_systems.is_empty():
		return
	var index: int = system_index_for(id, _last_systems)
	if index >= 0:
		repair_requested.emit(index)


func _on_pressed(id: String) -> void:
	var b: Button = get_node(NodePath(id))
	# A station whose hardware is gone cannot be opened. Godot has already
	# toggled the button by the time this runs, so the strip is repainted to
	# put it back rather than the click being swallowed silently.
	if b.disabled:
		select(_selected)
		return
	select(id)


## Which system a station speaks for, or -1 for one that speaks for no single
## box. Matching by code lets the ship data decide, so a hull carrying no
## laboratory simply has a station with nothing to knock out, rather than
## needing a second table here that has to be kept in step.
static func system_index_for(id: String, systems: Array[Dictionary]) -> int:
	var code: String = String(Catalog.station(id)["code"])
	if code.is_empty():
		return -1
	for i in range(systems.size()):
		if String(systems[i]["code"]) == code:
			return i
	return -1


## Repaint every visible tab from the ship. A tab is dimmed when its station is
## not yet wired, and disabled when the box behind it is out, because a console
## with no hardware on the other end should not take a click and do nothing.
func refresh(systems: Array[Dictionary], queue: Array[int]) -> void:
	_last_systems = systems
	for id in _ids:
		var key: String = String(id)
		var b: Button = get_node(NodePath(key))
		var spec: Dictionary = Catalog.station(key)
		var live: bool = bool(spec["live"])
		var index: int = system_index_for(key, systems)
		var boxes: int = -1
		var boxes_max: int = -1
		if index >= 0:
			boxes = int(systems[index]["boxes"])
			boxes_max = int(systems[index]["boxes_max"])
		var out: bool = index >= 0 and boxes <= 0
		var hurt: bool = index >= 0 and boxes > 0 and boxes < boxes_max
		var queued: bool = index >= 0 and queue.has(index)

		# A dark console usually cannot be opened, because there is nothing on
		# the other end of it. One station in the data says otherwise: the
		# tractor still lets a prisoner shove with its emitter shot away, so its
		# tab wears the repair chip without being locked out.
		b.disabled = out and not bool(spec.get("survives_box", false))
		var tint: Color = Palette.DIM
		if out:
			tint = Palette.CRIT
		elif hurt:
			tint = Palette.AMBER
		elif not live:
			tint = Palette.with_alpha(Palette.DIM, 0.5)
		elif key == _selected:
			tint = Palette.CYAN
		# The icon and the mark are painted together, never one without the
		# other: a glyph saying the box is dead over a mark saying it is fine
		# is the one state a tab must not be able to reach.
		Paint.stencil(b.get_node("Stack/Icon"), b.get_node("Stack/Mark"), tint)

		# A dark station cannot be opened, so the way to fix it lives on the
		# outside of the tab. Shown whenever the box has lost anything, not
		# only when it is gone, because a degraded station is worth fixing
		# before it becomes a dark one.
		var fix: Button = b.get_node("Fix")
		fix.visible = index >= 0 and (out or hurt)
		if fix.visible:
			var tuning: Dictionary = Catalog.tuning()
			var cost: int = RepairModel.job_cost(systems[index], tuning)
			fix.disabled = queued
			fix.modulate = Palette.OK if queued else Palette.AMBER
			fix.tooltip_text = "%s already queued" % String(spec["code"]) if queued \
				else "Queue %s for repair, %d parts" % [String(spec["code"]), cost]

		var note: String = ""
		if out:
			note = "\n%s is out. Repair it to use this station." % String(spec["code"])
		elif hurt:
			note = "\n%s at %d of %d boxes" % [String(spec["code"]), boxes, boxes_max]
		elif not live:
			note = "\nnot yet wired"
		if queued:
			note += "\nqueued for repair"
		b.tooltip_text = String(spec["label"]) + note
