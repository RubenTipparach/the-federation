class_name ArenaMap
extends Control

## A plan of one arena: what terrain is in it, and where the two sides start.
##
## It paints in _draw() for the reason CLAUDE.md section 7 grants the SSD shield
## ring: the content IS the data. A map has between zero and eighteen circles at
## positions drawn from a battle seed, so no static node tree could describe it
## and no committed mesh could either. Nothing is constructed here; the control
## is authored in its scene and this script only paints and reads.
##
## The circles are the simulation's own circles, straight out of Terrain, so the
## preview cannot disagree with the arena it is previewing.

## What is being shown. Set through show_terrain, never poked directly, so the
## control always repaints when it changes.
var terrain: Terrain = null
var starts: Array[Vector2] = []

## How many rings a cloud is faked from. Control has no radial gradient, so a
## nebula is drawn as nested discs of falling alpha, which is enough at preview
## size and matches how the 3D cloud actually falls off.
const CLOUD_BANDS: int = 5
const GRID_DIVISIONS: int = 6


func show_terrain(p_terrain: Terrain, p_starts: Array[Vector2]) -> void:
	terrain = p_terrain
	starts = p_starts
	queue_redraw()


## Arena units to control pixels. The arena is square, so one scale serves both
## axes and the plan never stretches.
func _scale() -> float:
	var half: float = float(Catalog.tuning()["combat"]["arena_half_extent"])
	return minf(size.x, size.y) / (half * 2.0)


func _to_px(at: Vector2) -> Vector2:
	var half: float = float(Catalog.tuning()["combat"]["arena_half_extent"])
	var s: float = _scale()
	var inset: Vector2 = (size - Vector2.ONE * (half * 2.0 * s)) * 0.5
	return inset + Vector2(at.x + half, half - at.y) * s


func _draw() -> void:
	var half: float = float(Catalog.tuning()["combat"]["arena_half_extent"])
	var s: float = _scale()
	var span: float = half * 2.0 * s
	var origin: Vector2 = (size - Vector2.ONE * span) * 0.5
	draw_rect(Rect2(origin, Vector2(span, span)), Palette.BG)

	# A faint grid, so the size of a feature can be judged rather than guessed.
	for i in range(1, GRID_DIVISIONS):
		var t: float = span * float(i) / float(GRID_DIVISIONS)
		draw_line(origin + Vector2(t, 0.0), origin + Vector2(t, span), Palette.LINE, 1.0)
		draw_line(origin + Vector2(0.0, t), origin + Vector2(span, t), Palette.LINE, 1.0)

	if terrain != null:
		for f in terrain.features:
			_draw_feature(f, s)

	# The two starting positions, as crosses rather than dots: a cross reads as
	# a mark on a chart, and a dot would read as another small rock.
	var arm: float = maxf(3.0, span * 0.018)
	for i in range(starts.size()):
		var at: Vector2 = _to_px(starts[i])
		var tint: Color = Palette.CYAN if i == 0 else Palette.MAGENTA
		draw_line(at - Vector2(arm, 0.0), at + Vector2(arm, 0.0), tint, 1.5)
		draw_line(at - Vector2(0.0, arm), at + Vector2(0.0, arm), tint, 1.5)

	draw_rect(Rect2(origin, Vector2(span, span)), Palette.LINE, false, 1.0)


func _draw_feature(f: Dictionary, s: float) -> void:
	var at: Vector2 = _to_px(f["pos"])
	var field: float = float(f["field"]) * s
	var body: float = float(f["body"]) * s
	match String(f["kind"]):
		Terrain.KIND_NEBULA:
			# No outline. A cloud has no edge you can touch, and drawing one
			# would say the opposite of what the rule does.
			for band in range(CLOUD_BANDS):
				var t: float = 1.0 - float(band) / float(CLOUD_BANDS)
				draw_circle(at, field * t, Palette.with_alpha(Palette.CYAN, 0.07))
		Terrain.KIND_ASTEROID:
			draw_circle(at, field, Palette.with_alpha(Palette.AMBER, 0.09))
			draw_arc(at, field, 0.0, TAU, 28, Palette.with_alpha(Palette.AMBER, 0.45), 1.0)
			draw_circle(at, maxf(body, 1.4), Palette.AMBER)
		Terrain.KIND_PLANET:
			draw_arc(at, field, 0.0, TAU, 48, Palette.with_alpha(Palette.BLUE, 0.5), 1.0)
			draw_circle(at, field, Palette.with_alpha(Palette.BLUE, 0.07))
			draw_circle(at, maxf(body, 2.0), Palette.BLUE)
