extends Control

## A discrete allocation strip: N boxes across, M of them filled. Click a box
## to set the level to it, click the box that is already the level to drop one.
##
## This is the control CLAUDE.md 6.2 requires instead of a slider in the
## tactical view. A slider asks for a slow precise drag exactly when the player
## has none to give, and it hides the fact that the value is a whole number of
## reactor points. Here the count is the value, readable without reading a
## number.
##
## It paints in _draw() rather than instancing N button nodes, which is the
## data driven 2D control exception in CLAUDE.md section 7: the box count is
## the reactor's surviving output and changes as the reactor is damaged, so
## there is no static node tree that could describe it. No node trees or
## meshes are built here; it is one authored node that paints and reports
## clicks, exactly like the SSD shield ring.

## Emitted with the level the player picked, from 0 to capacity.
signal level_picked(level: int)

const GAP := 2.0
const MIN_BOX := 3.0

var capacity: int = 24
var level: int = 0
var accent: Color = Palette.CYAN
## Boxes past this are drawn as unavailable rather than merely empty, so a
## reactor that has lost output shows the loss instead of silently shrinking.
var ceiling: int = -1


func setup(p_accent: Color) -> void:
	accent = p_accent
	queue_redraw()


## Capacity is passed on every paint rather than fixed once, because it is the
## ship's own reactor budget and the ship can change between battles. ceiling
## is how much of that budget still survives; boxes past it are drawn as shot
## away rather than merely empty.
func paint(p_level: int, p_capacity: int, p_ceiling: int = -1) -> void:
	capacity = maxi(1, p_capacity)
	level = clampi(p_level, 0, capacity)
	ceiling = p_ceiling
	queue_redraw()


func _box_width() -> float:
	return maxf(MIN_BOX, (size.x - GAP * float(capacity - 1)) / float(capacity))


func _draw() -> void:
	var w: float = _box_width()
	var top: float = 0.0
	var h: float = size.y
	var limit: int = capacity if ceiling < 0 else clampi(ceiling, 0, capacity)
	for i in range(capacity):
		var x: float = float(i) * (w + GAP)
		var col: Color = Palette.LINE
		if i >= limit:
			# Output this box used to represent has been shot away.
			col = Palette.PANEL_2
		elif i < level:
			col = accent
		draw_rect(Rect2(x, top, w, h), col)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
		return
	var w: float = _box_width()
	var picked: int = int(floor(event.position.x / (w + GAP))) + 1
	picked = clampi(picked, 0, capacity)
	# Clicking the box that is already the top of the bar means "one less",
	# so a strip can be walked down without a separate control.
	if picked == level:
		picked -= 1
	level_picked.emit(picked)
	accept_event()
