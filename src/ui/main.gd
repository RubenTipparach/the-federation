extends Control

## Application root: owns the session, wires the screens together, and prints
## the build smoke marker that scripts/verify-build.sh greps for. Screens
## never talk to each other directly; they signal, this file routes
## (dependency inversion, CLAUDE.md 4.2).

## Printed to stdout so an exported build can be verified headless. The
## verify script greps for this exact marker.
const SMOKE_MARKER := "FEDERATION_SMOKE_OK"

var session: Session
## Whether opening the settings panel is what paused the battle behind it. A
## battle the player had already paused has to still be paused when the panel
## shuts, so this records who did it rather than assuming.
var _paused_for_settings: bool = false


func _ready() -> void:
	session = Session.create()
	$Root/Content/Fitting.bind_session(session)
	$Root/Content/Arcs.bind_session(session)
	$Root/Content/Skirmish.bind_session(session)
	$Root/Content/Skirmish.replay_chosen.connect(_on_replay_chosen)
	$Root/Content/Combat.bind_session(session)

	$Root/TopBar/TabFitting.pressed.connect(show_tab.bind("Fitting"))
	$Root/TopBar/TabArcs.pressed.connect(show_tab.bind("Arcs"))
	$Root/TopBar/TabSkirmish.pressed.connect(show_tab.bind("Skirmish"))

	$Root/Content/Fitting.design_changed.connect(_on_design_changed)
	$Root/Content/Fitting.design_chosen.connect(_on_design_loaded)
	$Root/Content/Arcs.design_changed.connect(_on_design_changed)
	$Root/Content/Skirmish.design_selected.connect(_on_design_selected)
	$Root/Content/Skirmish.begin_battle.connect(_on_begin_battle)
	$Root/Content/Combat.battle_ended.connect(_on_battle_ended)

	# Settings hangs off the top bar rather than being a fourth tab: the tabs are
	# where the game is, and this is where the things around the game are. It is
	# handed the overlay because its instrument switch is what turns that on.
	$Settings.overlay = $DebugPanel
	$Settings.leave_requested.connect(_on_settings_leave)
	$Settings.closed.connect(_on_settings_closed)
	$Root/TopBar/Settings.pressed.connect(_on_topbar_settings)
	# The gear at the foot of the fight strip. Two buttons, one panel: the top
	# bar is hidden for the whole engagement, so without this there is no way to
	# reach a menu once a battle has started.
	$Root/Content/Combat.settings_requested.connect(_on_combat_settings)

	_wear_deck()
	show_tab("Fitting")
	_print_smoke_report()


## Wear the deck of the navy that built the hull in the session.
##
## Both halves of a skin move together or the interface lies: Palette serves
## the lit readouts, the generated theme carries the plates the readouts sit
## on, and Palette.theme_path names the theme built from the same skin, so
## there is no way to end up with gunmetal plates behind phosphor numbers.
##
## Set on this node because it is the Control every screen hangs under, which
## makes the swap one assignment rather than a walk.
func _wear_deck() -> void:
	Palette.use_faction(session.faction())
	var deck: Theme = load(Palette.theme_path())
	if theme != deck:
		theme = deck
	# The two overlays hang off CanvasLayers, which are not Controls, so the
	# theme above does not reach them. Settings is handed it; the debug overlay
	# is deliberately not, because an instrument that changed appearance with
	# the deck would be one more thing to doubt when a reading looks wrong.
	$Settings.wear(deck)


func _on_topbar_settings() -> void:
	if $Settings.visible:
		$Settings.close()
		return
	$Settings.set_battle(false)
	$Settings.open()


## The gear on the fight strip. CLAUDE.md 6.2: the menu button is how a battle
## pauses, so opening it does, and shutting it puts the battle back exactly as
## it was found.
func _on_combat_settings() -> void:
	if $Settings.visible:
		$Settings.close()
		return
	_paused_for_settings = $Root/Content/Combat.set_paused(true)
	$Settings.set_battle($Root/Content/Combat.in_battle())
	$Settings.open()


func _on_settings_closed() -> void:
	if _paused_for_settings:
		$Root/Content/Combat.set_paused(false)
		_paused_for_settings = false


## Leaving from the panel is the same ending the tactical view's Disengage
## gives, through the same call. Two exits that both claim to be a
## disengagement would be two things to keep in step (CLAUDE.md 4.1).
func _on_settings_leave() -> void:
	_paused_for_settings = false
	$Root/Content/Combat.leave_battle()


## A design loaded in the shipyard replaces the one in the session, which is
## the same thing picking a hull does. Routed here rather than done in the
## screen because main owns the session and the three other screens that have
## to repaint (CLAUDE.md 4.2).
func _on_design_loaded(fit: ShipFit) -> void:
	session.fit = fit
	_wear_deck()
	$Root/Content/Fitting.refresh_from_session()
	$Root/Content/Arcs.refresh()
	$Root/Content/Skirmish.refresh()


func show_tab(tab: String) -> void:
	for screen_name in ["Fitting", "Arcs", "Skirmish", "Combat"]:
		$Root/Content.get_node(screen_name).visible = screen_name == tab
	# The tabs are hidden for the whole battle rather than deleted: they are
	# global chrome that the other three screens still navigate by, and a
	# battle should be left by ending it, not by wandering off mid engagement
	# (CLAUDE.md 6.2).
	$Root/TopBar.visible = tab != "Combat"
	$Root/TopBar/TabFitting.button_pressed = tab == "Fitting"
	$Root/TopBar/TabArcs.button_pressed = tab == "Arcs"
	$Root/TopBar/TabSkirmish.button_pressed = tab == "Skirmish"
	if tab == "Arcs":
		$Root/Content/Arcs.refresh()
	elif tab == "Skirmish":
		$Root/Content/Skirmish.refresh()


func _on_design_changed() -> void:
	# The fit lives in the session; every screen just repaints from it.
	if $Root/Content/Arcs.visible:
		$Root/Content/Arcs.refresh()
	if $Root/Content/Skirmish.visible:
		$Root/Content/Skirmish.refresh()


func _on_design_selected(hull_id: String) -> void:
	if hull_id != session.fit.hull_id:
		session.fit = ShipFit.create_default(hull_id)
	# The hull names the navy and the navy names the deck, so picking a ship is
	# also picking a console. Done before the screens repaint, so they repaint
	# once, in the skin they are about to be wearing.
	_wear_deck()
	$Root/Content/Fitting.refresh_from_session()
	$Root/Content/Skirmish.refresh()


func _on_begin_battle() -> void:
	show_tab("Combat")
	$Root/Content/Combat.start_battle()


func _on_replay_chosen(log: BattleLog) -> void:
	show_tab("Combat")
	$Root/Content/Combat.start_replay(log)


func _on_battle_ended() -> void:
	# The session's hull may have changed on the way out (a prize taken), and
	# the deck follows the hull.
	Palette.use_faction(session.faction())
	$Root/Content/Fitting.refresh_from_session()
	show_tab("Skirmish")


## Number keys switch screens; 4 starts a battle. Useful for players and for
## driving the exported web build from automation.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				show_tab("Fitting")
			KEY_2:
				show_tab("Arcs")
			KEY_3:
				show_tab("Skirmish")
			KEY_4:
				_on_begin_battle()


func _print_smoke_report() -> void:
	var lines: Array[String] = [
		"THE FEDERATION",
		"Prototype: fitting, arcs, skirmish, 3d combat.",
		"Engine:    %s" % Engine.get_version_info().get("string", "unknown"),
		"Platform:  %s" % OS.get_name(),
		"Debug:     %s" % ("yes" if OS.is_debug_build() else "no"),
	]
	for line in lines:
		print(line)
	print(SMOKE_MARKER)
