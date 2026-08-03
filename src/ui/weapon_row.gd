extends HBoxContainer

## One weapon line on the combat HUD: name, capacitor, readiness chip, and the
## switch that arms an overload. The chip states come straight from
## ShipState.fire_check reasons so the UI can never disagree with the rule that
## gates the shot, and the switch reports a click rather than deciding
## anything: only Battle.apply_command may change what a ship is doing.

## The player asked for this mount to be armed, or disarmed. Whether it happens
## is the battle's business, and the screen puts the switch back to whatever the
## ship believes afterwards.
signal overload_toggled(on: bool)


func _ready() -> void:
	$Ovl.toggled.connect(func(on: bool) -> void: overload_toggled.emit(on))


## Why a weapon is or is not ready, in the colour that says it. A function
## rather than a const dictionary because Palette now reads its values from
## data/palette.json at first use, so they are resolved at runtime and cannot
## be baked into a constant.
static func chip_color(reason: String) -> Color:
	match reason:
		"bears": return Palette.OK
		# Both mean "wait a moment": one for the capacitor, the other for the
		# reserve an armed overload has to spend.
		"charging", "battery": return Palette.AMBER
		"no arc", "destroyed": return Palette.CRIT
		"no lock": return Palette.LINE_HOT
		"empty": return Palette.LINE_HOT
		_: return Palette.DIM


func paint(display_name: String, reason: String, charge: float,
		can_overload: bool = false, armed: bool = false) -> void:
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
	var hue: Color = chip_color(reason)
	if armed and reason == "bears":
		# Ready, but not an ordinary shot. RDY here would be a lie by omission:
		# the next trigger pull empties the reserve and takes the shields down.
		# ARMED rather than OVERLOAD because the chip is 77 pixels and the face
		# advances 12 to a character, so the longer word would be cut.
		chip = "ARMED"
		hue = Palette.CRIT
	$Chip.text = chip
	Paint.tint($Chip, "font_color", hue)
	# There was a second label here repeating the chip in lower case. It said
	# nothing the chip did not, and it was the widest thing in the column
	# (CLAUDE.md 6.4: the panel is a fixed rectangle, so words have to earn
	# their pixels).

	# Three states, and the dark one is information rather than decoration: it
	# says at a glance which of the fitted weapons could be overloaded at all.
	var ovl: Button = $Ovl
	ovl.disabled = not can_overload
	set_armed(armed)
	Paint.button_tint(ovl, Palette.CRIT if armed else (
		Palette.FG if can_overload else Palette.DIM))


## Put the switch where the SHIP says it is, without reporting it as a click.
## Used after an order as well as on every repaint, because an order the battle
## refused must not leave the panel showing it as taken.
func set_armed(on: bool) -> void:
	if $Ovl.button_pressed != on:
		$Ovl.set_pressed_no_signal(on)
