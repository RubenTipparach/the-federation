class_name Palette
extends RefCounted

## The one place UI colors are defined, taken from the approved mockup.
## Presentation constants, not gameplay tuning, so they live in code rather
## than data/tuning.json; gameplay numbers must never appear here.

const BG := Color("080d14")
const PANEL := Color("0d151f")
const PANEL_2 := Color("111b28")
const LINE := Color("1e2c3c")
const LINE_HOT := Color("2c4258")
const FG := Color("c6d5e2")
const DIM := Color("6d8296")
const CYAN := Color("5fd4e8")
const CYAN_DIM := Color("2b7f92")
const AMBER := Color("e8a54a")
const MAGENTA := Color("d4649b")
const BLUE := Color("6f9fe0")
const SLATE := Color("8c9bab")
const OK := Color("57c98a")
const CRIT := Color("e2564f")

const FAMILY_COLORS: Dictionary = {
	"weapon": MAGENTA,
	"power": BLUE,
	"control": AMBER,
	"hull": SLATE,
}


static func family_color(family: String) -> Color:
	return FAMILY_COLORS.get(family, SLATE)


## Shield state band by remaining fraction. The one place the thresholds
## live: colors and 3D material selection both derive from it.
static func shield_band(frac: float) -> String:
	if frac <= 0.0:
		return "down"
	if frac < 0.4:
		return "warn"
	return "ok"


## Shield readout color by remaining fraction, matching the mockup thresholds.
static func shield_color(frac: float) -> Color:
	match shield_band(frac):
		"down":
			return CRIT
		"warn":
			return AMBER
		_:
			return CYAN


static func with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)
