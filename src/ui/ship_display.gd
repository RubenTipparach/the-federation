extends HBoxContainer

## The one ship systems display (CLAUDE.md 6.1). It shows what a ship is
## carrying and what state it is in: the six facing shield ring, hull integrity
## in the middle of it, and the subsystem slots beside it.
##
## Callers configure it, they do not rebuild it. What varies is parameters:
##
##   detail  box by box slots, or family totals only
##   editable  slots take clicks, so a repair can be ordered from here
##
## The target's display runs with detail off, because reading an enemy's
## internals box by box is what a sensor lock will buy. Own ship runs with both
## on. Neither is a second component, which is the whole point: two ship
## displays would eventually disagree about what is fitted, and that is the one
## thing a player must always be able to trust.

## A subsystem slot was left clicked. The screen turns this into a command.
signal system_picked(index: int)
## A subsystem slot was right clicked.
signal system_detail(index: int)

const SLOT_COUNT: int = 16
const FAMILIES: PackedStringArray = ["weapon", "power", "control", "hull"]

var _ship: ShipState = null
var _detail: bool = true
var _editable: bool = false
var _bound: bool = false


## Point the display at a ship. Called when the ship changes, not every frame:
## slots are configured here and only painted in refresh().
func bind_ship(ship: ShipState, detail: bool, editable: bool) -> void:
	_ship = ship
	_detail = detail
	_editable = editable
	$Ring.compact = true
	$Side/Slots.visible = detail
	$Side/Families.visible = not detail
	if not $Ring.resized.is_connected(_fit_wire):
		$Ring.resized.connect(_fit_wire)
	if ship == null:
		$Ring/Wire.visible = false
		return
	# Editable means it is the player's own console, which is the same thing as
	# it being the player's own ship, so the outline is friendly. The target's
	# is not, and the two are on screen together.
	$Ring/Wire.visible = true
	$Ring/Wire.show_wireframe(ship.fit.hull(),
		Palette.CYAN if editable else Palette.MAGENTA)
	_fit_wire()
	for i in range(SLOT_COUNT):
		var slot: Node = _slot(i)
		var used: bool = detail and i < ship.systems.size()
		slot.visible = used
		if not used:
			continue
		var sys: Dictionary = ship.systems[i]
		# A slot only reports its index when the display is editable, so the
		# target's display cannot be clicked into ordering repairs on a ship
		# that is not yours.
		slot.build(String(sys["code"]), int(sys["boxes_max"]), String(sys["family"]),
			String(sys["mount_id"]), i if editable else -1)
		slot.mouse_filter = Control.MOUSE_FILTER_STOP if editable \
			else Control.MOUSE_FILTER_IGNORE
		if editable and not _bound:
			slot.picked.connect(system_picked.emit)
			slot.detail_requested.connect(system_detail.emit)
	_bound = editable
	refresh()


## The ring places the wireframe, and does it again whenever the ring changes
## size, because the viewport behind it renders on demand and a resized one
## comes back empty otherwise.
func _fit_wire() -> void:
	# Not the whole space: the hull integrity sits at the foot of the ring and
	# the ship is nudged up off it.
	$Ring.fit_inside($Ring/Wire)
	$Ring/Wire.position.y -= inner_gap()
	$Ring/Wire.request_frame()


## How far up the ship rides to clear the integrity reading under it.
func inner_gap() -> float:
	return $Ring.inner_radius() * 0.20


func _slot(i: int) -> Node:
	return $Side/Slots.get_node("S%d" % i)


## Repaint from the ship. Everything here is a read: the display owns no state
## the sim does not already have.
func refresh() -> void:
	if _ship == null:
		return
	$Ring.show_state(_ship.shields, _ship.shield_max)

	var boxes: int = _ship.total_boxes()
	var boxes_max: int = maxi(1, _ship.total_boxes_max())
	var frac: float = float(boxes) / float(boxes_max)
	$Ring/Hull.text = "%d%%" % int(round(frac * 100.0))
	Paint.tint($Ring/Hull, "font_color",
		Palette.CRIT if frac < 0.4 else (Palette.AMBER if frac < 0.7 else Palette.FG))
	$Ring/Hull.tooltip_text = "%d of %d boxes" % [boxes, boxes_max]

	if _detail:
		for i in range(mini(SLOT_COUNT, _ship.systems.size())):
			var sys: Dictionary = _ship.systems[i]
			var slot: Node = _slot(i)
			slot.set_queued(_ship.repair_queue.has(i))
			slot.paint(int(sys["boxes"]), int(sys["boxes_max"]))
		return

	# Family totals: what you may read off a contact without a sensor lock.
	for f in range(FAMILIES.size()):
		var family: String = String(FAMILIES[f])
		var cur: int = 0
		var top: int = 0
		for sys in _ship.systems:
			if String(sys["family"]) != family:
				continue
			cur += int(sys["boxes"])
			top += int(sys["boxes_max"])
		var label: Label = $Side/Families.get_node("F%d" % f)
		label.visible = top > 0
		label.text = "%s   %d / %d" % [family.to_upper(), cur, top]
		var whole: bool = top > 0 and cur >= top
		Paint.tint(label, "font_color",
			Palette.family_color(family) if whole else (
				Palette.CRIT if cur == 0 else Palette.AMBER))
