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


func bind_session(p_session: Session) -> void:
	session = p_session
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
			battle.player().set_order(battle.player().ordered_heading, v))
	for sink in ["Weapons", "Shields", "Engines", "Systems", "Reserve"]:
		var slider: HSlider = $Left/PowerPanel/V.get_node(sink + "/Slider")
		slider.value_changed.connect(_on_power_slider.bind(sink.to_lower()))

	var container: SubViewportContainer = $Mid/ViewPanel/Stack/ViewContainer
	container.gui_input.connect(_on_view_input)

	# The plan inset renders the same world as the main view: one scene, two
	# cameras, so the tactical picture cannot diverge from the pretty one.
	var inset: SubViewport = $Mid/ViewPanel/Stack/InsetFrame/InsetContainer/Inset
	inset.world_3d = ($Mid/ViewPanel/Stack/ViewContainer/View as SubViewport).world_3d
	var plan_cam: Camera3D = inset.get_node("PlanCamera")
	plan_cam.size = float(cam["plan_inset_size"])
	plan_cam.look_at_from_position(Vector3(0, 60, 0), Vector3.ZERO, Vector3(0, 0, 1))


func _world() -> Node3D:
	return $Mid/ViewPanel/Stack/ViewContainer/View/World


func start_battle() -> void:
	battle = Battle.create_duel(session.fit.duplicate_fit(), session.enemy_hull_id,
		int(Time.get_ticks_usec()) % 1000000007)
	battle.player().set_order(battle.player().heading,
		float($Left/ShipPanel/V/Throttle/Slider.value))
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


func _physics_process(delta: float) -> void:
	if battle == null or not visible:
		return
	var events: Array[Dictionary] = []
	if not paused and not battle.over:
		events = battle.step(delta)
	_world().update_visuals(delta, events)
	for e in events:
		if String(e["type"]) == "shot":
			for line in e["log"]:
				_note(String(line))
		elif String(e["type"]) == "end":
			_show_end(int(e["winner"]))
	_refresh_hud()
	_position_ship_labels()


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
			if _dragging and _drag_moved < 6.0:
				var p: Vector2 = world.plane_point(event.position)
				if is_finite(p.x):
					var me: ShipState = battle.player()
					me.set_order(Sectors.bearing_between(me.pos, p), me.ordered_throttle)
					_note("Helm: come to %03d" % int(Sectors.bearing_between(me.pos, p)))
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
		battle.player().set_alloc_units(sink, value)


func _fire_beams() -> void:
	var n: int = battle.fire_family(battle.player(), "beam")
	n += battle.fire_family(battle.player(), "disruptor")
	if n == 0:
		_note("No beam or disruptor bears")


func _fire_heavy() -> void:
	var n: int = battle.fire_family(battle.player(), "torpedo")
	n += battle.fire_family(battle.player(), "lance")
	n += battle.fire_family(battle.player(), "drone")
	if n == 0:
		_note("No heavy weapon bears")


func _reinforce() -> void:
	var me: ShipState = battle.player()
	var facing: int = me.weakest_facing()
	if me.reinforce(facing, Catalog.tuning()):
		_note("Reinforced shield #%d from the battery" % (facing + 1))
	else:
		_note("Battery not charged")


func _come_about() -> void:
	var me: ShipState = battle.player()
	me.set_order(me.ordered_heading + 180.0, me.ordered_throttle)
	_note("Helm: coming about")


func _toggle_pause() -> void:
	paused = not paused
	$Mid/Actions/Pause.text = "Resume" if paused else "Pause"


func _end_battle(reason: String) -> void:
	_show_end(-1, reason)


func _show_end(winner: int, reason: String = "") -> void:
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

func _refresh_hud() -> void:
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
