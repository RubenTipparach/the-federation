extends HBoxContainer

## The tactical combat screen. Owns no rules: it steps a Battle, forwards
## orders, and paints what the sim says. The 3D world and the plan inset
## render the same World3D, so there is one battle display, seen twice.

signal battle_ended

const WEAPON_ROW := preload("res://scenes/ui/weapon_row.tscn")

var session: Session
var battle: Battle
var paused: bool = false
var _weapon_rows: Array = []
var _dragging: bool = false
var _drag_moved: float = 0.0
var _report_lines: Array[String] = []
var _wired: bool = false

## Set while watching a recording. The battle is driven by the log's commands
## instead of the player's, and the same tactical view renders it: a replay is
## the combat screen in another mode, never a second screen (CLAUDE.md 4.1).
var replay_log: BattleLog = null
var replay_speed: float = 1.0


## Called every time the player enters combat. The session is swapped each
## time, the wiring happens once: every connection below is to a node that
## outlives the battle, and connecting them again on the second visit stacked
## duplicate handlers (the sticks made this visible by erroring, the lambdas
## and bound callables were duplicating silently).
func bind_session(p_session: Session) -> void:
	session = p_session
	if _wired:
		return
	_wired = true
	var world: Node3D = _world()
	var cam: Dictionary = Catalog.tuning()["camera"]
	$Mid/CamRow/Pitch.min_value = float(cam["pitch_floor_deg"])
	$Mid/CamRow/Pitch.max_value = float(cam["pitch_ceil_deg"])
	$Mid/CamRow/Pitch.value_changed.connect(func(v: float) -> void:
		world.set_pitch(v)
		_sync_pitch_ui())
	var presets: Dictionary = cam["presets"]
	$Mid/CamRow/Tactical.pressed.connect(_set_pitch_preset.bind(float(presets["tactical"])))
	$Mid/CamRow/Cinematic.pressed.connect(_set_pitch_preset.bind(float(presets["cinematic"])))
	$Mid/CamRow/Plan.pressed.connect(_set_pitch_preset.bind(float(presets["plan"])))

	$Mid/Actions/FireBeams.pressed.connect(_fire_beams)
	$Mid/Actions/FireHeavy.pressed.connect(_fire_heavy)
	$Mid/Actions/Reinforce.pressed.connect(_reinforce)
	$Mid/Actions/ComeAbout.pressed.connect(_come_about)
	$Mid/Actions/Pause.pressed.connect(_toggle_pause)
	$Mid/Actions/Disengage.pressed.connect(_end_battle.bind("Disengaged"))
	$Mid/ViewPanel/Stack/EndOverlay/P/V/Return.pressed.connect(
		func() -> void: battle_ended.emit())

	$Left/ShipPanel/V/Throttle/Slider.value_changed.connect(func(v: float) -> void:
		if battle != null:
			battle.apply_command(0, "order", [battle.player().ordered_heading, v]))
	for sink in ["Weapons", "Shields", "Engines", "Systems", "Reserve"]:
		var slider: HSlider = $Left/PowerPanel/V.get_node(sink + "/Slider")
		slider.value_changed.connect(_on_power_slider.bind(sink.to_lower()))

	var container: SubViewportContainer = $Mid/ViewPanel/Stack/ViewContainer
	container.gui_input.connect(_on_view_input)

	# The plan inset renders the same world as the main view: one scene, two
	# cameras, so the tactical picture cannot diverge from the pretty one.
	var inset: SubViewport = $Mid/ViewPanel/Stack/InsetFrame/InsetContainer/Inset
	# find_world_3d(), not world_3d: an unassigned SubViewport's world_3d
	# property is null (both viewports were silently falling back to the root
	# window's world, which happened to work). find_world_3d resolves the world
	# actually in use, so the sharing is explicit instead of coincidental.
	inset.world_3d = ($Mid/ViewPanel/Stack/ViewContainer/View as SubViewport).find_world_3d()
	# cull_mask 1 on this camera, set in the scene, is what keeps the weapon arc
	# wedges and range rings out of the inset. See assets/materials/
	# env_plan_inset.tres for the layer convention.
	var plan_cam: Camera3D = inset.get_node("PlanCamera")
	plan_cam.size = float(cam["plan_inset_size"])
	_track_plan_camera()

	# Touch play. The sticks and the target buttons drive the same paths the
	# desktop controls do, so mobile is a second surface on one implementation
	# rather than a second control scheme (CLAUDE.md 4.1).
	var touch: Control = $Mid/ViewPanel/Stack/TouchControls
	touch.visible = touch.wanted()
	touch.helm_moved.connect(_on_helm_stick)
	touch.camera_moved.connect(_on_camera_stick)
	touch.target_stepped.connect(_step_target)

	var bar: Control = $Mid/ReplayBar
	bar.get_node("Play").pressed.connect(_toggle_pause)
	bar.get_node("Restart").pressed.connect(func() -> void: seek_replay(0))
	bar.get_node("Leave").pressed.connect(func() -> void: battle_ended.emit())
	for speed in [1, 2, 4]:
		bar.get_node("Speed%d" % speed).pressed.connect(
			_set_replay_speed.bind(float(speed)))
	bar.get_node("Scrub").value_changed.connect(func(v: float) -> void:
		if replay_log != null and absi(int(v) - battle.tick) > 1:
			seek_replay(int(v)))



func _world() -> Node3D:
	return $Mid/ViewPanel/Stack/ViewContainer/View/World


## Watch a recording. The view, the HUD, and the comm log are the live ones.
func start_replay(log: BattleLog) -> void:
	replay_log = log
	battle = log.replay_setup()
	_world().bind_battle(battle)
	paused = false
	replay_speed = 1.0
	_report_lines = []
	$Mid/Actions/Pause.text = "Pause"
	$Mid/ViewPanel/Stack/EndOverlay.visible = false
	_build_weapon_rows()
	_sync_pitch_ui()
	_refresh_hud()
	_sync_replay_bar()


func start_battle() -> void:
	replay_log = null
	$Mid/ReplayBar.visible = false
	battle = Battle.create_duel(session.fit.duplicate_fit(), session.enemy_hull_id,
		int(Time.get_ticks_usec()) % 1000000007)
	# Every battle is recorded. A log is small, it is written from the one
	# command path, and it is the difference between "it did something odd"
	# and a bug someone else can reproduce (docs/11).
	battle.log = BattleLog.create(battle.player().fit, session.enemy_hull_id,
		battle.seed_value, float(Catalog.tuning()["combat"]["replay_step"]))
	battle.apply_command(0, "order", [battle.player().heading,
		float($Left/ShipPanel/V/Throttle/Slider.value)])
	_world().bind_battle(battle)
	paused = false
	_report_lines = []
	$Mid/Actions/Pause.text = "Pause"
	$Mid/ViewPanel/Stack/EndOverlay.visible = false
	_build_weapon_rows()
	_sync_pitch_ui()
	_refresh_hud()


func _build_weapon_rows() -> void:
	var list: VBoxContainer = $Right/WeaponsPanel/V/WeaponList
	for child in list.get_children():
		child.queue_free()
	_weapon_rows = []
	for i in range(battle.player().weapons_rt.size()):
		var row: HBoxContainer = WEAPON_ROW.instantiate()
		list.add_child(row)
		_weapon_rows.append(row)


## Keep the plan inset looking straight down at the midpoint between the two
## ships. It used to be nailed to the world origin, which meant that once the
## pair drifted toward a corner of the arena they sat jammed against the edge
## of a 128 pixel readout with most of it empty.
##
## The size is deliberately fixed rather than zoomed to fit: a display whose
## scale changes under you is hard to read distance off, and at this size the
## fixed frame already holds the two ships apart at almost any separation they
## reach. So the inset pans and never zooms.
func _track_plan_camera() -> void:
	if battle == null:
		return
	var mid: Vector2 = (battle.player().pos + battle.enemy().pos) * 0.5
	var cam: Camera3D = $Mid/ViewPanel/Stack/InsetFrame/InsetContainer/Inset/PlanCamera
	cam.look_at_from_position(
		Vector3(mid.x, 60, mid.y), Vector3(mid.x, 0, mid.y), Vector3(0, 0, 1))


func _physics_process(delta: float) -> void:
	if battle == null or not visible:
		return
	_apply_sticks(delta)
	var events: Array[Dictionary] = []
	if replay_log != null:
		events = _step_replay(delta)
	elif not paused and not battle.over:
		events = battle.step(delta)
	_world().update_visuals(delta, events)
	_world().follow_pivot(delta)
	_track_plan_camera()
	for e in events:
		# Every event that narrates itself gets narrated: shots, launches,
		# interceptions, and drones running out of fuel.
		if e.has("log"):
			for line in e["log"]:
				_note(String(line))
		if String(e["type"]) == "end":
			_show_end(int(e["winner"]))
	_refresh_hud()
	_refresh_target_label()
	_position_ship_labels()



## Clicking to one side of the ship turns it that way. The ship is the anchor,
## so the gesture is "come left" or "come right" rather than "fly to this
## point", which is what a helm order actually is.
func _helm_click(at: Vector2) -> void:
	var me: ShipState = battle.player()
	var here: Vector2 = _world().screen_pos(me.pos)
	var step: float = float(Catalog.tuning()["combat"]["helm_click_turn_deg"])
	var side: float = 1.0 if at.x >= here.x else -1.0
	var heading: float = me.ordered_heading + side * step
	if battle.apply_command(0, "order", [heading, me.ordered_throttle]):
		_note("Helm: come %s to %03d" % [
			"starboard" if side > 0.0 else "port", int(Sectors.wrap_deg(heading))])


# ---- replay ------------------------------------------------------------------

## Drive the battle from the log rather than from the player. Steps are the
## log's fixed dt, so what is watched is exactly what was recorded; speed just
## runs more of them per frame.
func _step_replay(delta: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if paused or battle.over or battle.tick >= replay_log.end_tick:
		_sync_replay_bar()
		return events
	var budget: float = delta * replay_speed
	var steps: int = maxi(1, int(budget / replay_log.dt))
	for i in range(steps):
		if battle.over or battle.tick >= replay_log.end_tick:
			break
		for c in replay_log.commands_at(battle.tick):
			battle.apply_command(int(c[1]), String(c[2]), c[3], false)
		events.append_array(battle.step(replay_log.dt))
	_sync_replay_bar()
	return events


## Jump to a tick by replaying to it from the start. The simulation is cheap
## and this is the only way a scrub can land on the same state the recording
## had: there is no snapshot to restore, by design (docs/11).
func seek_replay(tick: int) -> void:
	if replay_log == null:
		return
	battle = replay_log.replay_setup()
	var target: int = clampi(tick, 0, replay_log.end_tick)
	while battle.tick < target and not battle.over:
		for c in replay_log.commands_at(battle.tick):
			battle.apply_command(int(c[1]), String(c[2]), c[3], false)
		battle.step(replay_log.dt)
	_world().bind_battle(battle)
	_build_weapon_rows()
	_refresh_hud()
	_sync_replay_bar()


func _sync_replay_bar() -> void:
	var bar: Control = $Mid/ReplayBar
	bar.visible = replay_log != null
	if replay_log == null:
		return
	var seconds: float = float(battle.tick) * replay_log.dt
	var total: float = float(replay_log.end_tick) * replay_log.dt
	bar.get_node("Where").text = "TICK %d / %d   %0.1fs / %0.1fs" % [
		battle.tick, replay_log.end_tick, seconds, total]
	var scrub: HSlider = bar.get_node("Scrub")
	scrub.max_value = maxf(1.0, float(replay_log.end_tick))
	if not scrub.has_focus():
		scrub.set_value_no_signal(float(battle.tick))


# ---- touch ------------------------------------------------------------------

## Held stick positions, applied every frame in _process so a thumb resting on
## the stick keeps turning rather than turning once per input event.
var _helm_stick: Vector2 = Vector2.ZERO
var _camera_stick: Vector2 = Vector2.ZERO


func _on_helm_stick(v: Vector2) -> void:
	_helm_stick = v


func _on_camera_stick(v: Vector2) -> void:
	_camera_stick = v


## Left stick turns the ship, right stick moves the camera. Both go through
## the same helm order and the same camera clamp the mouse uses.
func _apply_sticks(delta: float) -> void:
	var cam: Dictionary = Catalog.tuning()["camera"]
	if absf(_helm_stick.x) > 0.12 and _can_command():
		var me: ShipState = battle.player()
		battle.apply_command(0, "order", [me.ordered_heading + _helm_stick.x
			* float(cam["stick_turn_deg_per_sec"]) * delta, me.ordered_throttle])
	if _camera_stick.length() > 0.12:
		var speed: float = float(cam["stick_orbit_deg_per_sec"]) * delta
		_world().orbit(_camera_stick.x * speed, -_camera_stick.y * speed)


## Cycle the target the player is shooting at. With one hostile this reports
## the only choice; the sim already supports several.
func _step_target(step: int) -> void:
	if battle == null:
		return
	var me: ShipState = battle.player()
	var foes: Array[ShipState] = battle.foes_of(me)
	if foes.is_empty():
		return
	var current: int = maxi(0, foes.find(battle.target_for(me)))
	var next: int = posmod(current + step, foes.size())
	battle.apply_command(0, "target", [battle.ships.find(foes[next])])
	_note("Target: %s" % String(foes[next].fit.hull()["name"]))
	_refresh_target_label()


func _refresh_target_label() -> void:
	var touch: Control = $Mid/ViewPanel/Stack/TouchControls
	if battle == null or not touch.visible:
		return
	var me: ShipState = battle.player()
	var foes: Array[ShipState] = battle.foes_of(me)
	var index: int = maxi(0, foes.find(battle.target_for(me)))
	touch.set_target_label("TARGET %d/%d" % [index + 1, maxi(1, foes.size())])


# ---- orders ------------------------------------------------------------------

func _on_view_input(event: InputEvent) -> void:
	if battle == null:
		return
	var world: Node3D = _world()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_moved = 0.0
		else:
			if _dragging and _drag_moved < 6.0 and _can_command():
				_helm_click(event.position)
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		_drag_moved += event.relative.length()
		if _drag_moved >= 6.0:
			var cam: Dictionary = Catalog.tuning()["camera"]
			var speed: float = float(cam["orbit_speed"])
			world.orbit(-event.relative.x * speed, event.relative.y * speed)
			_sync_pitch_ui()


func _set_pitch_preset(deg: float) -> void:
	_world().set_pitch(deg)
	_sync_pitch_ui()


func _sync_pitch_ui() -> void:
	var world: Node3D = _world()
	$Mid/CamRow/Pitch.set_value_no_signal(world.pitch())
	$Mid/CamRow/PitchOut.text = "%d deg" % int(world.pitch())
	$Mid/CamRow/FloorNote.visible = world.at_pitch_floor()
	$Mid/CamRow/FloorNote.add_theme_color_override("font_color", Palette.AMBER)


func _on_power_slider(value: float, sink: String) -> void:
	if battle != null:
		battle.apply_command(0, "power", [sink, value])


## Sim mutating commands are gated on pause and battle end, matching the
## step gate: firing into a frozen battle applied damage while time stood
## still, which the review caught.
func _can_command() -> bool:
	return battle != null and not paused and not battle.over and replay_log == null


func _fire_beams() -> void:
	if not _can_command():
		return
	var n: int = 1 if battle.apply_command(0, "fire_family", ["beam"]) else 0
	n += 1 if battle.apply_command(0, "fire_family", ["disruptor"]) else 0
	if n == 0:
		_note("No beam or disruptor bears")


func _fire_heavy() -> void:
	if not _can_command():
		return
	var n: int = 1 if battle.apply_command(0, "fire_family", ["torpedo"]) else 0
	n += 1 if battle.apply_command(0, "fire_family", ["lance"]) else 0
	n += 1 if battle.apply_command(0, "fire_family", ["drone"]) else 0
	if n == 0:
		_note("No heavy weapon bears")


func _reinforce() -> void:
	if not _can_command():
		return
	var me: ShipState = battle.player()
	var facing: int = me.weakest_facing()
	if battle.apply_command(0, "reinforce", [facing]):
		_note("Reinforced shield #%d from the battery" % (facing + 1))
	else:
		_note("Battery not charged")


func _come_about() -> void:
	if not _can_command():
		return
	var me: ShipState = battle.player()
	battle.apply_command(0, "order", [me.ordered_heading + 180.0, me.ordered_throttle])
	_note("Helm: coming about")


func _set_replay_speed(speed: float) -> void:
	replay_speed = speed
	for option in [1, 2, 4]:
		$Mid/ReplayBar.get_node("Speed%d" % option).button_pressed = \
			is_equal_approx(float(option), speed)


func _toggle_pause() -> void:
	paused = not paused
	$Mid/Actions/Pause.text = "Resume" if paused else "Pause"
	$Mid/ReplayBar/Play.text = "Play" if paused else "Pause"


func _end_battle(reason: String) -> void:
	_show_end(-1, reason)


## A finished battle is written to disk, so anything odd can be watched again
## or attached to a report (docs/11). Every ending saves: a victory, a defeat,
## and a disengagement are all worth being able to replay.
func _save_recording() -> void:
	if replay_log != null or battle == null or battle.log == null:
		return
	if battle.log.end_tick < 0:
		battle.log.close(battle)
	var path: String = ReplayStore.save(battle.log, int(Time.get_unix_time_from_system()))
	if not path.is_empty():
		_note("Battle recorded to %s" % [path.get_file()])


func _show_end(winner: int, reason: String = "") -> void:
	_save_recording()
	var overlay: CenterContainer = $Mid/ViewPanel/Stack/EndOverlay
	overlay.visible = true
	var result: Label = overlay.get_node("P/V/Result")
	var detail: Label = overlay.get_node("P/V/Detail")
	if not reason.is_empty():
		result.text = reason.to_upper()
		result.add_theme_color_override("font_color", Palette.AMBER)
		detail.text = "The engagement is broken off."
	elif winner == 0:
		result.text = "VICTORY"
		result.add_theme_color_override("font_color", Palette.OK)
		detail.text = "%s is destroyed." % String(battle.enemy().fit.hull()["name"])
	else:
		result.text = "SHIP LOST"
		result.add_theme_color_override("font_color", Palette.CRIT)
		detail.text = "%s is destroyed." % String(battle.player().fit.hull()["name"])
	paused = true


# ---- hud ---------------------------------------------------------------------

## Which families have a weapon charged and bearing right now. The fire
## buttons are lit from this, so a lit button always means a shot will happen
## and a dark one always means it will not.
func _ready_families() -> Dictionary:
	var out: Dictionary = { "beam": false, "heavy": false }
	if battle == null:
		return out
	var me: ShipState = battle.player()
	var foe: ShipState = battle.target_for(me)
	for i in range(me.weapons_rt.size()):
		var w: Dictionary = me.weapons_rt[i]["weapon"]
		if w.is_empty():
			continue
		if not bool(me.fire_check(i, foe.pos)["ok"]):
			continue
		var family: String = String(w["family"])
		if family in ["beam", "disruptor", "special"]:
			out["beam"] = true
		else:
			out["heavy"] = true
	return out


func _sync_fire_buttons() -> void:
	var ready: Dictionary = _ready_families()
	var can: bool = _can_command()
	for pair in [["FireBeams", "beam"], ["FireHeavy", "heavy"]]:
		var button: Button = $Mid/Actions.get_node(String(pair[0]))
		var lit: bool = can and bool(ready[String(pair[1])])
		button.disabled = not lit
		button.add_theme_color_override("font_color",
			Palette.OK if lit else Palette.DIM)


func _refresh_hud() -> void:
	_sync_fire_buttons()
	if battle == null:
		return
	var me: ShipState = battle.player()
	var foe: ShipState = battle.enemy()

	$Left/ShipPanel/V/Head.text = String(me.fit.hull()["name"]).to_upper()
	$Left/ShipPanel/V/Body.text = "\n".join([
		"BOXES  %d / %d" % [me.total_boxes(), me.total_boxes_max()],
		"SPEED  %.1f / %.1f" % [me.speed, me.max_speed()],
		"HEADING  %03d  ordered %03d" % [int(me.heading), int(me.ordered_heading)],
	])

	var out: float = me.power_output()
	$Left/PowerPanel/V/Head.text = "POWER  %d / %d" % [int(out),
		int(me.fit.hull()["budgets"]["power"])]
	for sink in ["Weapons", "Shields", "Engines", "Systems", "Reserve"]:
		var row: HBoxContainer = $Left/PowerPanel/V.get_node(sink)
		var slider: HSlider = row.get_node("Slider")
		var units: float = me.alloc_units(sink.to_lower())
		slider.max_value = maxf(out, 0.001)
		slider.set_value_no_signal(units)
		row.get_node("Out").text = str(int(roundf(units)))

	var dmg: Array[String] = []
	for sys in me.systems:
		if int(sys["boxes"]) < int(sys["boxes_max"]):
			dmg.append("%s  %d/%d" % [String(sys["code"]), int(sys["boxes"]),
				int(sys["boxes_max"])])
	$Left/DamagePanel/V/Body.text = "No damage." if dmg.is_empty() else "\n".join(dmg)
	$Left/DamagePanel/V/CommLog.text = "\n".join(_report_lines.slice(-6))

	var dist: float = me.pos.distance_to(foe.pos)
	var bearing: float = Sectors.bearing_between(me.pos, foe.pos)
	$Right/TargetPanel/V/Body.text = "\n".join([
		"CONTACT  %s" % String(foe.fit.hull()["name"]),
		"BOXES  %d / %d" % [foe.total_boxes(), foe.total_boxes_max()],
		"RANGE  %.1f" % dist,
		"BEARING  %03d" % int(bearing),
	])
	for f in range(6):
		$Right/TheirShields/V.get_node("S%d" % f).paint(f, foe.shields[f], foe.shield_max)

	for i in range(_weapon_rows.size()):
		var w: Dictionary = me.weapons_rt[i]
		if w["weapon"].is_empty():
			_weapon_rows[i].paint("%s (empty)" % String(w["mount"]["id"]), "empty", 0.0)
			continue
		var check: Dictionary = me.fire_check(i, foe.pos)
		_weapon_rows[i].paint("%s %s" % [String(w["mount"]["id"]),
			String(w["weapon"]["name"])], String(check["reason"]), float(w["charge"]))
	$Right/WeaponsPanel/V/Battery.text = "BATTERY %d%%" % int(me.battery * 100.0)
	$Right/WeaponsPanel/V/Battery.add_theme_color_override("font_color",
		Palette.OK if me.battery >= 1.0 else Palette.DIM)


func _position_ship_labels() -> void:
	if battle == null:
		return
	var world: Node3D = _world()
	var stack: Control = $Mid/ViewPanel/Stack
	var me: ShipState = battle.player()
	var foe: ShipState = battle.enemy()
	# Screen space offsets: world space label lifts collapse at plan pitch.
	var p: Vector2 = world.screen_pos(me.pos)
	stack.get_node("PlayerLabel").position = p + Vector2(-30, -46)
	stack.get_node("PlayerLabel").text = String(me.fit.hull()["name"]).to_upper()
	stack.get_node("PlayerLabel").add_theme_color_override("font_color", Palette.CYAN)
	var q: Vector2 = world.screen_pos(foe.pos)
	stack.get_node("EnemyLabel").position = q + Vector2(-34, -58)
	stack.get_node("EnemyLabel").text = String(foe.fit.hull()["name"]).to_upper()
	stack.get_node("EnemyLabel").add_theme_color_override("font_color", Palette.MAGENTA)
	var status: Label = stack.get_node("EnemyStatus")
	var downs: Array[String] = []
	for f in range(6):
		if foe.shields[f] <= 0.0:
			downs.append("#%d" % (f + 1))
	status.position = q + Vector2(-40, -42)
	status.text = "" if downs.is_empty() else "SHIELD %s DOWN" % " ".join(downs)
	status.add_theme_color_override("font_color", Palette.AMBER)


func _note(line: String) -> void:
	_report_lines.append(line)
	if _report_lines.size() > 40:
		_report_lines = _report_lines.slice(-40)
