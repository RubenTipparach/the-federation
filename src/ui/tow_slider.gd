extends Control

## The tow distance slider: how far out a prize is being held, and where she
## actually is while the beam works her onto it.
##
## Two marks on one track, which is the whole reason this is a slider rather
## than a strip of boxes (the CLAUDE.md section 7 exception). The HANDLE is
## the order. The CARET beneath it is the truth. Reeling in is the caret
## closing on the handle, and paying out is the caret falling behind it, so
## the state of the tow is read from the gap between them with nothing having
## to say it in words.
##
## The track carries the grip falloff as well: bright and tight at the close
## end, washed out at the far end, so the cost of reaching is painted on the
## control that sets it.
##
## Presentation only. The script paints the two fractions it is handed and
## reports where it was dragged; it never reads the simulation and never
## decides what a fraction means in world units, which is the panel's job
## because only the panel knows which beam is on screen.

## The player set the distance, as a unit position along the track. The panel
## turns that into a standoff fraction, because where the track STARTS depends
## on the two hulls and the slider is not told about hulls.
signal distance_picked(unit: float)

const TRACK_H: float = 15.0
const HANDLE_W: float = 9.0
const CARET_H: float = 8.0

var _set: float = 0.5
var _now: float = 0.5
var _live: bool = false


func paint(set_unit: float, now_unit: float, live: bool) -> void:
	var s: float = clampf(set_unit, 0.0, 1.0)
	var n: float = clampf(now_unit, 0.0, 1.0)
	if is_equal_approx(_set, s) and is_equal_approx(_now, n) and _live == live:
		return
	_set = s
	_now = n
	_live = live
	queue_redraw()


## The track, inset by half a handle at each end so the handle at either
## extreme is still drawn inside the control rather than clipped by it.
func _track() -> Rect2:
	return Rect2(HANDLE_W * 0.5, 2.0,
		maxf(1.0, size.x - HANDLE_W), TRACK_H)


func _draw() -> void:
	var t: Rect2 = _track()
	# The falloff, as a wash along the track. Painted in strips rather than as
	# a gradient because there is no gradient primitive here and forty strips
	# on a control this size is one draw call's worth of rectangles.
	var strips: int = 40
	for i in range(strips):
		var f: float = float(i) / float(strips)
		var col: Color = Palette.CYAN.lerp(Palette.PANEL_2, 0.35 + 0.6 * f)
		draw_rect(Rect2(t.position.x + t.size.x * f, t.position.y,
			t.size.x / float(strips) + 1.0, t.size.y), col)
	draw_rect(t, Palette.LINE_HOT, false, 1.0)
	if not _live:
		return
	# Where she actually is.
	var nx: float = t.position.x + t.size.x * _now
	draw_colored_polygon(PackedVector2Array([
		Vector2(nx, t.end.y + 2.0),
		Vector2(nx - 5.0, t.end.y + 2.0 + CARET_H),
		Vector2(nx + 5.0, t.end.y + 2.0 + CARET_H)]), Palette.MAGENTA)
	# What was ordered.
	var sx: float = t.position.x + t.size.x * _set
	var handle: Rect2 = Rect2(sx - HANDLE_W * 0.5, t.position.y - 3.0,
		HANDLE_W, t.size.y + 6.0)
	draw_rect(handle, Palette.CYAN)
	draw_rect(handle, Palette.FG, false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if not _live:
		return
	var held: bool = event is InputEventMouseMotion \
		and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	var clicked: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if not (held or clicked):
		return
	var t: Rect2 = _track()
	distance_picked.emit(
		clampf((event.position.x - t.position.x) / t.size.x, 0.0, 1.0))
	accept_event()
