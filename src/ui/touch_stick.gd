extends Control

## A virtual thumb stick for touch play. Reports a vector in the range -1 to 1
## and nothing else: what turning the ship or the camera means is decided by
## the screen that listens (CLAUDE.md 5.2). The knob is an authored node that
## this script only moves, never builds.
##
## Mouse events are handled as well as touch, so the control can be exercised
## on a desktop without a touchscreen.

signal moved(vector: Vector2)

## How far from the centre counts as full deflection.
const RADIUS: float = 56.0

var _active_touch: int = -1
var _vector: Vector2 = Vector2.ZERO


func caption(text: String) -> void:
	$Caption.text = text


func vector() -> Vector2:
	return _vector


func _ready() -> void:
	Paint.tint($Caption, "font_color", Palette.DIM)
	_set_vector(Vector2.ZERO)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _active_touch == -1:
			_active_touch = event.index
			_track(event.position)
		elif not event.pressed and event.index == _active_touch:
			_active_touch = -1
			_set_vector(Vector2.ZERO)
		accept_event()
	elif event is InputEventScreenDrag and event.index == _active_touch:
		_track(event.position)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_active_touch = -2
			_track(event.position)
		else:
			_active_touch = -1
			_set_vector(Vector2.ZERO)
		accept_event()
	elif event is InputEventMouseMotion and _active_touch == -2:
		_track(event.position)
		accept_event()


func _track(local_pos: Vector2) -> void:
	var offset: Vector2 = local_pos - size * 0.5
	if offset.length() > RADIUS:
		offset = offset.normalized() * RADIUS
	_set_vector(offset / RADIUS)


func _set_vector(v: Vector2) -> void:
	_vector = v
	var knob: Panel = $Knob
	knob.position = size * 0.5 - knob.size * 0.5 + v * RADIUS
	knob.modulate = Palette.CYAN if v.length() > 0.05 else Color(1, 1, 1, 0.7)
	moved.emit(v)
