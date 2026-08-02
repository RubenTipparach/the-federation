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
## The tractor orders. The panel does not know which ship it is drawing, so the
## screen turns each of these into a Battle command (docs/11: one command path).
signal tractor_latch_requested
signal tractor_release_requested
signal tractor_mode_picked(mode: String)
## The player set the tractor bid, in whole reactor units.
signal tractor_bid_picked(units: int)

const REPAIR_JOB := preload("res://scenes/ui/repair_job.tscn")
const ICON_DIR: String = "res://assets/icons/"
const ROW_COUNT: int = 8

var _station: String = ""
var _ship: ShipState = null
var _renderers: Dictionary = {}
var _wired: bool = false

## The battle this ship is in, needed only by the tractor station: a beam is a
## relationship between two ships and neither of them owns it. Left null on any
## screen that has no battle, and the tractor renderer copes.
var battle: Battle = null


func _ready() -> void:
	_renderers = {
		"shields": _render_shields,
		"repair": _render_repair,
		"reactor": _render_reactor,
		"life": _render_life,
		"tractor": _render_tractor,
	}
	if not _wired:
		_wired = true
		$V/Fix.pressed.connect(_on_fix)
		for f in range(Sectors.FACING_COUNT):
			var b: Button = $V/Picker.get_node("P%d" % f)
			b.pressed.connect(_on_pick.bind(f))
		$V/Cmds/Latch.pressed.connect(_on_latch)
		$V/Cmds/Hold.pressed.connect(_on_mode.bind(Tractor.MODE_HOLD))
		$V/Cmds/Reel.pressed.connect(_on_mode.bind(Tractor.MODE_REEL))
		_row(0).get_node("Boxes").level_picked.connect(_on_bid_picked)


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
	# What the station is for lives in a tooltip, not on the panel. A battle
	# screen has no room for prose and a player under fire has no time for it,
	# so the sentence is available on a hover and absent from the layout.
	tooltip_text = String(spec["blurb"])

	# Reset the authored rows, then let the station turn on the ones it wants.
	for i in range(ROW_COUNT):
		_row(i).visible = false
	$V/Picker.visible = false
	$V/Queue.visible = false
	$V/Total.visible = false
	$V/Tug.visible = false
	$V/Cmds.visible = false

	var out: bool = index >= 0 and int(_ship.systems[index]["boxes"]) <= 0
	# One station keeps working with its hardware gone, and it is in the data
	# rather than named here: the tractor's emitter is what latches a ship, and
	# shoving against a beam already on you needs engines, not an emitter.
	var survives: bool = bool(spec.get("survives_box", false))
	var badge: String = "LIVE"
	var badge_tint: Color = Palette.OK
	if out:
		badge = "NO EMITTER" if survives else "OFFLINE"
		badge_tint = Palette.CRIT
	elif not live:
		badge = "DEFERRED"
		badge_tint = Palette.DIM
	$V/Head/Badge.text = badge
	Paint.tint($V/Head/Badge, "font_color", badge_tint)

	# A station whose box is gone shows the box, and nothing it could not
	# actually do. The way back is the repair button, which is the same answer
	# on every station and so lives here rather than in ten places.
	if out and not survives:
		_render_backing(index)
	elif _renderers.has(_station):
		(_renderers[_station] as Callable).call()
	else:
		_render_backing(index)

	_refresh_fix(index)


func _row(i: int) -> HBoxContainer:
	return $V/Rows.get_node("R%d" % i)


## Configure one authored row: a name, a strip of discrete boxes, a number.
## Most rows are readouts, so the strip ignores the mouse. The tractor's bid is
## the exception: it is a control, and it is the same strip rather than a second
## kind of one, because the thing being set is a power sink like any other.
func _paint_row(i: int, label: String, level: int, capacity: int, out: String,
		tint: Color, ceiling: int = -1, clickable: bool = false) -> void:
	var row: HBoxContainer = _row(i)
	row.visible = true
	row.get_node("L").text = label
	row.get_node("Out").text = out
	Paint.tint(row.get_node("Out"), "font_color", tint)
	var boxes: Control = row.get_node("Boxes")
	boxes.setup(tint, clickable)
	boxes.paint(level, maxi(1, capacity), ceiling)
	boxes.mouse_filter = Control.MOUSE_FILTER_STOP if clickable \
		else Control.MOUSE_FILTER_IGNORE


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
		Paint.tint(b, "font_color",
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
		Paint.tint(node.get_node("Line/Cost"), "font_color",
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
		var want_fill: float = maxf(frac, 0.001)
		if not is_equal_approx(fill.anchor_right, want_fill):
			fill.anchor_right = want_fill
		Paint.tint(node.get_node("Line/Code"), "font_color",
			Palette.CYAN if i == 0 else Palette.FG)

	$V/Total.visible = true
	if jobs.is_empty():
		$V/Total.text = "NOTHING QUEUED"
		Paint.tint($V/Total, "font_color", Palette.DIM)
	else:
		var total: int = RepairModel.queue_cost(_ship.systems, jobs, tuning)
		$V/Total.text = "QUEUE %d JOB%s      %d of %d parts" % [
			jobs.size(), "" if jobs.size() == 1 else "S", total, _ship.parts]
		Paint.tint($V/Total, "font_color",
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


## The tractor auction (docs/13 section 6).
##
## Federation Commander does not print its tractor rules and says so, which
## docs/09 section 6 records in full, so the contest below is ours. What the
## panel shows is what the simulation compares: a grip, a shove weighted by
## tonnage, and how long the loser has before the beam gives.
##
## Everything here is discrete or a countdown. The bid is boxes, the contest is
## boxes, the orders are buttons, and the one continuous thing on the panel is
## the strain, which is a clock and not a control (CLAUDE.md 6.2).
func _render_tractor() -> void:
	var tuning: Dictionary = Catalog.tuning()
	# The bid strip is as long as the tug bar below it, not as long as the whole
	# reactor. Sixteen boxes are more bid than any contest needs, and a strip of
	# sixty in this column would be thinner than the gaps between its boxes,
	# which turns discrete boxes back into the bar CLAUDE.md 6.2 banned. What the
	# reactor can actually afford is the ceiling: boxes past it draw as
	# unavailable, so a shot up reactor visibly shortens what you may spend.
	var bid: int = int(roundf(_ship.alloc_units(Tractor.SINK)))
	var span: int = int(tuning["tractor"]["bar_units"])
	var afford: int = mini(span, int(floorf(_ship.power_output())))
	_paint_row(0, "BID", bid, span, "%d u" % bid, Palette.CYAN, afford, true)

	$V/Cmds.visible = true
	var beam: Tractor = battle.tractor_on(_ship) if battle != null else null
	if beam == null:
		_render_tractor_idle(tuning)
	else:
		_render_tractor_contest(beam, tuning)


## Nothing held. The badge carries the reason a latch would be refused, in the
## same words the weapon rows use for a shot that cannot be taken.
func _render_tractor_idle(tuning: Dictionary) -> void:
	var target: ShipState = battle.target_for(_ship) if battle != null else null
	var check: Dictionary = { "ok": false, "reason": "empty" }
	if target != null:
		check = Tractor.latch_check(_ship, target, tuning)
	var ok: bool = bool(check["ok"])
	$V/Head/Badge.text = String(check["reason"]).to_upper()
	Paint.tint($V/Head/Badge, "font_color",
		Palette.OK if ok else Palette.AMBER)
	$V/Cmds/Latch.text = "LATCH"
	$V/Cmds/Latch.disabled = not ok
	for name in ["Hold", "Reel"]:
		var b: Button = $V/Cmds.get_node(name)
		b.disabled = true
		b.button_pressed = false


## A beam is up. The same panel serves both ends of it: the geometry is fixed,
## grip on the left and shove on the right, and the colour says which of them is
## yours (docs/13 section 6.3).
func _render_tractor_contest(beam: Tractor, tuning: Dictionary) -> void:
	var holding: bool = beam.holder == _ship
	var other: ShipState = beam.held if holding else beam.holder
	var grip: float = beam.hold_bid()
	var shove: float = beam.break_bid()
	var mine: Color = Palette.CYAN
	var theirs: Color = Palette.MAGENTA

	$V/Head/Badge.text = "HOLDING" if holding else "UNDER TOW"
	Paint.tint($V/Head/Badge, "font_color",
		Palette.OK if holding == (grip > shove) else Palette.AMBER)

	$V/Tug.visible = true
	$V/Tug/Bar.paint(grip, mine if holding else theirs,
		shove, theirs if holding else mine,
		int(tuning["tractor"]["bar_units"]))
	$V/Tug/Labels/L.text = "YOUR GRIP" if holding else "THEIR GRIP"
	Paint.tint($V/Tug/Labels/L, "font_color", mine if holding else theirs)
	$V/Tug/Labels/R.text = "THEIR SHOVE" if holding else "YOUR SHOVE"
	Paint.tint($V/Tug/Labels/R, "font_color", theirs if holding else mine)

	# The multiplication is printed rather than hidden, because a captain losing
	# to a lighter ship has earned an explanation.
	var ratio: float = Tractor.tonnage(beam.held) / Tractor.tonnage(beam.holder)
	$V/Tug/Reading/L.text = "%.1f grip" % grip
	Paint.tint($V/Tug/Reading/L, "font_color", mine if holding else theirs)
	$V/Tug/Reading/R.text = "%.1f x %.2f = %.1f" % [
		Tractor.bid_of(beam.held), ratio, shove]
	Paint.tint($V/Tug/Reading/R, "font_color", theirs if holding else mine)

	var frac: float = beam.strain_frac(tuning)
	var track: ColorRect = $V/Tug/Strain
	var fill: ColorRect = $V/Tug/Strain/Fill
	track.color = Palette.LINE
	fill.color = Palette.CRIT if frac > 0.6 else Palette.AMBER
	var want_fill: float = maxf(frac, 0.001)
	if not is_equal_approx(fill.anchor_right, want_fill):
		fill.anchor_right = want_fill
	var seconds_left: float = maxf(0.0,
		float(tuning["tractor"]["break_seconds"]) - beam.strain)
	if frac <= 0.0:
		$V/Tug/Note/L.text = "Grip secure"
		Paint.tint($V/Tug/Note/L, "font_color", Palette.DIM)
	elif holding:
		$V/Tug/Note/L.text = "Grip failing in %.1fs" % seconds_left
		Paint.tint($V/Tug/Note/L, "font_color", Palette.AMBER)
	else:
		$V/Tug/Note/L.text = "Breaking free in %.1fs" % seconds_left
		Paint.tint($V/Tug/Note/L, "font_color", Palette.OK)
	$V/Tug/Note/R.text = "%d t against %d t, %s" % [
		int(Tractor.tonnage(beam.held)), int(Tractor.tonnage(beam.holder)),
		"reeling in" if beam.mode == Tractor.MODE_REEL else "holding range"]
	Paint.tint($V/Tug/Note/R, "font_color", Palette.DIM)

	# Only the holder chooses hold or reel. The prisoner does not get a say in
	# whether it is being pulled closer, so those buttons are simply not theirs.
	$V/Cmds/Latch.text = "RELEASE" if holding else "HELD BY %s" % String(
		other.fit.hull()["name"]).to_upper()
	$V/Cmds/Latch.disabled = not holding
	for entry in [["Hold", Tractor.MODE_HOLD], ["Reel", Tractor.MODE_REEL]]:
		var b: Button = $V/Cmds.get_node(String(entry[0]))
		b.disabled = not holding
		b.button_pressed = holding and beam.mode == String(entry[1])


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
	Paint.tint(fix, "font_color", Palette.OK if queued else Palette.AMBER)
	Paint.tint(fix, "font_disabled_color", Palette.OK)


func _on_fix() -> void:
	var index: int = SystemTabs.system_index_for(_station, _ship.systems)
	if index >= 0:
		repair_requested.emit(index)


func _on_pick(facing: int) -> void:
	regen_facing_picked.emit(facing)


## One button for both ends of the beam: latch when nothing is held, release
## when something is. A prisoner's copy is disabled, so this only ever fires for
## the holder or for a ship about to become one.
func _on_latch() -> void:
	if battle != null and battle.tractor_on(_ship) != null:
		tractor_release_requested.emit()
	else:
		tractor_latch_requested.emit()


func _on_mode(mode: String) -> void:
	tractor_mode_picked.emit(mode)


func _on_bid_picked(level: int) -> void:
	if _station == Tractor.SINK:
		tractor_bid_picked.emit(level)


func _on_drop(job: Node) -> void:
	if job.has_meta("system_index"):
		repair_dropped.emit(int(job.get_meta("system_index")))
