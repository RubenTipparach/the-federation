extends CanvasLayer

## The things around the game: the debug overlay, and leaving.
##
## Summoned by the gear on the top bar, or by the gear at the foot of the fight
## strip, which is the only one reachable during a battle. Opening it there
## pauses, because CLAUDE.md 6.2 says the menu button is how a battle pauses.
##
## It owns no state. The overlay owns whether it is visible and the combat
## screen owns the battle; this file reads them and reports what the player
## pressed (5.2).
##
## Saved designs used to be here and are now in the shipyard, which is where a
## design is made. Settings is the things around the game, not part of it.

## The player asked to leave the battle from in here. Reported rather than
## done, for the same reason loading a design is: main owns the screens, and
## the combat screen already knows how to end a battle.
signal leave_requested
## Shut, by any of the four gestures that shut it. main listens so it can put
## a battle it paused back the way it found it.
signal closed

## Set by main so the overlay can be toggled from here without this file
## knowing where in the tree it lives.
var overlay: CanvasLayer


func _ready() -> void:
	visible = false
	# A CanvasLayer is not a Control, so the theme main sets on the screen root
	# stops here: this layer and everything under it would otherwise render in
	# Godot's default font. wear() below is how it is handed one, and painting
	# the two flat surfaces from the palette is the other half of the same job.
	$Dim.color = Palette.with_alpha(Palette.BG, 0.78)
	$Frame/Back.color = Palette.BG
	$Dim.gui_input.connect(_on_dim_input)
	$Frame/V/Head/Close.pressed.connect(close)
	$Frame/V/Scroll/Body/QuitRow/Quit.pressed.connect(_on_quit)
	$Frame/V/Scroll/Body/LeaveRow/Leave.pressed.connect(_on_leave)
	var toggle: Control = $Frame/V/Scroll/Body/DebugRow/Toggle
	toggle.setup(Palette.CYAN, true)
	toggle.level_picked.connect(_on_debug_picked)


## Wear a deck. Called by main whenever the faction's skin changes, because a
## CanvasLayer breaks theme inheritance and this panel would otherwise keep
## whatever it was born with. The two flat surfaces are repainted here too, so
## the backing and the dim cannot end up a skin behind the plate around them.
func wear(deck: Theme) -> void:
	$Frame.theme = deck
	$Dim.color = Palette.with_alpha(Palette.BG, 0.78)
	$Frame/Back.color = Palette.BG


## Leaving only exists while there is a battle to leave. Everything else in the
## panel is the same in both places.
func set_battle(on: bool) -> void:
	$Frame/V/Scroll/Body/LeaveRow.visible = on


func open() -> void:
	visible = true
	_paint_debug()


func close() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func toggle() -> void:
	if visible:
		close()
	else:
		open()


## Clicking the dim closes, which is the gesture every modal has and the reason
## the dim takes the mouse at all.
func _on_dim_input(event: InputEvent) -> void:
	var clicked: bool = (event is InputEventMouseButton
		and event.pressed and event.button_index == MOUSE_BUTTON_LEFT)
	if clicked or (event is InputEventScreenTouch and event.pressed):
		close()


## Escape closes. _unhandled_input rather than _input, so anything with focus
## inside the panel gets the key first.
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


# ---- instruments -------------------------------------------------------------


## The strip has one box, so picking any level is a toggle: clicking the lit box
## picks one less, which is zero. That is BoxStrip's own behaviour rather than
## anything special cased here.
func _on_debug_picked(level: int) -> void:
	if overlay != null:
		overlay.set_shown(level > 0)
	_paint_debug()


func _paint_debug() -> void:
	var on: bool = overlay != null and overlay.is_shown()
	$Frame/V/Scroll/Body/DebugRow/Toggle.paint(1 if on else 0, 1)
	var state: Label = $Frame/V/Scroll/Body/DebugRow/State
	state.text = "ON" if on else "OFF"
	Paint.tint(state, "font_color", Palette.CYAN if on else Palette.DIM)


# ---- session -----------------------------------------------------------------


## Quitting is the tree's job, not a screen's. On the web it does nothing
## visible; the row stays anyway, because a panel whose contents change between
## builds is a panel nobody can learn.
func _on_quit() -> void:
	get_tree().quit()


func _on_leave() -> void:
	close()
	leave_requested.emit()
