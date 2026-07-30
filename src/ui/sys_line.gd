extends VBoxContainer

## One subsystem slot on the ship systems display: an icon and a health bar,
## nothing else. The SSD is a fitting view, so a section's slots should read at
## a glance; the code, the box count, and the mount live in the tooltip for
## when the player wants them, and the per hit point boxes belong to the combat
## view where they are what is being watched.
##
## Icons are committed .png masks (CLAUDE.md 3) tinted here with the family
## colour the rest of the UI uses, so one file serves every damage state.

const ICON_DIR: String = "res://assets/icons/"

var _family: String = "hull"
var _code: String = ""
var _mount: String = ""


## Called when the fit changes: load the mask and write the tooltip once.
func build(code: String, boxes_max: int, family: String, mount_id: String = "") -> void:
	_family = family
	_code = code
	_mount = mount_id
	var path: String = ICON_DIR + code.to_lower().replace("-", "") + ".png"
	$Icon.texture = load(path) if ResourceLoader.exists(path) else null
	_write_tooltip(boxes_max, boxes_max)


func paint(cur: int, boxes_max: int) -> void:
	var frac: float = 0.0 if boxes_max <= 0 else float(cur) / float(boxes_max)
	var dead: bool = cur <= 0
	var hurt: bool = frac < 1.0 and not dead
	var hue: Color = Palette.CRIT if dead else (
		Palette.AMBER if hurt else Palette.family_color(_family))
	$Icon.modulate = Palette.with_alpha(Palette.CRIT, 0.4) if dead else hue
	$Health.color = Palette.with_alpha(hue, 0.25 if dead else 0.9)
	# The bar is the glance: full width intact, a stub when nearly gone.
	$Health.custom_minimum_size.x = 26.0
	$Health.scale = Vector2(maxf(frac, 0.04) if not dead else 1.0, 1.0)
	_write_tooltip(cur, boxes_max)


func _write_tooltip(cur: int, boxes_max: int) -> void:
	tooltip_text = "%s   %d / %d boxes%s" % [
		_code, cur, boxes_max, "" if _mount.is_empty() else "   mount " + _mount]
