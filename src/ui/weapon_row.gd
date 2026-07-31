extends HBoxContainer

## One weapon line on the combat HUD: name, readiness chip, reason. The chip
## states come straight from ShipState.fire_check reasons so the UI can never
## disagree with the rule that gates the shot.

const CHIP_COLORS: Dictionary = {
	"bears": Palette.OK,
	"charging": Palette.AMBER,
	"range": Palette.DIM,
	"no arc": Palette.CRIT,
	"destroyed": Palette.CRIT,
	"empty": Palette.LINE_HOT,
}


func paint(display_name: String, reason: String, charge: float) -> void:
	$Name.text = display_name
	$Name.add_theme_color_override("font_color", Palette.FG)
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
	var hue: Color = CHIP_COLORS.get(reason, Palette.DIM)
	$Chip.add_theme_color_override("font_color", hue)
	# The chip already carries the reason; the note only adds words when the
	# chip is a percentage.
	$Note.text = "charging" if reason == "charging" else ""
	$Note.add_theme_color_override("font_color", Palette.DIM)
