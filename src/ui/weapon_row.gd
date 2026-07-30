extends HBoxContainer

## One weapon line on the combat HUD: name, readiness chip, reason. The chip
## states come straight from ShipState.fire_check reasons so the UI can never
## disagree with the rule that gates the shot.

const CHIP_COLORS: Dictionary = {
	"bears": Color("57c98a"),
	"charging": Color("e8a54a"),
	"range": Color("6d8296"),
	"no arc": Color("e2564f"),
	"destroyed": Color("e2564f"),
	"empty": Color("4d5762"),
}


func paint(display_name: String, reason: String, charge: float) -> void:
	$Name.text = display_name
	$Name.add_theme_color_override("font_color", Palette.FG)
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
