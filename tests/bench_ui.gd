extends SceneTree

## What the interface costs per frame, in microseconds of CPU.
##
## This exists because the question "why is it slow on my phone" could not be
## answered by anything else available. The headless screenshot harness runs on
## a software rasteriser which is fill bound at around 130 milliseconds a frame
## whatever the game does, so every switch in the debug overlay measured the
## same number and the interface hid behind that floor completely. Timing the
## calls directly with Time.get_ticks_usec() has no rasteriser in it at all.
##
## What it found, on a desktop, before any of it was fixed:
##
##   _refresh_hud                5524 us     against a 16666 us frame at 60fps
##   _position_ship_labels        973 us     and this one ran EVERY frame
##   battle.step                  225 us     the entire simulation, for scale
##
## So the interface cost twenty nine times the simulation, and could not have
## held sixty frames a second on the machine it was developed on, let alone a
## phone. Two causes, both measured below in the primitives section:
##
##   add_theme_color_override does NOT compare before applying, and costs 37
##   microseconds. Label.text DOES compare, and costs 0.2 when unchanged. The
##   station tab strips called the former eighty times a tick for colours that
##   change a handful of times in a battle. See src/ui/paint.gd.
##
##   get_global_mouse_position is a DisplayServer round trip to the operating
##   system, 190 microseconds, and hover picking called it once a frame along
##   with the local variant at 151. See _pointer_at in combat_screen.gd.
##
## Run it with scripts/bench-ui.sh. It is a regression instrument: a number
## that jumps here is a frame the player will lose, long before it is visible
## as a dropped frame on any machine a developer owns.

## Iterations per measurement. High enough that a single slow call cannot move
## the average, low enough that the whole run stays under a minute.
const ROUNDS: int = 300
const PRIMITIVE_ROUNDS: int = 20000
## The frame budget the numbers are quoted against.
const FRAME_US: float = 1000000.0 / 60.0


func _time(what: String, rounds: int, body: Callable) -> float:
	# Warm first: the first calls pay for theme caches and text buffers that
	# every later frame gets for free, and charging those to the steady state
	# would overstate it.
	for i in range(mini(rounds / 10, 200)):
		body.call()
	var t0: int = Time.get_ticks_usec()
	for i in range(rounds):
		body.call()
	var us: float = float(Time.get_ticks_usec() - t0) / float(rounds)
	print("  %-40s %9.2f us" % [what, us])
	return us


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.show_tab("Combat")
	main._on_begin_battle()
	for i in range(30):
		await process_frame

	var c: Node = main.get_node("Root/Content/Combat")
	var me: ShipState = c.battle.player()
	var foe: ShipState = c.battle.enemy()

	print("")
	print("PER FRAME")
	var hud: float = _time("_refresh_hud (at the HUD rate)", ROUNDS,
		func() -> void: c._refresh_hud())
	var pos: float = _time("_position_ship_labels (every frame)", ROUNDS,
		func() -> void: c._position_ship_labels())
	var sim: float = _time("battle.step (the simulation, for scale)", ROUNDS,
		func() -> void: c.battle.step(1.0 / 60.0))

	print("")
	print("INSIDE _refresh_hud")
	_time("_sync_fire_buttons", ROUNDS, func() -> void: c._sync_fire_buttons())
	_time("_refresh_target_readout", ROUNDS,
		func() -> void: c._refresh_target_readout(me, foe))
	_time("SSD, own ship", ROUNDS,
		func() -> void: c.get_node("Right/OwnPanel/V/Display").refresh())
	_time("SSD, target", ROUNDS,
		func() -> void: c.get_node("Right/TargetDisplayPanel/V/Display").refresh())
	_time("FightTabs.refresh (6 tabs)", ROUNDS,
		func() -> void: c.get_node("Right/FightStation/FightTabs").refresh(me.systems, me.repair_queue))
	_time("KeepTabs.refresh (4 tabs)", ROUNDS,
		func() -> void: c.get_node("Left/KeepStation/KeepTabs").refresh(me.systems, me.repair_queue))
	_time("FightPanel.refresh (open station)", ROUNDS,
		func() -> void: c.get_node("Right/FightStation/FightPanel").refresh())
	_time("KeepPanel.refresh (open station)", ROUNDS,
		func() -> void: c.get_node("Left/KeepStation/KeepPanel").refresh())

	print("")
	print("THE REST OF THE PER FRAME PATH")
	# Everything _physics_process does besides repainting panels. Added because
	# the overlay's per part timings summed to about a twelfth of the script
	# time it reported, so most of the frame is spent somewhere the panel
	# timings cannot see, and guessing where would have been the same mistake
	# twice.
	var w: Node3D = c._world()
	var no_events: Array[Dictionary] = []
	_time("_world().update_visuals", ROUNDS,
		func() -> void: w.update_visuals(1.0 / 60.0, 1.0 / 60.0, no_events))
	_time("_world().follow_pivot", ROUNDS,
		func() -> void: w.follow_pivot(1.0 / 60.0))
	_time("_track_plan_camera", ROUNDS, func() -> void: c._track_plan_camera())
	_time("_apply_debug (every frame)", ROUNDS, func() -> void: c._apply_debug())
	_time("_apply_sticks", ROUNDS, func() -> void: c._apply_sticks(1.0 / 60.0))
	_time("_refresh_target_label", ROUNDS, func() -> void: c._refresh_target_label())

	print("")
	print("INSIDE _position_ship_labels")
	var world: Node3D = c._world()
	var stack: Control = c.get_node("Mid/ViewPanel/Stack")
	_time("_refresh_brackets", ROUNDS,
		func() -> void: c._refresh_brackets(world, stack))
	_time("_ship_under_mouse (hover pick)", ROUNDS,
		func() -> void: var _i: int = c._ship_under_mouse())

	print("")
	print("PRIMITIVES, which is where the cost came from")
	var probe: Label = c.get_node("Left/DamagePanel/V/BodyScroll/Body")
	var n: int = 0
	_time("Label.text, value changed", PRIMITIVE_ROUNDS, func() -> void:
		n += 1
		probe.text = "sample %d" % n)
	_time("Label.text, value unchanged", PRIMITIVE_ROUNDS,
		func() -> void: probe.text = "steady")
	var raw: float = _time("add_theme_color_override, unguarded", PRIMITIVE_ROUNDS,
		func() -> void: probe.add_theme_color_override("font_color", Palette.FG))
	var guarded: float = _time("Paint.tint, same colour", PRIMITIVE_ROUNDS,
		func() -> void: Paint.tint(probe, "font_color", Palette.FG))

	print("")
	print("SUMMARY")
	print("  interface per frame at 60Hz HUD   %9.2f us" % (hud + pos))
	print("  simulation per frame              %9.2f us" % sim)
	print("  interface is                      %9.1fx the simulation" % ((hud + pos) / maxf(sim, 0.001)))
	print("  share of a 60fps frame            %9.1f%%" % ((hud + pos) / FRAME_US * 100.0))
	print("  Paint.tint saves                  %9.1fx per colour" % (raw / maxf(guarded, 0.001)))
	print("")
	print("BENCH_DONE")
	quit()
