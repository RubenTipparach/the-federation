extends HBoxContainer

## One shield facing bar. Same thresholds as every other shield readout,
## through Palette.shield_color.


func paint(facing: int, value: float, max_value: float) -> void:
	$Idx.text = Sectors.facing_mark(facing)
	Paint.tint($Idx, "font_color", Palette.DIM)
	var frac: float = 0.0 if max_value <= 0.0 else value / max_value
	var hue: Color = Palette.shield_color(frac)
	$Track/Fill.anchor_right = clampf(frac, 0.0, 1.0)
	$Track/Fill.color = hue
	$Value.text = "DOWN" if value <= 0.0 else "%d/%d" % [int(value), int(max_value)]
	Paint.tint($Value, "font_color", hue)
