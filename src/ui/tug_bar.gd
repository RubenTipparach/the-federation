extends Control

## The tractor contest, drawn as two strips of boxes meeting at a seam.
##
## The number that decides a tug of war is not either bid on its own, it is
## which one is bigger. Two strips growing toward one bright seam say that
## without arithmetic: whichever side has pushed past the middle is winning, and
## by how many boxes. Both strips are in the same unit as the bid strip above
## them, which is reactor output, so "raise it by two" has an obvious cost.
##
## What the strips show is force AFTER the tonnage weighting, because that is
## the number the simulation actually compares (Tractor.break_bid). The raw bid
## and the multiplier are printed by the panel underneath.
##
## Geometry is fixed and colour is not: the left side is always the grip and the
## right side is always the shove, whichever of them belongs to the player. That
## keeps one control for both sides of a beam (see docs/13 section 8), and the
## tint is what says whose it is.
##
## It paints in _draw() under the CLAUDE.md section 7 exception the box strips
## already hold: the box count is live simulation output and there is no static
## node tree that could describe it. It reports no clicks at all: the way to
## change a bid is the strip above, not this.

const GAP: float = 1.5
const SEAM: float = 3.0
const MIN_BOX: float = 3.0

var cap: int = 14
var left_boxes: int = 0
var right_boxes: int = 0
var left_tint: Color = Palette.CYAN
var right_tint: Color = Palette.MAGENTA


## Values are forces, not box counts, and are rounded to the nearest whole box.
## A box is a reactor unit and that is the resolution the contest is fought at,
## so rounding is honest rather than lossy.
func paint(left_force: float, p_left_tint: Color, right_force: float,
		p_right_tint: Color, p_cap: int) -> void:
	cap = maxi(1, p_cap)
	left_boxes = clampi(int(roundf(left_force)), 0, cap)
	right_boxes = clampi(int(roundf(right_force)), 0, cap)
	left_tint = p_left_tint
	right_tint = p_right_tint
	queue_redraw()


func _box_width() -> float:
	var half: float = (size.x - SEAM) * 0.5
	return maxf(MIN_BOX, (half - GAP * float(cap - 1)) / float(cap))


func _draw() -> void:
	var w: float = _box_width()
	var h: float = size.y
	var half: float = (size.x - SEAM) * 0.5
	var seam_x: float = half

	# Both strips grow toward the seam, so the left one fills from its right end.
	for i in range(cap):
		var lit: bool = i >= cap - left_boxes
		var x: float = float(i) * (w + GAP)
		draw_rect(Rect2(x, 0.0, w, h), left_tint if lit else Palette.LINE)
	for i in range(cap):
		var lit_r: bool = i < right_boxes
		var x_r: float = seam_x + SEAM + float(i) * (w + GAP)
		draw_rect(Rect2(x_r, 0.0, w, h), right_tint if lit_r else Palette.LINE)

	draw_rect(Rect2(seam_x, -1.0, SEAM, h + 2.0), Palette.FG)
