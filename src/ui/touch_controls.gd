extends Control

## The touch overlay: a helm stick on the left, a camera stick on the right,
## and target cycling. Mobile is a testing surface for this game, not the
## primary one, so this is deliberately the smallest control set that makes a
## battle playable with two thumbs.
##
## It reports intent and holds no state about the battle (CLAUDE.md 5.2). The
## combat screen decides what turning, orbiting, and cycling actually do, using
## the same paths the desktop buttons use.

signal helm_moved(vector: Vector2)
signal camera_moved(vector: Vector2)
signal target_stepped(step: int)


func _ready() -> void:
	$Helm.caption("HELM")
	$Camera.caption("CAMERA")
	$Helm.moved.connect(func(v: Vector2) -> void: helm_moved.emit(v))
	$Camera.moved.connect(func(v: Vector2) -> void: camera_moved.emit(v))
	$Targeting/Prev.pressed.connect(func() -> void: target_stepped.emit(-1))
	$Targeting/Next.pressed.connect(func() -> void: target_stepped.emit(1))
	Paint.tint($Targeting/Label, "font_color", Palette.DIM)


## Shown only where there is a touchscreen. A desktop player never sees it,
## and a phone or a tablet browser always does.
static func wanted() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


func set_target_label(text: String) -> void:
	$Targeting/Label.text = text
