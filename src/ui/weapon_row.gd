extends HBoxContainer

## One weapon line on the combat HUD: name, readiness chip, reason. The chip
## states come straight from ShipState.fire_check reasons so the UI can never
## disagree with the rule that gates the shot.

## Why a weapon is or is not ready, in the colour that says it. A function
## rather than a const dictionary because Palette now reads its values from
## data/palette.json at first use, so they are resolved at runtime and cannot
## be baked into a constant.
static func chip_color(reason: String) -> Color:
	match reason:
		"bears": return Palette.OK
		"charging": return Palette.AMBER
		"no arc", "destroyed": return Palette.CRIT
		"no lock": return Palette.LINE_HOT
		"empty": return Palette.LINE_HOT
		_: return Palette.DIM


func paint(display_name: String, reason: String, charge: float) -> void:
	$Name.text = display_name
	Paint.tint($Name, "font_color", Palette.FG)
	# The capacitor is the thing a captain watches: a bar that fills, and a
	# chip that says why the shot cannot be taken when it is full.
	var bar: ProgressBar = $Cap
	bar.value = clampf(charge, 0.0, 1.0)
	var full: bool = charge >= 1.0
	bar.modulate = Palette.OK if reason == "bears" else (
		Palette.CYAN if full else Palette.CYAN_DIM)
	var chip: String = "RDY" if reason == "bears" else reason.to_upper()
	if reason == "charging":
		chip = "%d%%" % int(charge * 100.0)
	$Chip.text = chip
	var hue: Color = chip_color(reason)
	Paint.tint($Chip, "font_color", hue)
	# The chip already carries the reason; the note only adds words when the
	# chip is a percentage.
	$Note.text = "charging" if reason == "charging" else ""
	Paint.tint($Note, "font_color", Palette.DIM)
