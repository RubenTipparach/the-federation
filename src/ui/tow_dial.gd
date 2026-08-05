extends Control

## The tow bearing dial: which way off your own bow you are holding a prize,
## and nothing else.
##
## NORMALIZED, deliberately. The prize is drawn on the rim whatever the real
## range is, so the circle is a compass rather than a map and never has to be
## read as one. How far out she rides is the slider below it, which is a
## better shape for a distance than a radius a captain would have to eyeball.
##
## A painted control in the CLAUDE.md section 7 sense, listed there with the
## slider: its content is the live tow plan against the holder's heading, so
## no static node tree could describe it. The node is authored in
## scenes/ui/tow_dial.tscn; this script paints what it is handed and reports
## where it was clicked, never reading the simulation itself.
##
## Bearings follow Sectors: 000 is dead ahead and increases clockwise, drawn
## with the holder's nose up, because the plan is relative to the hull.

## The player picked a bearing, already snapped. Relative to the holder's nose.
signal bearing_picked(deg: float)

const MARGIN: float = 5.0
## Below this a click is on the ship at the centre rather than on a bearing,
## and picking one from it would be noise: the vector is undefined there.
const DEAD_ZONE: float = 4.0

var _bearing: float = 0.0
var _live: bool = false
var _snap: float = 15.0


## `live` is whether there is a beam to plan for. An idle dial still draws its
## compass, because a station whose instrument vanishes between grapples reads
## as broken hardware.
func paint(bearing_deg: float, live: bool, snap_deg: float) -> void:
	if is_equal_approx(_bearing, bearing_deg) and _live == live \
			and is_equal_approx(_snap, snap_deg):
		return
	_bearing = bearing_deg
	_live = live
	_snap = snap_deg
	queue_redraw()


func _centre() -> Vector2:
	return size * 0.5


func _radius() -> float:
	return maxf(6.0, minf(size.x, size.y) * 0.5 - MARGIN)


## A point on the dial at a bearing, in the screen's own axes: 000 is up and
## bearings run clockwise, which is Sectors' convention drawn.
static func _at(centre: Vector2, radius: float, deg: float) -> Vector2:
	var a: float = deg_to_rad(deg)
	return centre + Vector2(sin(a), -cos(a)) * radius


func _draw() -> void:
	var c: Vector2 = _centre()
	var r: float = _radius()
	draw_arc(c, r, 0.0, TAU, 72, Palette.LINE_HOT, 2.0, true)
	# Twenty four ticks: the twelve sector marks bold and the halves between
	# them faint, because a click snaps to fifteen degrees and the dial should
	# show what it will give you.
	for k in range(24):
		var deg: float = float(k) * 15.0
		var major: bool = k % 2 == 0
		draw_line(_at(c, r - (9.0 if major else 5.0), deg),
			_at(c, r, deg),
			Palette.LINE_HOT if major else Palette.LINE, 2.0 if major else 1.0)
	# The bow mark, so the dial reads as ship relative without a word on it.
	draw_line(_at(c, r - 13.0, 0.0), _at(c, r, 0.0),
		Palette.FG, 3.0)
	_chevron(c, 0.0, 9.0, Palette.CYAN)
	if not _live:
		return
	var p: Vector2 = _at(c, r, _bearing)
	# The beam, dashed, because it is an order rather than a drawn object.
	var steps: int = 9
	for i in range(steps):
		if i % 2 == 1:
			continue
		draw_line(c.lerp(p, float(i) / float(steps)),
			c.lerp(p, float(i + 1) / float(steps)), Palette.CYAN, 2.0)
	draw_arc(p, 8.0, 0.0, TAU, 20, Palette.CYAN, 2.0, true)
	_chevron(p, _bearing + 180.0, 6.5, Palette.MAGENTA)


## A ship, nose along a bearing. The same four point silhouette the tactical
## contact marks use, at whatever size the caller asks for.
func _chevron(at: Vector2, deg: float, scale: float, col: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array()
	for o in [Vector2(0.0, -1.0), Vector2(0.62, 0.75),
			Vector2(0.0, 0.4), Vector2(-0.62, 0.75)]:
		pts.append(at + o.rotated(deg_to_rad(deg)) * scale)
	draw_colored_polygon(pts, col)


func _gui_input(event: InputEvent) -> void:
	if not _live:
		return
	var held: bool = event is InputEventMouseMotion \
		and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0
	var clicked: bool = event is InputEventMouseButton and event.pressed \
		and event.button_index == MOUSE_BUTTON_LEFT
	if not (held or clicked):
		return
	var d: Vector2 = event.position - _centre()
	if d.length() < DEAD_ZONE:
		return
	var deg: float = Sectors.wrap_deg(rad_to_deg(atan2(d.x, -d.y)))
	if _snap > 0.0:
		deg = Sectors.wrap_deg(roundf(deg / _snap) * _snap)
	bearing_picked.emit(deg)
	accept_event()
