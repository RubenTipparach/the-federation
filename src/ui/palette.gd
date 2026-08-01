class_name Palette
extends RefCounted

## The one place UI colors are read. It does not own them: every value below is
## a role looked up in data/palette.json, which CLAUDE.md 3.1 names as the
## single colour authority. That file says which palette entry plays "accent"
## or "warn"; this file only gives those roles names GDScript can use.
##
## Two pools back the roles. The chassis draws from `colors`, the Waldgeist
## palette, verbatim, because plates and bezels are committed art. The lit
## readouts draw from `ui_colors`, a small set of emissives, because an
## instrument that is on emits rather than reflects and no reflective palette
## entry sits bright enough to say so. Ship art can never reach that second
## pool: tools/shiplib.py verify() checks hulls against `colors` alone.
##
## These are presentation, not gameplay tuning, which is why the roles are here
## rather than in data/tuning.json. Gameplay numbers must never appear here.

const PALETTE_PATH: String = "res://data/palette.json"

static var _roles: Dictionary = {}


## Resolve the role map once. Roles name a colour, colours name a hex, and a
## missing role is a hard failure rather than a silent fallback: a role that
## quietly paints black because someone typoed it is worse than one that stops.
static func _role(name: String) -> Color:
	if _roles.is_empty():
		var f: FileAccess = FileAccess.open(PALETTE_PATH, FileAccess.READ)
		assert(f != null, "missing palette: " + PALETTE_PATH)
		var data: Dictionary = JSON.parse_string(f.get_as_text())
		var pool: Dictionary = {}
		pool.merge(data["colors"])
		pool.merge(data["ui_colors"])
		for key in data["ui"]:
			var entry: String = String(data["ui"][key])
			assert(pool.has(entry), "ui role %s names unknown colour %s" % [key, entry])
			_roles[key] = Color(String(pool[entry]))
	assert(_roles.has(name), "unknown ui role: " + name)
	return _roles[name]


static var BG: Color:
	get: return _role("bg")
static var PANEL: Color:
	get: return _role("panel")
static var PANEL_2: Color:
	get: return _role("panel_2")
static var LINE: Color:
	get: return _role("line")
static var LINE_HOT: Color:
	get: return _role("line_hot")
static var FG: Color:
	get: return _role("fg")
static var DIM: Color:
	get: return _role("dim")

## The lit set. The names are what the widgets have always called them, so the
## skin changes underneath every readout without a single call site moving.
static var CYAN: Color:
	get: return _role("accent")
static var CYAN_DIM: Color:
	get: return _role("accent_dim")
static var AMBER: Color:
	get: return _role("warn")
static var MAGENTA: Color:
	get: return _role("weapon")
static var BLUE: Color:
	get: return _role("power")
static var SLATE: Color:
	get: return _role("neutral")
static var OK: Color:
	get: return _role("ok")
static var CRIT: Color:
	get: return _role("crit")


static func family_color(family: String) -> Color:
	match family:
		"weapon": return _role("family_weapon")
		"power": return _role("family_power")
		"control": return _role("family_control")
		_: return _role("family_hull")


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
