extends PanelContainer

## The body of whichever subsystem station is open. One panel serves all ten
## stations: it shows and configures the rows authored in subsystem_panel.tscn
## rather than building any, and it holds no rules. Everything it draws comes
## from the ship, and everything it does goes back through Battle.apply_command
## so a replay sees it (CLAUDE.md 5.2).
##
## Station specific rendering is a table of Callables rather than a switch, so
## wiring a deferred station is adding an entry and not editing the middle of
## a growing branch (CLAUDE.md 4.2, open closed).

## The player wants this system repaired. The screen owns the command, because
## the panel has no idea which ship it is drawing.
signal repair_requested(system_index: int)
## The player picked which shield the regeneration energy buys for.
signal regen_facing_picked(facing: int)
## The player took a job off the repair queue.
signal repair_dropped(system_index: int)

const REPAIR_JOB := preload("res://scenes/ui/repair_job.tscn")
const ICON_DIR: String = "res://assets/icons/"
const ROW_COUNT: int = 8

var _station: String = ""
var _ship: ShipState = null
var _renderers: Dictionary = {}
var _wired: bool = false


func _ready() -> void:
	_renderers = {
		"shields": _render_shields,
		"repair": _render_repair,
		"reactor": _render_reactor,
		"life": _render_life,
	}
	if not _wired:
		_wired = true
		$V/Fix.pressed.connect(_on_fix)
		for f in range(Sectors.FACING_COUNT):
			var b: Button = $V/Picker.get_node("P%d" % f)
			b.pressed.connect(_on_pick.bind(f))


func show_station(id: String, ship: ShipState) -> void:
	_station = id
	_ship = ship
	refresh()


## Repaint. Called every frame the panel is visible, so a repair finishing is
## seen without anything having to announce it.
func refresh() -> void:
	if _ship == null or _station.is_empty():
		return
	var spec: Dictionary = Catalog.station(_station)
	var live: bool = bool(spec["live"])
	var index: int = SystemTabs.system_index_for(_station, _ship.systems)

	$V/Head/Title.text = String(spec["label"]).to_upper()
	$V/Blurb.text = String(spec["blurb"])
	$V/Blurb.add_theme_color_override("font_color", Palette.DIM)

	# Reset the authored rows, then let the station turn on the ones it wants.
	for i in range(ROW_COUNT):
		_row(i).visible = false
	$V/Picker.visible = false
	$V/Queue.visible = false
	$V/Total.visible = false

	var out: bool = index >= 0 and int(_ship.systems[index]["boxes"]) <= 0
	var badge: String = "LIVE"
	var badge_tint: Color = Palette.OK
	if out:
		badge = "OFFLINE"
		badge_tint = Palette.CRIT
	elif not live:
		badge = "DEFERRED"
		badge_tint = Palette.DIM
	$V/Head/Badge.text = badge
	$V/Head/Badge.add_theme_color_override("font_color", badge_tint)

	# A station whose box is gone shows the box, and nothing it could not
	# actually do. The way back is the repair button, which is the same answer
	# on every station and so lives here rather than in ten places.
	if out:
		_render_backing(index)
	elif _renderers.has(_station):
		(_renderers[_station] as Callable).call()
	else:
		_render_backing(index)

	_refresh_fix(index)


func _row(i: int) -> HBoxContainer:
	return $V/Rows.get_node("R%d" % i)


## Configure one authored row: a name, a strip of discrete boxes, a number.
func _paint_row(i: int, label: String, level: int, capacity: int, out: String,
		tint: Color, ceiling: int = -1) -> void:
	var row: HBoxContainer = _row(i)
	row.visible = true
	row.get_node("L").text = label
	row.get_node("Out").text = out
	row.get_node("Out").add_theme_color_override("font_color", tint)
	var boxes: Control = row.get_node("Boxes")
	boxes.setup(tint)
	boxes.paint(level, maxi(1, capacity), ceiling)
	boxes.mouse_filter = Control.MOUSE_FILTER_IGNORE


## The health of the box a station speaks for. Every station that has one shows
## this, so "why is this dark" is answered in the panel and not only in a
## tooltip on the tab.
func _render_backing(index: int) -> void:
	if index < 0:
		return
	var sys: Dictionary = _ship.systems[index]
	var boxes: int = int(sys["boxes"])
	var boxes_max: int = int(sys["boxes_max"])
	var tint: Color = Palette.CRIT if boxes <= 0 else (
		Palette.AMBER if boxes < boxes_max else Palette.family_color(String(sys["family"])))
	_paint_row(0, String(sys["code"]), boxes, boxes_max,
		"%d/%d" % [boxes, boxes_max], tint)


# ---- the wired stations ------------------------------------------------------

## Federation Commander 3C7: energy buys shield boxes, one shield at a time.
## The six facings, then the picker that says which one is being bought for.
func _render_shields() -> void:
	for f in range(Sectors.FACING_COUNT):
		var cur: int = int(_ship.shields[f])
		var top: int = int(_ship.shield_max)
		_paint_row(f, "#%d" % (f + 1), cur, top, "%d/%d" % [cur, top],
			Palette.shield_color(float(cur) / maxf(1.0, float(top))))
	var reinf: int = 1 if _ship.battery >= 1.0 else 0
	_paint_row(6, "REINF", reinf, 1, "%d PT" % reinf, Palette.BLUE)
	$V/Picker.visible = true
	for f in range(Sectors.FACING_COUNT):
		var b: Button = $V/Picker.get_node("P%d" % f)
		b.button_pressed = _ship.shield_bias == f
		b.disabled = _ship.shields[f] >= _ship.shield_max
		b.add_theme_color_override("font_color",
			Palette.CYAN if _ship.shield_bias == f else Palette.DIM)


## The parts hold, the damage control parties, and the whole queue in the order
## it will be worked. Only the head job carries a progress track, because 5G4
## finishes a box before work moves anywhere else.
func _render_repair() -> void:
	var tuning: Dictionary = Catalog.tuning()
	_paint_row(0, "PARTS", _ship.parts, maxi(1, _ship.parts_max),
		"%d/%d" % [_ship.parts, _ship.parts_max],
		Palette.AMBER if _ship.parts * 4 < _ship.parts_max else Palette.SLATE)
	_paint_row(1, "CREWS", _ship.damage_control, maxi(1, _ship.damage_control),
		"%d CREW" % _ship.damage_control,
		Palette.AMBER)

	$V/Queue.visible = true
	var jobs: Array[int] = _ship.repair_queue
	while $V/Queue.get_child_count() > jobs.size():
		var extra: Node = $V/Queue.get_child($V/Queue.get_child_count() - 1)
		$V/Queue.remove_child(extra)
		extra.queue_free()
	while $V/Queue.get_child_count() < jobs.size():
		var job: Node = REPAIR_JOB.instantiate()
		$V/Queue.add_child(job)
		job.get_node("Line/Drop").pressed.connect(_on_drop.bind(job))

	var spent_before: int = 0
	for i in range(jobs.size()):
		var index: int = jobs[i]
		var sys: Dictionary = _ship.systems[index]
		var node: Node = $V/Queue.get_child(i)
		node.set_meta("system_index", index)
		var cost: int = RepairModel.job_cost(sys, tuning)
		var affordable: bool = spent_before + cost <= _ship.parts
		spent_before += cost
		node.get_node("Line/Ord").text = str(i + 1)
		node.get_node("Line/Code").text = String(sys["code"])
		node.get_node("Line/Where").text = "core" if int(sys["sector"]) < 0 \
			else "#%d" % (int(sys["sector"]) + 1)
		node.get_node("Line/Cost").text = "%d p" % cost
		node.get_node("Line/Cost").add_theme_color_override("font_color",
			Palette.DIM if affordable else Palette.AMBER)
		var icon_path: String = ICON_DIR + String(sys["code"]).to_lower().replace("-", "") + ".png"
		var icon: TextureRect = node.get_node("Line/Icon")
		icon.texture = load(icon_path) if ResourceLoader.exists(icon_path) else null
		icon.modulate = Palette.family_color(String(sys["family"]))
		# Only the head is under way, so only the head's track fills.
		var track: ColorRect = node.get_node("Track")
		var fill: ColorRect = node.get_node("Track/Fill")
		track.color = Palette.with_alpha(Palette.LINE, 0.9)
		var frac: float = 0.0
		if i == 0:
			var needed: float = RepairModel.seconds_per_box(
				String(sys["family"]), tuning)
			frac = clampf(_ship.repair_progress / maxf(0.001, needed), 0.0, 1.0)
		fill.color = Palette.with_alpha(Palette.CYAN, 1.0 if i == 0 else 0.0)
		fill.anchor_right = maxf(frac, 0.001)
		node.get_node("Line/Code").add_theme_color_override("font_color",
			Palette.CYAN if i == 0 else Palette.FG)

	$V/Total.visible = true
	if jobs.is_empty():
		$V/Total.text = "Nothing queued. Click a damaged system on the ship display."
		$V/Total.add_theme_color_override("font_color", Palette.DIM)
	else:
		var total: int = RepairModel.queue_cost(_ship.systems, jobs, tuning)
		$V/Total.text = "QUEUE %d JOB%s      %d of %d parts" % [
			jobs.size(), "" if jobs.size() == 1 else "S", total, _ship.parts]
		$V/Total.add_theme_color_override("font_color",
			Palette.AMBER if total > _ship.parts else Palette.DIM)


## What the reactor is actually putting out, and the boxes producing it. Fuel,
## coolant and the overload are drawn in the mockup but have no sim behind them
## yet, so they are not drawn here: a control that does nothing is worse than
## one that is missing.
func _render_reactor() -> void:
	var row: int = 0
	for i in range(_ship.systems.size()):
		var sys: Dictionary = _ship.systems[i]
		if String(sys["family"]) != "power" or row >= ROW_COUNT - 1:
			continue
		var boxes: int = int(sys["boxes"])
		var boxes_max: int = int(sys["boxes_max"])
		var tint: Color = Palette.CRIT if boxes <= 0 else (
			Palette.AMBER if boxes < boxes_max else Palette.BLUE)
		_paint_row(row, String(sys["code"]), boxes, boxes_max,
			"%d/%d" % [boxes, boxes_max], tint)
		row += 1
	var out: int = int(round(_ship.power_output()))
	var top: int = int(_ship.fit.hull()["budgets"]["power"])
	_paint_row(row, "OUTPUT", out, maxi(1, top), "%d/%d" % [out, top],
		Palette.AMBER if out * 2 < top else Palette.BLUE)


## Crew aboard and the control boxes that keep them alive. Casualties and the
## officer roster are in the mockup and not in the sim, so they are not faked.
func _render_life() -> void:
	var crew: int = int(_ship.fit.hull()["budgets"]["crew"])
	_paint_row(0, "CREW", crew, maxi(1, crew), "%d aboard" % crew, Palette.CYAN)
	var row: int = 1
	for i in range(_ship.systems.size()):
		var sys: Dictionary = _ship.systems[i]
		if String(sys["family"]) != "control" or row >= ROW_COUNT:
			continue
		var boxes: int = int(sys["boxes"])
		var boxes_max: int = int(sys["boxes_max"])
		var tint: Color = Palette.CRIT if boxes <= 0 else (
			Palette.AMBER if boxes < boxes_max else Palette.family_color("control"))
		_paint_row(row, String(sys["code"]), boxes, boxes_max,
			"%d/%d" % [boxes, boxes_max], tint)
		row += 1


# ---- repair affordance -------------------------------------------------------

## The button that answers a dark console. Shown whenever the box behind the
## open station has lost anything, hidden when there is nothing to fix or no
## box to fix, and disabled once the job is already on the list.
func _refresh_fix(index: int) -> void:
	var fix: Button = $V/Fix
	if index < 0 or not RepairModel.repairable(_ship.systems[index], Catalog.tuning()):
		fix.visible = false
		return
	fix.visible = true
	var queued: bool = _ship.repair_queue.has(index)
	var cost: int = RepairModel.job_cost(_ship.systems[index], Catalog.tuning())
	fix.disabled = queued
	fix.text = "QUEUED FOR REPAIR" if queued else "QUEUE REPAIR   %d PARTS" % cost
	fix.add_theme_color_override("font_color", Palette.OK if queued else Palette.AMBER)
	fix.add_theme_color_override("font_disabled_color", Palette.OK)


func _on_fix() -> void:
	var index: int = SystemTabs.system_index_for(_station, _ship.systems)
	if index >= 0:
		repair_requested.emit(index)


func _on_pick(facing: int) -> void:
	regen_facing_picked.emit(facing)


func _on_drop(job: Node) -> void:
	if job.has_meta("system_index"):
		repair_dropped.emit(int(job.get_meta("system_index")))
