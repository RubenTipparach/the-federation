class_name Palette
extends RefCounted

## The one place UI colors are read. It does not own them: every value below is
## a role looked up in data/palette.json, which CLAUDE.md 3.1 names as the
## single colour authority. That file says which palette entry plays "accent"
## or "warn"; this file only gives those roles names GDScript can use.
##
## Which roles apply is chosen by `ui_skin`, so the whole interface repaints
## from one key in that file. Only the LIT half is read here; the chassis half
## is baked into the plate textures by tools/gen_ui_plates.py and wired by the
## generated theme, and scripts/gen-skin.sh keeps the two in step.
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
		var skin_name: String = String(data["ui_skin"])
		assert(data["ui_skins"].has(skin_name),
			"ui_skin names unknown skin: " + skin_name)
		var lit: Dictionary = data["ui_skins"][skin_name]["lit"]
		for key in lit:
			var entry: String = String(lit[key])
			assert(pool.has(entry), "%s lit role %s names unknown colour %s" % [
				skin_name, key, entry])
			_roles[key] = Color(String(pool[entry]))
	assert(_roles.has(name), "unknown ui role: " + name)
	return _roles[name]


## The whole palette file, parsed once. The role lookup above needs it and so
## does anything reading a role map other than the skin's, which is why it is
## cached here rather than opened again per caller.
static var _file: Dictionary = {}


static func _palette_file() -> Dictionary:
	if _file.is_empty():
		var f: FileAccess = FileAccess.open(PALETTE_PATH, FileAccess.READ)
		assert(f != null, "missing palette: " + PALETTE_PATH)
		_file = JSON.parse_string(f.get_as_text())
	return _file


## A palette entry by its own name, rather than by the role it happens to play.
## Only for callers that already hold a role map of their own: the world colour
## lists, and nothing else. Everything about the interface goes through a role.
static func named(entry: String) -> Color:
	var data: Dictionary = _palette_file()
	if data["colors"].has(entry):
		return Color(String(data["colors"][entry]))
	assert(data["ui_colors"].has(entry), "unknown palette colour: " + entry)
	return Color(String(data["ui_colors"][entry]))


## The ordered colour list one kind of world is painted from (docs/14). A
## variant with no list is a data error and stops rather than painting a world
## in whatever the shader defaults happen to be, which would be somebody else's
## palette.
static func world_roles(variant: String) -> Array:
	var worlds: Dictionary = _palette_file()["worlds"]
	assert(worlds.has(variant), "no world palette for variant: " + variant)
	return worlds[variant]


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
