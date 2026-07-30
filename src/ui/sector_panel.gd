extends PanelContainer

## One shield facing's worth of the ship systems display, or the hull core.
## Carries the facing number, its name, the bearing arc it covers, and the
## systems mounted behind it. Structure is authored in sector_panel.tscn; this
## script instances system lines and paints sim state (CLAUDE.md 5.2).

const SYS_LINE := preload("res://scenes/ui/sys_line.tscn")

var _lines: Array = []
var _systems: Array[Dictionary] = []


func build(tag: String, title: String, arc: String, systems: Array[Dictionary]) -> void:
	$V/Head/Tag.text = tag
	$V/Head/Title.text = title.to_upper()
	$V/Head/Arc.text = arc
	_systems = systems
	_lines = []
	for child in $V/Systems.get_children():
		child.queue_free()
	for sys in systems:
		var line := SYS_LINE.instantiate()
		$V/Systems.add_child(line)
		line.build(String(sys["code"]), int(sys["boxes_max"]), String(sys["family"]))
		_lines.append(line)
	if systems.is_empty():
		var empty := SYS_LINE.instantiate()
		$V/Systems.add_child(empty)
		empty.build("NO SYSTEMS", 0, "hull")
		empty.paint(0, 0)


## Repaint from the same system dictionaries the sim mutates, so the plate and
## the damage model can never disagree about what is left.
func refresh(shield: float, shield_max: float, has_shield: bool = true) -> void:
	for i in range(_lines.size()):
		_lines[i].paint(int(_systems[i]["boxes"]), int(_systems[i]["boxes_max"]))
	if not has_shield:
		$V/Head/Arc.text = "NO SHIELD"
		return
	var frac: float = 0.0 if shield_max <= 0.0 else shield / shield_max
	$V/Head/Tag.add_theme_color_override("font_color", Palette.shield_color(frac))
