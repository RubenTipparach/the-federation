class_name SsdRingControl
extends Control

## The six facing shield ring of the Ship System Display. A thin data driven
## chart: the node is authored in the scene, this script only paints the state
## it is handed and reports which facing was clicked. All rules live in the
## sim (CLAUDE.md 5.2); this file may not contain gameplay math beyond the
## geometry needed to draw and hit test.

signal facing_selected(facing: int)

var selected_facing: int = 0

## Small enough that the per facing strength text would not fit outside the
## ring. The tactical view draws this at 124 pixels and lists the same numbers
## on the shields station, so the text is dropped rather than shrunk into
## illegibility. The fitting screen draws it at 660 and keeps them.
var compact: bool = false

var _shields: Array[float] = []
var _shield_max: float = 1.0


func show_state(shields: Array[float], shield_max: float) -> void:
	_shields = shields.duplicate()
	_shield_max = maxf(shield_max, 0.001)
	queue_redraw()


func _outer_radius() -> float:
	return minf(size.x, size.y) * 0.48


## The inner edge of the shield band. Anything belonging to the ship rather
## than to a shield belongs inside this, which is what the sector panels and
## the hull view are placed against, so nothing ever sits on top of a shield.
func inner_radius() -> float:
	return _outer_radius() * 0.82


func centre() -> Vector2:
	return size * 0.5


func _draw() -> void:
	if _shields.is_empty():
		return
	var center: Vector2 = size * 0.5
	var r_out: float = _outer_radius()
	var r_in: float = r_out * 0.82
	var font: Font = get_theme_default_font()

	for f in range(Sectors.FACING_COUNT):
		# Facing f spans bearings f*60 - 30 to f*60 + 30, with a small gap so
		# six bands read as six. Bearing b maps to screen dir (sin b, -cos b)
		# so that bearing 000 is up.
		var frac: float = _shields[f] / _shield_max
		var a0: float = deg_to_rad(f * 60.0 - 26.0)
		var a1: float = deg_to_rad(f * 60.0 + 26.0)
		var points: PackedVector2Array = PackedVector2Array()
		var steps: int = 10
		for i in range(steps + 1):
			var a: float = lerpf(a0, a1, float(i) / steps)
			points.append(center + Vector2(sin(a), -cos(a)) * r_out)
		for i in range(steps + 1):
			var a: float = lerpf(a1, a0, float(i) / steps)
			points.append(center + Vector2(sin(a), -cos(a)) * r_in)
		var hue: Color = Palette.shield_color(frac)
		var fill_alpha: float = 0.14 if frac <= 0.0 else 0.18 + 0.32 * frac
		draw_colored_polygon(points, Palette.with_alpha(hue, fill_alpha))
		var edge: Color = Palette.CYAN if f == selected_facing else Palette.with_alpha(hue, 0.8)
		draw_polyline(points + PackedVector2Array([points[0]]), edge,
			2.5 if f == selected_facing else 1.2)

		var mid: float = deg_to_rad(f * 60.0)
		var label_pos: Vector2 = center + Vector2(sin(mid), -cos(mid)) * ((r_out + r_in) * 0.5)
		draw_string(font, label_pos + Vector2(-10, 4), "#%d" % (f + 1),
			HORIZONTAL_ALIGNMENT_CENTER, 22, 9 if compact else 12,
			Palette.CRIT if _shields[f] <= 0.0 else Palette.FG)
		if compact:
			continue
		var hp_pos: Vector2 = center + Vector2(sin(mid), -cos(mid)) * (r_out + 14.0)
		var hp_text: String = "DOWN" if _shields[f] <= 0.0 else "%d/%d" % [
			int(_shields[f]), int(_shield_max)]
		draw_string(font, hp_pos + Vector2(-18, 4), hp_text,
			HORIZONTAL_ALIGNMENT_CENTER, 46, 10,
			Palette.CRIT if _shields[f] <= 0.0 else Palette.DIM)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var center: Vector2 = size * 0.5
		var d: Vector2 = event.position - center
		if d.length() < _outer_radius() * 0.4:
			return
		var bearing: float = Sectors.wrap_deg(rad_to_deg(atan2(d.x, -d.y)))
		selected_facing = Sectors.facing_of_relative_bearing(bearing)
		facing_selected.emit(selected_facing)
		queue_redraw()
