extends Control

## A rolling history of frame times, one column per frame.
##
## The number beside it says what the frame costs right now, which is the wrong
## question when you have just flipped a switch: what you want to see is the
## step, and whether the new cost is steady or a saw. A column per frame shows
## both, and it shows the spikes that an averaged readout hides completely.
##
## It paints in _draw() for the reason the box strips and the tug bar do
## (CLAUDE.md section 7): the content IS the data, a buffer of live samples that
## no node tree could describe. Nothing is constructed and nothing is read back.
##
## Samples every frame, repaints far slower. Every spike is therefore captured,
## while the graph itself stays close to free, which matters more here than
## anywhere else in the project: an instrument that changes what it measures is
## worse than no instrument.

## Columns held, which is also the pixel width the graph wants.
const SAMPLES: int = 200
## The scale steps the top of the graph may take, in milliseconds. It does not
## fit itself to the data continuously, because an axis that slides makes before
## and after incomparable and that comparison is the only reason this exists. It
## snaps to the smallest step that holds the worst sample, and the panel prints
## which step it landed on, so a scale change is stated rather than silent.
const CEILING_STEPS: Array = [25.0, 50.0, 100.0, 250.0, 500.0]
## The two budgets worth a line: sixty frames a second and thirty.
const BUDGET_60: float = 1000.0 / 60.0
const BUDGET_30: float = 1000.0 / 30.0

var _samples: PackedFloat32Array = PackedFloat32Array()
var _at: int = 0
var _ceiling: float = 50.0


## The top of the scale, and what the panel prints beside the graph.
func ceiling_ms() -> float:
	return _ceiling


func _ready() -> void:
	_samples.resize(SAMPLES)
	_samples.fill(0.0)


## One frame's cost. Called every frame; the repaint is throttled by the panel.
func push(ms: float) -> void:
	_samples[_at] = ms
	_at = (_at + 1) % SAMPLES


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	var worst: float = 0.0
	for ms in _samples:
		worst = maxf(worst, ms)
	_ceiling = float(CEILING_STEPS[CEILING_STEPS.size() - 1])
	for step_ms in CEILING_STEPS:
		if worst <= float(step_ms):
			_ceiling = float(step_ms)
			break
	draw_rect(Rect2(Vector2.ZERO, size), Palette.BG)

	# Budget lines first, so the columns stand on top of them.
	for budget in [BUDGET_60, BUDGET_30]:
		var y: float = h - clampf(budget / _ceiling, 0.0, 1.0) * h
		draw_line(Vector2(0.0, y), Vector2(w, y), Palette.LINE, 1.0)

	var step: float = w / float(SAMPLES)
	for i in range(SAMPLES):
		# Oldest on the left, so the graph reads left to right like time does.
		var ms: float = _samples[(_at + i) % SAMPLES]
		if ms <= 0.0:
			continue
		var frac: float = clampf(ms / _ceiling, 0.0, 1.0)
		var tint: Color = Palette.OK
		if ms > BUDGET_30:
			tint = Palette.CRIT
		elif ms > BUDGET_60:
			tint = Palette.AMBER
		var col_h: float = frac * h
		draw_rect(Rect2(float(i) * step, h - col_h, maxf(step, 1.0), col_h), tint)

	draw_rect(Rect2(Vector2.ZERO, size), Palette.LINE, false, 1.0)
