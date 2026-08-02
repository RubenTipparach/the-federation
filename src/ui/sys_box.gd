extends Panel

## One internal system box on the SSD. Painted from sim state; holds none.


func paint(code: String, cur: int, max_boxes: int, family: String) -> void:
	var hue: Color = Palette.family_color(family)
	var dead: bool = cur <= 0
	var hit: bool = cur < max_boxes and not dead
	$Body/Code.text = code
	$Body/Hp.text = "%d/%d" % [cur, max_boxes]
	if dead:
		$Bg.color = Color("0a0d11")
		Paint.tint($Body/Code, "font_color", Color("4d5762"))
		Paint.tint($Body/Hp, "font_color", Palette.CRIT)
	elif hit:
		$Bg.color = Palette.with_alpha(Palette.AMBER, 0.22)
		Paint.tint($Body/Code, "font_color", Palette.AMBER)
		Paint.tint($Body/Hp, "font_color", Palette.FG)
	else:
		$Bg.color = Palette.with_alpha(hue, 0.16)
		Paint.tint($Body/Code, "font_color", hue.lerp(Palette.FG, 0.3))
		Paint.tint($Body/Hp, "font_color", Palette.FG)
