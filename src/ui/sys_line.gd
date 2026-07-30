extends HBoxContainer

## One system on the ship systems display: its icon, its code, and what is
## left of it. The SSD is a fitting view, so it answers "what is aboard and is
## it intact"; the per hit point boxes belong to the combat view, where losing
## one box at a time is the thing being watched.
##
## Icons are committed .png files (CLAUDE.md 3), tinted here with the family
## colour the rest of the UI already uses, so one file serves every state.

const ICON_DIR: String = "res://assets/icons/"

var _family: String = "hull"


## Called when the fit changes. Loading the texture is the only work here.
func build(code: String, _boxes_max: int, family: String) -> void:
	_family = family
	$SysName.text = code
	var path: String = ICON_DIR + code.to_lower().replace("-", "") + ".png"
	$Icon.texture = load(path) if ResourceLoader.exists(path) else null
	$Icon.visible = $Icon.texture != null


func paint(cur: int, boxes_max: int) -> void:
	$Count.text = "%d/%d" % [cur, boxes_max]
	var dead: bool = cur <= 0
	var hurt: bool = cur < boxes_max and not dead
	var hue: Color = Palette.CRIT if dead else (
		Palette.AMBER if hurt else Palette.family_color(_family))
	$Icon.modulate = hue if not dead else Palette.with_alpha(Palette.CRIT, 0.45)
	$SysName.add_theme_color_override("font_color", Palette.CRIT if dead else Palette.FG)
	$Count.add_theme_color_override("font_color", hue if dead or hurt else Palette.DIM)
