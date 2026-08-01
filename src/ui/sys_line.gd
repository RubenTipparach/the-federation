extends VBoxContainer

## One subsystem slot on the ship systems display: an icon and a health bar,
## nothing else. The SSD is a fitting view, so a section's slots should read at
## a glance; the code, the box count, and the mount live in the tooltip for
## when the player wants them, and the per hit point boxes belong to the combat
## view where they are what is being watched.
##
## Icons are committed .png masks (CLAUDE.md 3) tinted here with the family
## colour the rest of the UI uses, so one file serves every damage state.
##
## The same slot is used in the tactical view, where it is also how a repair is
## ordered: left click queues the system, right click asks what losing it
## costs. The fitting screen simply does not connect those signals, which is
## what section 6.1 means by callers configuring the component rather than
## building a second one.

## Left clicked. The listener decides what that means; the slot knows only
## which system it is drawing.
signal picked(index: int)
## Right clicked, meaning "tell me what losing this costs me".
signal detail_requested(index: int)

const ICON_DIR: String = "res://assets/icons/"

var _family: String = "hull"
var _code: String = ""
var _mount: String = ""
## Where this system sits in ShipState.systems. Set by the display that owns
## the slot, so a click can be reported without the slot knowing the ship.
var _index: int = -1
## Already in the repair queue. Drawn differently because a second click on a
## queued system should read as "already ordered" rather than as nothing.
var _queued: bool = false


## Called when the fit changes: load the mask and write the tooltip once.
func build(code: String, boxes_max: int, family: String, mount_id: String = "",
		index: int = -1) -> void:
	_family = family
	_code = code
	_mount = mount_id
	_index = index
	var path: String = ICON_DIR + code.to_lower().replace("-", "") + ".png"
	$Icon.texture = load(path) if ResourceLoader.exists(path) else null
	_write_tooltip(boxes_max, boxes_max)


## Mark the slot as queued for repair. Presentation only: the queue lives in
## ShipState and this is told what that queue says.
func set_queued(queued: bool) -> void:
	_queued = queued


func paint(cur: int, boxes_max: int) -> void:
	var frac: float = 0.0 if boxes_max <= 0 else float(cur) / float(boxes_max)
	var dead: bool = cur <= 0
	var hurt: bool = frac < 1.0 and not dead
	var hue: Color = Palette.CRIT if dead else (
		Palette.AMBER if hurt else Palette.family_color(_family))
	$Icon.modulate = Palette.with_alpha(Palette.CRIT, 0.4) if dead else hue
	# The bar is the glance: a track that keeps the slot's width, and a fill
	# anchored to its left edge. Scaling the bar instead would drift the slot
	# off centre, because a scaled Control still lays out at its full size.
	# A queued repair shows in the TRACK rather than the fill, so the slot still
	# says how hurt the system is as well as that help is on the way.
	$Health.color = Palette.with_alpha(Palette.OK if _queued else Palette.LINE, 0.9)
	var fill: ColorRect = $Health/Fill
	fill.color = Palette.with_alpha(hue, 0.35 if dead else 1.0)
	fill.anchor_right = 1.0 if dead else clampf(frac, 0.06, 1.0)
	_write_tooltip(cur, boxes_max)


func _write_tooltip(cur: int, boxes_max: int) -> void:
	tooltip_text = "%s   %d / %d boxes%s%s" % [
		_code, cur, boxes_max, "" if _mount.is_empty() else "   mount " + _mount,
		"\nqueued for repair" if _queued else ""]


func _gui_input(event: InputEvent) -> void:
	if _index < 0 or not (event is InputEventMouseButton) or not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_LEFT:
		picked.emit(_index)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_RIGHT:
		detail_requested.emit(_index)
		accept_event()
