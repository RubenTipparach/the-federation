extends Control

## One squad of marines drawn as figures with their wounds: a row of soldier
## glyphs, each carrying the pips of the hits it has taken, a dead one greyed
## under a cross. The canonical readout of a squad's state, drawn the same
## wherever a squad appears (the home deck, our team on their deck, their crew
## facing us), so the three rows on the marines station cannot drift apart.
##
## A live data visualization in the CLAUDE.md section 7 sense: how many
## figures there are and how many pips each carries IS the sim's marine
## arrays, so no static node tree could describe it. The node is authored in
## scenes/ui/subsystem_panel.tscn; this script only paints what set_squad was
## handed and never reads the sim itself, keeping it a dumb terminal the way
## the box strip is.
##
## Painted in whatever colour the caller sets, because the same control draws
## friend and foe and the colour is the caller's statement of which.

var _squad: Array[int] = []
var _limit: int = 3
var _tint: Color = Color.WHITE

const FIG_W: float = 12.0
const FIG_H: float = 15.0
const PIP: float = 4.0
const STEP: float = 22.0


func set_squad(squad: Array[int], limit: int, tint: Color) -> void:
	_squad = squad.duplicate()
	_limit = limit
	_tint = tint
	queue_redraw()


func _draw() -> void:
	var dead_tint: Color = Color(0.196, 0.196, 0.188)
	var pip_off: Color = Color(0.078, 0.122, 0.145)
	var cross: Color = Color(0.812, 0.416, 0.325)
	for i in range(_squad.size()):
		var x: float = float(i) * STEP
		if x + FIG_W > size.x:
			break
		var hits: int = _squad[i]
		var dead: bool = hits >= _limit
		var body: Color = dead_tint if dead else _tint
		# The figure: helmet, torso, arms, drawn in flat quads like every
		# glyph in this interface.
		draw_rect(Rect2(x + 2.0, 0.0, FIG_W - 4.0, 5.0), body)
		draw_rect(Rect2(x + 1.0, 6.0, FIG_W - 2.0, FIG_H - 6.0), body)
		if dead:
			draw_line(Vector2(x, 0.0), Vector2(x + FIG_W, FIG_H), cross, 2.0)
			draw_line(Vector2(x + FIG_W, 0.0), Vector2(x, FIG_H), cross, 2.0)
		# The wounds, one pip per hit taken, the empty ones outlined so three
		# healthy marines do not read as three unmarked strangers.
		for p in range(_limit):
			var px: float = x + float(p) * (PIP + 1.0)
			var rect: Rect2 = Rect2(px, FIG_H + 3.0, PIP, PIP)
			if p < hits:
				draw_rect(rect, cross)
			else:
				draw_rect(rect, pip_off, false, 1.0)
