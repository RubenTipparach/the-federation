extends VBoxContainer

## One system on the ship systems display: its name, what is left of it, and
## one box per hit point wrapping six to a row, which is the layout the
## approved plate uses. Boxes are instanced from a committed scene and only
## painted here (CLAUDE.md 5.1).

const HIT_BOX := preload("res://scenes/ui/hit_box.tscn")

var _boxes: Array[Panel] = []
var _family: String = "hull"


## Build the box row once, when the fit changes. Painting per frame never
## touches the tree.
func build(sys_name: String, boxes_max: int, family: String) -> void:
	_family = family
	$Head/SysName.text = sys_name
	for child in $Boxes.get_children():
		child.queue_free()
	_boxes = []
	for i in range(boxes_max):
		var box: Panel = HIT_BOX.instantiate()
		$Boxes.add_child(box)
		_boxes.append(box)


func paint(cur: int, boxes_max: int) -> void:
	$Head/Count.text = "%d/%d" % [cur, boxes_max]
	var dead: bool = cur <= 0
	$Head/SysName.add_theme_color_override("font_color",
		Palette.CRIT if dead else Palette.FG)
	$Head/Count.add_theme_color_override("font_color",
		Palette.CRIT if dead else Palette.DIM)
	for i in range(_boxes.size()):
		_boxes[i].paint(i < cur, _family)
