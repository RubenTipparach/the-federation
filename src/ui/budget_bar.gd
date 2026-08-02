extends VBoxContainer

## One fitting budget readout. Over budget turns the bar and value critical,
## because an illegal fit must be impossible to miss.


func paint(label: String, used: float, cap: float, hue: Color) -> void:
	var over: bool = used > cap
	$Row/Name.text = label.to_upper() + (" OVER" if over else "")
	Paint.tint($Row/Name, "font_color", Palette.DIM)
	$Row/Value.text = "%d / %d" % [int(used), int(cap)]
	Paint.tint($Row/Value, "font_color", Palette.CRIT if over else Palette.FG)
	$Track/Fill.anchor_right = clampf(used / maxf(cap, 1.0), 0.0, 1.0)
	$Track/Fill.color = Palette.CRIT if over else hue
