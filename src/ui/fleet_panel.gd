extends PanelContainer

## The fleet roster: every hull this command owns, one compact row each. A
## row is the ship's builder as a colour chip, her name, her health as a ten
## cell strip with the reading beside it, an ENG OFFLINE flag when she cannot
## move herself, and the wheel that takes her helm. The filled wheel is the
## ship being flown. Berths without a ship say so in one dim line, the one
## line an empty state is allowed (CLAUDE.md 6.5).
##
## The rows are authored in scenes/ui/fleet_panel.tscn, four of them because
## Session.FLEET_MAX is four; this script only paints session.fleet into them
## and reports which wheel was pressed. Captures past the fourth berth stay
## recorded in the session; here the count in the header goes critical, and
## the overflow is the tractor work's problem, not this panel's.
##
## The health strip is the box strip every allocation readout uses
## (CLAUDE.md 4.1), painted read only: ten cells, each a tenth of the hull's
## internal boxes, coloured by the same thresholds the shield readouts use.

signal helm_taken(index: int)

const ROWS: int = 4
## The health strip shows tenths, not boxes: at a glance is the row's job,
## and the exact reading sits beside it.
const CELLS: int = 10

var session: Session


func bind_session(p_session: Session) -> void:
	session = p_session
	for i in range(ROWS):
		_row(i).get_node("Wheel").pressed.connect(_on_wheel.bind(i))
	refresh()


func _row(i: int) -> HBoxContainer:
	return get_node("V/Row%d" % (i + 1))


func refresh() -> void:
	if session == null:
		return
	var count: Label = $V/Head/Count
	count.text = "%d/%d" % [session.fleet.size(), Session.FLEET_MAX]
	Paint.tint(count, "font_color",
		Palette.CRIT if session.fleet.size() > Session.FLEET_MAX else Palette.DIM)
	for i in range(ROWS):
		_paint_row(i)


func _paint_row(i: int) -> void:
	var row: HBoxContainer = _row(i)
	var name_label: Label = row.get_node("Name")
	var manned: bool = i < session.fleet.size()
	for part in ["Chip", "Health", "Num", "Flag", "Wheel"]:
		row.get_node(part).visible = manned
	if not manned:
		name_label.text = "EMPTY BERTH"
		Paint.tint(name_label, "font_color", Palette.PANEL_2)
		return
	var entry: Dictionary = session.fleet[i]
	var at_helm: bool = i == session.helm
	name_label.text = String(entry["name"]).to_upper()
	Paint.tint(name_label, "font_color", Palette.FG if at_helm else Palette.DIM)
	row.get_node("Chip").color = Palette.faction_mark(
		String(Catalog.hull(String(entry["hull_id"]))["faction"]))
	var frac: float = float(entry["hull"]) / maxf(1.0, float(entry["hull_max"]))
	var tone: Color = Palette.shield_color(frac)
	var strip: Control = row.get_node("Health")
	strip.setup(tone)
	# A ship still afloat never reads as zero cells: the numeric beside the
	# strip carries the exactness, the strip carries the glance.
	var lit: int = int(round(frac * CELLS))
	if int(entry["hull"]) > 0:
		lit = maxi(1, lit)
	strip.paint(lit, CELLS)
	var num: Label = row.get_node("Num")
	num.text = "%d/%d" % [int(entry["hull"]), int(entry["hull_max"])]
	Paint.tint(num, "font_color", Palette.DIM if frac >= 1.0 else tone)
	var flag: Label = row.get_node("Flag")
	flag.text = "ENG OFFLINE" if bool(entry["engines_out"]) else ""
	Paint.tint(flag, "font_color", Palette.CRIT)
	var wheel: Button = row.get_node("Wheel")
	# A hull that cannot move itself cannot be flown; her wheel waits on the
	# tow to a yard.
	wheel.disabled = bool(entry["engines_out"])
	# The filled wheel is the ship being flown: the theme's pressed face does
	# the filling, the same way a selected design card shows itself.
	wheel.set_pressed_no_signal(at_helm)
	Paint.button_tint(wheel, Palette.CYAN if at_helm else Palette.DIM)


func _on_wheel(i: int) -> void:
	helm_taken.emit(i)
