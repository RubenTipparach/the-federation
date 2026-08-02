extends Control

## The marker drawn over a ship in the tactical view: four corner brackets, the
## ship's name above them, and its hull bar below.
##
## One component, two states, because a hover and a lock are the same marker at
## two strengths rather than two things to build and keep in agreement
## (CLAUDE.md 4.1). HOVER draws the corners alone and dim, so pointing at a
## contact says only "this is pickable". LOCKED draws them bright and adds the
## name and the hull bar, which is the information a player wants about the
## ship they have actually chosen to shoot.
##
## Painted in _draw() under the section 7 data driven exception, granted with
## the tactical reskin: the bracket's
## size follows the ship's projected extent, which changes with zoom and range
## every frame, so there is no static node tree that could describe it. Only
## the name Label is a real node, because text is not worth hand drawing.

enum State { HIDDEN, HOVER, LOCKED }

## Length of each corner arm as a fraction of the shorter side, so the corners
## stay corners instead of becoming a full box on a small bracket.
const ARM_FRAC := 0.28
const ARM_MIN := 6.0
const THICK := 2.0
const BAR_H := 3.0
const BAR_GAP := 5.0

var state: int = State.HIDDEN
var tint: Color = Palette.CYAN
var hull_frac: float = 1.0


func show_target(p_state: int, p_name: String, p_hull_frac: float,
		p_tint: Color) -> void:
	state = p_state
	tint = p_tint
	hull_frac = clampf(p_hull_frac, 0.0, 1.0)
	visible = state != State.HIDDEN
	var label: Label = $Name
	label.visible = state == State.LOCKED
	if label.visible:
		label.text = p_name
		label.add_theme_color_override("font_color", tint)
	queue_redraw()


func _draw() -> void:
	if state == State.HIDDEN:
		return
	var col: Color = tint
	if state == State.HOVER:
		# A hover is a suggestion, not a decision, so it is drawn faint.
		col.a = 0.45
	var arm: float = maxf(ARM_MIN, minf(size.x, size.y) * ARM_FRAC)
	var w: float = size.x
	var h: float = size.y
	# Four corners, each two strokes. Drawn as rects rather than lines so the
	# thickness is exact at any zoom instead of depending on line antialiasing.
	var corners: Array = [
		[Vector2(0, 0), Vector2(1, 1)],
		[Vector2(w, 0), Vector2(-1, 1)],
		[Vector2(0, h), Vector2(1, -1)],
		[Vector2(w, h), Vector2(-1, -1)],
	]
	for c in corners:
		var p: Vector2 = c[0]
		var d: Vector2 = c[1]
		var hx: float = p.x if d.x > 0 else p.x - arm
		var vy: float = p.y if d.y > 0 else p.y - arm
		draw_rect(Rect2(hx, p.y - (0.0 if d.y > 0 else THICK), arm, THICK), col)
		draw_rect(Rect2(p.x - (0.0 if d.x > 0 else THICK), vy, THICK, arm), col)

	if state != State.LOCKED:
		return
	# Hull bar under the bracket, full width, so damage reads without moving
	# the eye off the ship.
	var bar_y: float = h + BAR_GAP
	draw_rect(Rect2(0, bar_y, w, BAR_H), Palette.LINE)
	if hull_frac > 0.0:
		var band: Color = Palette.OK
		if hull_frac <= 0.25:
			band = Palette.CRIT
		elif hull_frac <= 0.6:
			band = Palette.AMBER
		draw_rect(Rect2(0, bar_y, w * hull_frac, BAR_H), band)
