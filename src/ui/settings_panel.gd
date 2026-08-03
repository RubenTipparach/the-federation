extends CanvasLayer

## The things around the game: saved designs, the debug overlay, and leaving.
##
## Summoned by the gear on the top bar, which means it is not reachable during
## a battle, which is deliberate. A battle is left by ending it (CLAUDE.md 6.2)
## and DISENGAGE in the tactical view is how, so this never becomes a second
## way to wander off mid engagement.
##
## It owns no state. The designs live in DesignStore, the fit lives in the
## session, and the overlay owns whether it is visible; this file reads those
## three and reports what the player pressed (5.2). That is why loading a
## design is a signal rather than an assignment: main owns the session and the
## repaint that follows, and a panel that reached in and swapped the fit would
## be a second place that knows how to do it.

signal design_chosen(fit: ShipFit)
## The player asked to leave the battle from in here. Reported rather than
## done, for the same reason loading a design is: main owns the screens, and
## the combat screen already knows how to end a battle.
signal leave_requested
## Shut, by any of the four gestures that shut it. main listens so it can put
## a battle it paused back the way it found it.
signal closed

const SELECT_CARD: PackedScene = preload("res://scenes/ui/select_card.tscn")

## Set by main, because the panel needs a fit to save and does not own one.
var session: Session

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
	$Frame/V/Scroll/Body/SaveRow/Save.pressed.connect(_on_save)
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


## What the panel offers differs inside a battle and out of it.
##
## Designs go away, because you cannot refit a ship under fire and a Load
## button that silently did nothing would be worse than no button. Leaving
## appears, because it is only a thing you can do when there is something to
## leave. The instruments and the quit stay put in both, so the two shapes are
## the same panel with one group swapped rather than two panels.
func set_battle(on: bool) -> void:
	var body: Node = $Frame/V/Scroll/Body
	for id in ["DesignsHead", "DesignList", "NoDesigns", "SaveRow"]:
		body.get_node(id).visible = not on
	body.get_node("LeaveRow").visible = on


func open() -> void:
	visible = true
	if $Frame/V/Scroll/Body/DesignsHead.visible:
		_fill_designs()
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


# ---- designs -----------------------------------------------------------------


## Every saved design, newest first. Cards are instanced from the committed
## scene, which is what CLAUDE.md 5.1 allows and what the skirmish screen's
## recordings list already does: the number of rows is data, so the rows cannot
## be authored, but the row itself is.
func _fill_designs() -> void:
	var list: VBoxContainer = $Frame/V/Scroll/Body/DesignList
	for child in list.get_children():
		child.queue_free()
	var paths: Array[String] = DesignStore.list_paths()
	var shown: int = 0
	for path in paths:
		var fit: ShipFit = DesignStore.read(path)
		if fit == null:
			continue
		var card: Button = SELECT_CARD.instantiate()
		list.add_child(card)
		card.setup(path, String(fit.hull()["name"]),
			"%s / saved %s" % [DesignStore.describe(fit),
				_when(DesignStore.stamp_of(path))],
			Palette.CYAN)
		card.allow_delete(true)
		card.chosen.connect(func(_id: String) -> void:
			design_chosen.emit(fit)
			close())
		card.delete_requested.connect(_on_delete)
		shown += 1
	$Frame/V/Scroll/Body/NoDesigns.visible = shown == 0


## A saved time a player can place. The date only once it is not today, because
## "14:22" is what you want for the one you saved a minute ago and a full
## timestamp on every row is a wall of digits.
func _when(stamp: int) -> String:
	if stamp <= 0:
		return "unknown"
	var then: Dictionary = Time.get_datetime_dict_from_unix_time(stamp)
	var now: Dictionary = Time.get_datetime_dict_from_unix_time(
		int(Time.get_unix_time_from_system()))
	var clock: String = "%02d:%02d" % [int(then["hour"]), int(then["minute"])]
	if int(then["year"]) == int(now["year"]) and int(then["month"]) == int(now["month"]) \
			and int(then["day"]) == int(now["day"]):
		return clock
	return "%04d-%02d-%02d %s" % [
		int(then["year"]), int(then["month"]), int(then["day"]), clock]


func _on_save() -> void:
	if session == null:
		return
	DesignStore.save(session.fit, int(Time.get_unix_time_from_system()))
	_fill_designs()


func _on_delete(path: String) -> void:
	DesignStore.remove(path)
	_fill_designs()


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


## Quitting is the tree's job, not a screen's. On the web this does nothing
## visible, which is why the button says so rather than being hidden: a panel
## whose contents change between builds is a panel nobody can learn.
func _on_quit() -> void:
	get_tree().quit()


func _on_leave() -> void:
	close()
	leave_requested.emit()
