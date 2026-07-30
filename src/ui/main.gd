extends Control

## Application root: owns the session, wires the screens together, and prints
## the build smoke marker that scripts/verify-build.sh greps for. Screens
## never talk to each other directly; they signal, this file routes
## (dependency inversion, CLAUDE.md 4.2).

## Printed to stdout so an exported build can be verified headless. The
## verify script greps for this exact marker.
const SMOKE_MARKER := "FEDERATION_SMOKE_OK"

var session: Session


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
	$Root/Content/Arcs.design_changed.connect(_on_design_changed)
	$Root/Content/Skirmish.design_selected.connect(_on_design_selected)
	$Root/Content/Skirmish.begin_battle.connect(_on_begin_battle)
	$Root/Content/Combat.battle_ended.connect(_on_battle_ended)

	show_tab("Fitting")
	_print_smoke_report()


func show_tab(tab: String) -> void:
	for screen_name in ["Fitting", "Arcs", "Skirmish", "Combat"]:
		$Root/Content.get_node(screen_name).visible = screen_name == tab
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
	$Root/Content/Fitting.refresh_from_session()
	$Root/Content/Skirmish.refresh()


func _on_begin_battle() -> void:
	show_tab("Combat")
	$Root/Content/Combat.start_battle()


func _on_replay_chosen(log: BattleLog) -> void:
	show_tab("Combat")
	$Root/Content/Combat.start_replay(log)


func _on_battle_ended() -> void:
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
