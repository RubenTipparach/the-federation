extends HBoxContainer

## The tactical combat screen. Owns no rules: it steps a Battle, forwards
## orders, and paints what the sim says. The 3D world and the plan inset
## render the same World3D, so there is one battle display, seen twice.

signal battle_ended
## The gear at the foot of the fight strip. The screen does not open the
## settings panel itself: main owns that layer, and a screen that reached up
## to a sibling would be the coupling CLAUDE.md 4.2 exists to prevent.
signal settings_requested

const WEAPON_ROW := preload("res://scenes/ui/weapon_row.tscn")

## Throttle is a fraction in the sim, so the notch count is the whole of the
## discretisation and lives here rather than in the sim.
const THROTTLE_NOTCHES := 8
## Where the helm starts a battle: most of the way up, leaving room to push.
const OPENING_THROTTLE_NOTCH := 6
const TargetBracket := preload("res://src/ui/target_bracket.gd")
## Markers authored in the scene, one per ship in a duel.
const BRACKET_COUNT := 2
## Hull radius in sim units per ton, so a bracket is sized by the ship it is
## drawn around rather than by a single number for every hull. It lives in
## data/tuning.json with the other sizes it has to move with (CLAUDE.md 5.4).
const BRACKET_MIN_PX := 19.0
const BRACKET_MAX_PX := 144.0
## Extra pixels around a ship that still count as pointing at it.
const BRACKET_PICK_SLACK := 12.0
## Off screen by more than any real pointer position, so "no pointer" needs no
## second boolean that could disagree with the position beside it.
const NO_POINTER := Vector2(-1e9, -1e9)
## How far the pointer may travel before a right button press stops being a
## click and becomes a camera orbit. Small enough that a deliberate drag is
## never read as a lock, large enough that a hand tremor is not a drag.
const DRAG_SLOP := 6.0
## Each sink gets its own hue so the five strips are told apart at a glance
## rather than by counting rows. The subsystem family colours only supply four,
## which left shields and reserve identical, so these are named directly.
static func _sink_tint(sink: String) -> Color:
	match sink:
		"Weapons": return Palette.MAGENTA
		"Shields": return Palette.CYAN
		"Engines": return Palette.BLUE
		"Systems": return Palette.AMBER
		_: return Palette.SLATE

var session: Session
var battle: Battle
var paused: bool = false
var _weapon_rows: Array = []
## Set while the right button is held. Right drag orbits the camera; right
## click, meaning a press and release that never travelled, locks a target.
## Left is the helm and nothing else, so an order can never be mistaken for a
## camera move.
var _orbiting: bool = false
## Seconds until the panels are repainted again. Always zero at full rate, so
## the throttle costs nothing when it is not being used.
var _hud_due: float = 0.0
## The last range and bearing the sensors actually measured, and when. Held so
## a lost lock can show a stale reading with its age instead of a blank panel.
var _last_seen_range: float = 0.0
var _last_seen_bearing: float = 0.0
var _last_seen_at: float = 0.0
## Live touch points, for pinch. Two fingers zoom; the camera stick orbits.
var _touches: Dictionary = {}
var _pinch_span: float = -1.0
var _drag_moved: float = 0.0
## Where the pointer is inside the battle view, in that view's own coordinates,
## or NO_POINTER when it is not over the view at all.
##
## Cached from the events Godot already delivers rather than asked for. Asking
## costs a DisplayServer round trip to the operating system: measured at 190
## microseconds for get_global_mouse_position and 151 for the local one, and
## hover picking called both once a frame, which was the whole cost of the
## per frame path and nine times the cost of stepping the simulation.
##
## A touch device never sets this, which is correct rather than a limitation:
## there is no hover on a phone, so hover picking there costs nothing at all.
var _pointer_at: Vector2 = NO_POINTER
var _report_lines: Array[String] = []
## What changed since the last tick. Panels that did not change are not
## repainted at all, which is what the UI repaint rate was faking by being
## wrong more slowly (HudFeed).
var _feed: HudFeed = HudFeed.new()
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
	var cam: Dictionary = Catalog.tuning()["camera"]

	$Mid/Actions/FireBeams.pressed.connect(_fire_beams)
	$Mid/Actions/FireHeavy.pressed.connect(_fire_heavy)
	$Mid/Actions/Reinforce.pressed.connect(_reinforce)
	$Mid/Actions/ComeAbout.pressed.connect(_come_about)
	$Mid/Actions/Pause.pressed.connect(_toggle_pause)
	$Mid/Actions/Disengage.pressed.connect(_end_battle.bind("Disengaged"))
	$Mid/ViewPanel/Stack/EndOverlay/P/V/Return.pressed.connect(
		func() -> void: battle_ended.emit())

	var throttle: Control = $Left/ShipPanel/V/Throttle/Boxes
	# Both of these are controls, not readouts, so their empty boxes are drawn
	# bright enough to click at.
	throttle.setup(Palette.CYAN, true)
	throttle.level_picked.connect(_on_throttle_picked)
	for sink in ["Weapons", "Shields", "Engines", "Systems", "Reserve"]:
		var strip: Control = $Left/PowerPanel/V.get_node(sink + "/Boxes")
		strip.setup(_sink_tint(sink), true)
		strip.level_picked.connect(_on_power_picked.bind(sink.to_lower()))

	# Two strips of the same component, split by CLAUDE.md 6.2's own test:
	# what a player reaches for under fire sits on the right beside the target,
	# and the ship's business sits on the left beside the log, where the comm
	# log had room to spare. Three columns on the right, two on the left, so
	# neither needs a second row of tabs.
	# The gear rides the fight strip, which is the only chrome the tactical view
	# keeps, and is therefore the only place a menu can be reached under fire.
	$Right/FightStation/FightTabs.setup("fight", true)
	$Left/KeepStation/KeepTabs.setup("keep")
	$Right/FightStation/FightTabs.tab_selected.connect(_on_station_selected.bind($Right/FightStation/FightPanel))
	$Left/KeepStation/KeepTabs.tab_selected.connect(_on_station_selected.bind($Left/KeepStation/KeepPanel))
	$Right/FightStation/FightTabs.repair_requested.connect(_on_repair_requested)
	$Left/KeepStation/KeepTabs.repair_requested.connect(_on_repair_requested)
	$Right/FightStation/FightTabs.settings_requested.connect(
		func() -> void: settings_requested.emit())
	for panel in [$Right/FightStation/FightPanel, $Left/KeepStation/KeepPanel]:
		panel.repair_requested.connect(_on_repair_requested)
		panel.repair_dropped.connect(_on_repair_dropped)
		panel.regen_facing_picked.connect(_on_regen_facing_picked)
		panel.tractor_latch_requested.connect(_on_tractor_latch)
		panel.tractor_release_requested.connect(_on_tractor_release)
		panel.tractor_mode_picked.connect(_on_tractor_mode)
		panel.tractor_bid_picked.connect(_on_power_picked.bind(Tractor.SINK))

	# The own ship display is where a repair is ordered. The target's is the
	# same component with detail and editing off, which is what stops an
	# enemy's internals being readable box by box before sensors exist.
	$Right/OwnPanel/V/Display.system_picked.connect(_on_repair_requested)
	$Right/OwnPanel/V/Display.system_detail.connect(_on_system_detail)

	var container: SubViewportContainer = $Mid/ViewPanel/Stack/ViewContainer
	container.gui_input.connect(_on_view_input)
	container.mouse_exited.connect(func() -> void: _pointer_at = NO_POINTER)

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
	_feed.force()
	replay_log = log
	battle = log.replay_setup()
	_world().bind_battle(battle)
	paused = false
	replay_speed = 1.0
	_report_lines = []
	$Mid/Actions/Pause.text = "Pause"
	$Mid/ViewPanel/Stack/EndOverlay.visible = false
	_build_weapon_rows()
	_bind_displays()
	_refresh_hud()
	_sync_replay_bar()


func start_battle() -> void:
	_feed.force()
	replay_log = null
	$Mid/ReplayBar.visible = false
	battle = Battle.create_duel(session.fit.duplicate_fit(), session.enemy_hull_id,
		int(Time.get_ticks_usec()) % 1000000007, session.map_id)
	# Every battle is recorded. A log is small, it is written from the one
	# command path, and it is the difference between "it did something odd"
	# and a bug someone else can reproduce (docs/11).
	battle.log = BattleLog.create(battle.player().fit, session.enemy_hull_id,
		battle.seed_value, float(Catalog.tuning()["combat"]["replay_step"]),
		session.map_id)
	# Open at the throttle notch the strip will show, so the opening order and
	# the panel agree without the panel having to be read first.
	battle.apply_command(0, "order", [battle.player().heading,
		float(OPENING_THROTTLE_NOTCH) / float(THROTTLE_NOTCHES)])
	_world().bind_battle(battle)
	paused = false
	_report_lines = []
	$Mid/Actions/Pause.text = "Pause"
	$Mid/ViewPanel/Stack/EndOverlay.visible = false
	_build_weapon_rows()
	_bind_displays()
	_refresh_hud()


## Point the two ship displays at their ships. Own ship gets box by box detail
## and takes clicks; the target gets neither, because reading an enemy's
## internals is what a sensor lock will buy (CLAUDE.md 6.1: one component,
## configured, never a second one).
func _bind_displays() -> void:
	if battle == null:
		return
	var me: ShipState = battle.player()
	$Right/OwnPanel/V/Display.bind_ship(me, true, true)
	$Right/TargetDisplayPanel/V/Display.bind_ship(battle.target_for(me), false, false)
	# A tractor beam is a relationship between two ships, so the panel that draws
	# it needs the battle. Everything else it draws comes from the one ship.
	$Right/FightStation/FightPanel.battle = battle
	$Left/KeepStation/KeepPanel.battle = battle
	$Right/FightStation/FightPanel.show_station($Right/FightStation/FightTabs.selected(), me)
	$Left/KeepStation/KeepPanel.show_station($Left/KeepStation/KeepTabs.selected(), me)


func _build_weapon_rows() -> void:
	var list: VBoxContainer = $Right/WeaponsPanel/V/WeaponList
	for child in list.get_children():
		child.queue_free()
	_weapon_rows = []
	for i in range(battle.player().weapons_rt.size()):
		var row: HBoxContainer = WEAPON_ROW.instantiate()
		list.add_child(row)
		row.overload_toggled.connect(_on_overload_toggled.bind(i))
		_weapon_rows.append(row)


## Arming a mount is an order like any other: it goes through the battle, so it
## is written into the log and a replay fires the same heavy shot (docs/11).
## The switch is then set from what the ship believes rather than from what was
## clicked, because a refused order must not leave the panel showing it as
## taken, and a refusal moves nothing the HUD's dirty check would notice.
func _on_overload_toggled(on: bool, index: int) -> void:
	if battle == null:
		return
	if _can_command():
		battle.apply_command(0, "overload", [index, on])
	_weapon_rows[index].set_armed(battle.player().overloaded(index))


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


## Escape pauses, and it is the only key this screen claims. It is handled as
## unhandled input so a control that genuinely wants the key can take it first,
## and it is ignored while the screen is hidden so it cannot pause a battle the
## player is not looking at (CLAUDE.md 6.2).
func _unhandled_input(event: InputEvent) -> void:
	if not visible or battle == null:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		_toggle_pause()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if battle == null or not visible:
		return
	_apply_sticks(delta)
	var events: Array[Dictionary] = []
	if replay_log != null:
		events = _step_replay(delta)
	elif not paused and not battle.over:
		events = battle.step(delta)
	# The rig update is gated as well as timed. It was timed only, which made
	# its switch a no op and its measurement noise: the sweep turns a part off
	# and times the frame, so a flag that removes nothing measures nothing.
	# follow_pivot stays outside the gate because it is the camera, and a
	# battle you cannot see is not a measurement of anything.
	if DebugFlags.on("world"):
		var t_world: int = HudProfile.open("world")
		_world().update_visuals(delta, events)
		HudProfile.close("world", t_world)
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
	_apply_debug()
	# The HUD repaint is throttled separately from the simulation, which keeps
	# stepping at full rate: that is what makes the switch measure interface
	# cost rather than changing the game (DebugFlags).
	var hz: float = DebugFlags.number("hud_hz", 60.0)
	_hud_due -= delta
	if _hud_due <= 0.0:
		_hud_due = 1.0 / maxf(1.0, hz)
		_refresh_hud()
		_refresh_target_label()
	_position_ship_labels()



## Clicking to one side of the ship turns it that way. The ship is the anchor,
## so the gesture is "come left" or "come right" rather than "fly to this
## point", which is what a helm order actually is.
## Steer toward the point clicked, not merely to one side of the ship.
##
## The click is projected onto the battle plane, and the ship is ordered onto
## the bearing from its own position to that point. The previous version only
## read which side of the ship the click landed on and nudged the heading by a
## fixed step, so pointing at somewhere specific did not take the ship there.
func _helm_click(at: Vector2) -> void:
	var me: ShipState = battle.player()
	var point: Vector2 = _world().plane_point(at)
	if is_nan(point.x) or is_nan(point.y):
		return
	var to_point: Vector2 = point - me.pos
	# A click on the ship itself has no direction in it; hold the current order.
	if to_point.length() < 0.001:
		return
	var heading: float = Sectors.bearing_between(me.pos, point)
	if battle.apply_command(0, "order", [heading, me.ordered_throttle]):
		_note("Helm: come to %03d" % int(Sectors.wrap_deg(heading)))


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
	# Every mouse event that reaches the view carries where it happened, in the
	# view's own coordinates, which is exactly what picking wants. Recorded
	# first so every branch below has already updated it.
	if event is InputEventMouse:
		_pointer_at = event.position
	var world: Node3D = _world()
	# Godot emits a press AND a release for every wheel notch, so without the
	# pressed guard each notch would zoom twice.
	if event is InputEventMouseButton and event.pressed and (
			event.button_index == MOUSE_BUTTON_WHEEL_UP
			or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var dir: float = -1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0
		world.zoom(dir * float(Catalog.tuning()["camera"]["zoom_step"]))
		return
	# Pinch. InputEventMagnifyGesture is not delivered by the web export, which
	# is a shipping target, so the two finger distance is tracked by hand and
	# the gesture event is treated as a bonus when a platform does send it.
	if event is InputEventMagnifyGesture:
		world.zoom((1.0 - event.factor) * float(
			Catalog.tuning()["camera"]["zoom_pinch_scale"]))
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_span = -1.0
		return
	if event is InputEventScreenDrag:
		_touches[event.index] = event.position
		if _touches.size() == 2:
			var keys: Array = _touches.keys()
			var span: float = (_touches[keys[0]] as Vector2).distance_to(
				_touches[keys[1]])
			if _pinch_span > 0.0:
				world.zoom((_pinch_span - span) * float(
					Catalog.tuning()["camera"]["zoom_touch_scale"]))
			_pinch_span = span
			return
	# The right button does both camera and targeting, told apart by whether the
	# pointer moved: hold and drag to look around, click to lock the contact
	# under the cursor. The lock routes through the same target command the
	# cycle buttons use, so there is one notion of what is targeted rather than
	# a second one owned by the mouse.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			_orbiting = true
			_drag_moved = 0.0
		else:
			if _orbiting and _drag_moved < DRAG_SLOP:
				_lock_under_mouse()
			_orbiting = false
		return
	if event is InputEventMouseMotion and _orbiting:
		_drag_moved += event.relative.length()
		if _drag_moved >= DRAG_SLOP:
			var cam: Dictionary = Catalog.tuning()["camera"]
			var speed: float = float(cam["orbit_speed"])
			world.orbit(-event.relative.x * speed, event.relative.y * speed)
		return
	# Left is the helm. It fires on press rather than release because the order
	# is a single point and there is nothing to wait for; the camera no longer
	# shares this button, so there is no drag to disambiguate from.
	if event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT:
		# A pinch emits an emulated left click from the first finger, which
		# would otherwise fling the helm at wherever that finger happened to
		# land while the player was only zooming.
		if _touches.size() >= 2:
			return
		if _can_command():
			_helm_click(event.position)


## Lock whatever contact the cursor is over, if it is a contact and not us.
func _lock_under_mouse() -> void:
	if not _can_command():
		return
	var picked: int = _ship_under_mouse()
	if picked < 0 or battle.ships[picked] == battle.player():
		return
	if battle.apply_command(0, "target", [picked]):
		_note("Locked on %s" % String(
			battle.ships[picked].fit.hull()["name"]).to_upper())


## A station was opened. The panel is told which ship it is drawing here rather
## than holding one, so the same panel serves a live battle and a replay.
func _on_station_selected(id: String, panel: Node) -> void:
	_feed.force()
	if battle != null:
		panel.show_station(id, battle.player())


## Order a repair. Routed through apply_command like every other order, so a
## recording sees it and a replay puts the ship back together the same way.
func _on_repair_requested(index: int) -> void:
	if battle == null or not _can_command():
		return
	if battle.apply_command(0, "repair_queue", [index]):
		var sys: Dictionary = battle.player().systems[index]
		_note("Repair: %s queued, %d parts" % [String(sys["code"]),
			RepairModel.job_cost(sys, Catalog.tuning())])


func _on_repair_dropped(index: int) -> void:
	if battle == null or not _can_command():
		return
	if battle.apply_command(0, "repair_drop", [index]):
		_note("Repair: %s cancelled" % String(battle.player().systems[index]["code"]))


## Which shield the regeneration energy is buying for (Federation Commander
## 3C7). Clicking the facing already picked releases it back to the weakest.
func _on_regen_facing_picked(facing: int) -> void:
	if battle == null or not _can_command():
		return
	var want: int = -1 if battle.player().shield_bias == facing else facing
	if battle.apply_command(0, "shield_bias", [want]):
		_note("Shields: hold %s" % Sectors.facing_mark(facing) if want >= 0 else "Shields: even")


## Right click on a subsystem: what losing it costs. It goes to the comm log
## rather than to a popover, because the log is already the place this screen
## says things and a second one would be a second implementation.
func _on_system_detail(index: int) -> void:
	if battle == null:
		return
	var sys: Dictionary = battle.player().systems[index]
	var tuning: Dictionary = Catalog.tuning()
	var where: String = "core" if int(sys["sector"]) < 0 \
		else Sectors.facing_mark(int(sys["sector"]))
	if RepairModel.repairable(sys, tuning):
		_note("%s %s: %d/%d, %d parts to fix" % [String(sys["code"]), where,
			int(sys["boxes"]), int(sys["boxes_max"]),
			RepairModel.job_cost(sys, tuning)])
	else:
		_note("%s %s: %d/%d, undamaged" % [String(sys["code"]), where,
			int(sys["boxes"]), int(sys["boxes_max"])])


## A box strip reports the level it was clicked to, which is already the whole
## number of reactor points the sim wants. No rounding happens at the view.
func _on_power_picked(level: int, sink: String) -> void:
	if battle != null:
		battle.apply_command(0, "power", [sink, float(level)])


## The three tractor orders. Like every other order on this screen they go
## through Battle.apply_command, so a recording sees them and a replay repeats
## them (docs/11).
func _on_tractor_latch() -> void:
	if battle == null:
		return
	var target: ShipState = battle.target_for(battle.player())
	var index: int = battle.ships.find(target)
	if index >= 0:
		battle.apply_command(0, "tractor_latch", [index])


func _on_tractor_release() -> void:
	if battle != null:
		battle.apply_command(0, "tractor_release", [])


func _on_tractor_mode(mode: String) -> void:
	if battle != null:
		battle.apply_command(0, "tractor_mode", [mode])


## Throttle is stored as a 0 to 1 fraction, so the notch count is the only
## place the discretisation lives.
func _on_throttle_picked(level: int) -> void:
	if battle == null:
		return
	var frac: float = float(level) / float(THROTTLE_NOTCHES)
	battle.apply_command(0, "order", [battle.player().ordered_heading, frac])


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
		_note("Reinforced shield %s from the battery" % Sectors.facing_mark(facing))
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
	set_paused(not paused)


## Pause or resume, and say whether it actually changed anything. The return is
## what lets the settings panel put the battle back exactly as it found it: it
## pauses on open and resumes on close, but only if it was the one that paused.
## A battle the player had already paused stays paused when the panel shuts.
func set_paused(on: bool) -> bool:
	if paused == on:
		return false
	paused = on
	$Mid/Actions/Pause.text = "Resume" if paused else "Pause"
	$Mid/ReplayBar/Play.text = "Play" if paused else "Pause"
	return true


## Whether a battle is running here. The settings panel asks, because what it
## offers differs: you cannot refit a ship under fire, and leaving is only a
## thing you can do when there is something to leave.
func in_battle() -> bool:
	return battle != null and not battle.over


## Leave the battle now. The same ending Disengage gives, through the same
## call, because two ways out that both claim to be a disengagement is exactly
## the divergence CLAUDE.md 4.1 is about.
func leave_battle() -> void:
	set_paused(false)
	_end_battle("Disengaged")


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
		Paint.tint(result, "font_color", Palette.AMBER)
		detail.text = "The engagement is broken off."
	elif winner == 0:
		result.text = "VICTORY"
		Paint.tint(result, "font_color", Palette.OK)
		detail.text = "%s is destroyed." % String(battle.enemy().fit.hull()["name"])
	else:
		result.text = "SHIP LOST"
		Paint.tint(result, "font_color", Palette.CRIT)
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
		Paint.tint(button, "font_color",
			Palette.OK if lit else Palette.DIM)


## Repaint the panels. One block per part, each gated by its own switch and
## timed by the one profiler, so the overlay can say what each is worth without
## anybody having to toggle eleven things twice on a phone.
##
## The gate is deliberately on the WORK and not only on the visibility: a panel
## nobody can see still pays for every string formatted into it, and a switch
## that removed the drawing but left the updating would measure half a thing.
func _refresh_hud() -> void:
	if not DebugFlags.on("hud") or battle == null:
		return
	var me: ShipState = battle.player()
	var foe: ShipState = battle.enemy()
	# One pass over the ship, before any panel asks anything. Every panel below
	# reads its answer from this rather than working out for itself whether it
	# has anything to do, because thirty of those tests is thirty chances for
	# one to be wrong (CLAUDE.md 4.1).
	# The range and bearing are taken LIVE here, not from the cached last seen
	# pair. Those are written by the target panel, so signing on them would mean
	# the panel only repaints when it has already repainted: a readout that
	# freezes the instant it stops being refreshed, which is a deadlock wearing
	# a plausible face.
	var seen: bool = me.can_see(foe.pos)
	var rng: float = me.pos.distance_to(foe.pos) if seen else _last_seen_range
	var brg: float = Sectors.bearing_between(me.pos, foe.pos) if seen \
		else _last_seen_bearing
	var lost_tenths: int = 0 if seen else int((battle.time - _last_seen_at) * 10.0)
	_feed.sample(me, foe, seen, rng, brg, lost_tenths, _report_lines.size())
	var t: int = 0

	if DebugFlags.on("ship") and _feed.moved([HudFeed.HELM]):
		t = HudProfile.open("ship")
		_sync_fire_buttons()
		$Left/ShipPanel/V/Head.text = String(me.fit.hull()["name"]).to_upper()
		$Left/ShipPanel/V/Throttle/Boxes.paint(
			int(roundf(me.ordered_throttle * float(THROTTLE_NOTCHES))), THROTTLE_NOTCHES)
		$Left/ShipPanel/V/Throttle/Out.text = "%d" % int(
			roundf(me.ordered_throttle * float(THROTTLE_NOTCHES)))
		$Left/ShipPanel/V/Body.text = "\n".join([
			"BOXES  %d / %d" % [me.total_boxes(), me.total_boxes_max()],
			"SPEED  %.1f / %.1f" % [me.speed, me.max_speed()],
			"HEADING  %03d  ordered %03d" % [int(me.heading), int(me.ordered_heading)],
		])
		HudProfile.close("ship", t)

	if DebugFlags.on("power") and _feed.moved([HudFeed.POWER]):
		t = HudProfile.open("power")
		var out: float = me.power_output()
		$Left/PowerPanel/V/Head.text = "POWER  %d / %d" % [int(out),
			int(me.fit.hull()["budgets"]["power"])]
		# The strip is as long as the reactor's SURVIVING output, so losing power
		# boxes visibly shortens every row instead of silently rescaling them.
		var budget: int = int(me.fit.hull()["budgets"]["power"])
		var ceiling: int = int(floorf(out))
		for sink in ["Weapons", "Shields", "Engines", "Systems", "Reserve"]:
			var row: HBoxContainer = $Left/PowerPanel/V.get_node(sink)
			var units: float = me.alloc_units(sink.to_lower())
			row.get_node("Boxes").paint(int(roundf(units)), budget, ceiling)
			row.get_node("Out").text = str(int(roundf(units)))
		HudProfile.close("power", t)

	if DebugFlags.on("damage") and _feed.moved([HudFeed.SYSTEMS, HudFeed.LOG]):
		t = HudProfile.open("damage")
		var dmg: Array[String] = []
		for sys in me.systems:
			if int(sys["boxes"]) < int(sys["boxes_max"]):
				dmg.append("%s  %d/%d" % [String(sys["code"]), int(sys["boxes"]),
					int(sys["boxes_max"])])
		$Left/DamagePanel/V/BodyScroll/Body.text = \
			"No damage." if dmg.is_empty() else "\n".join(dmg)
		$Left/DamagePanel/V/CommScroll/CommLog.text = "\n".join(_report_lines.slice(-6))
		HudProfile.close("damage", t)

	if DebugFlags.on("target") and _feed.moved([HudFeed.TARGET]):
		t = HudProfile.open("target")
		_refresh_target_readout(me, foe)
		HudProfile.close("target", t)

	if DebugFlags.on("own_ssd") and _feed.moved([HudFeed.SHIELDS, HudFeed.SYSTEMS]):
		t = HudProfile.open("own_ssd")
		$Right/OwnPanel/V/Display.refresh()
		HudProfile.close("own_ssd", t)

	if DebugFlags.on("target_ssd") and _feed.moved([HudFeed.FOE]):
		t = HudProfile.open("target_ssd")
		$Right/TargetDisplayPanel/V/Display.refresh()
		HudProfile.close("target_ssd", t)

	# The station panels serve all ten stations and the open one is not known
	# from here, so they sign on everything any station could read. Wider than
	# necessary on purpose: repainting when nothing moved is waste, and NOT
	# repainting when something did is a stale readout in a fight.
	if DebugFlags.on("fight") and _feed.moved(
			[HudFeed.SYSTEMS, HudFeed.SHIELDS, HudFeed.QUEUE, HudFeed.POWER]):
		t = HudProfile.open("fight")
		$Right/FightStation/FightTabs.refresh(me.systems, me.repair_queue)
		$Right/FightStation/FightPanel.refresh()
		HudProfile.close("fight", t)

	if DebugFlags.on("keep") and _feed.moved(
			[HudFeed.SYSTEMS, HudFeed.QUEUE, HudFeed.POWER]):
		t = HudProfile.open("keep")
		$Left/KeepStation/KeepTabs.refresh(me.systems, me.repair_queue)
		$Left/KeepStation/KeepPanel.refresh()
		HudProfile.close("keep", t)

	# SHIELDS as well as WEAPONS, because this panel prints the battery and the
	# battery lives in the shields facet. Caught by tests/hud_test.gd at one
	# failure in eight hundred: the readout sat a single percent behind, which
	# no screenshot would ever have shown and which is exactly how a dirty
	# check optimisation goes wrong.
	if DebugFlags.on("weapons") and _feed.moved([HudFeed.WEAPONS, HudFeed.SHIELDS]):
		t = HudProfile.open("weapons")
		for i in range(_weapon_rows.size()):
			var w: Dictionary = me.weapons_rt[i]
			if w["weapon"].is_empty():
				# The mount id alone. The chip beside it already says EMPTY, and
				# a row that says it twice is spending the column on nothing.
				_weapon_rows[i].paint(String(w["mount"]["id"]), "empty", 0.0)
				continue
			var check: Dictionary = me.fire_check(i, foe.pos)
			# The four letter code rather than the full name. The column is 118
			# pixels and the face advances 12 to a character, so the name was
			# being cut to "M2 Disruptor Ba" long before the arming switch
			# arrived; the code is the same one the rest of the game prints and
			# it is never cut (CLAUDE.md 6.4).
			_weapon_rows[i].paint("%s %s" % [String(w["mount"]["id"]),
				String(w["weapon"]["short"])], String(check["reason"]),
				float(w["charge"]), me.can_overload(i), me.overloaded(i))
		$Right/WeaponsPanel/V/Battery.text = "BATTERY %d%%" % int(me.battery * 100.0)
		Paint.tint($Right/WeaponsPanel/V/Battery, "font_color",
			Palette.OK if me.battery >= 1.0 else Palette.DIM)
		HudProfile.close("weapons", t)

	HudProfile.tick()


## The contact readout, and what it says when the sensors cannot hold a lock.
##
## A nebula does not delete the enemy, it stops you measuring them, so the panel
## keeps the last reading rather than blanking. The numbers go dim and the age
## of the reading is printed, which is the difference between "he is at 18.4"
## and "he WAS at 18.4, three seconds ago". Hiding the readout instead would
## read as a bug, and blanking the numbers would throw away the only
## information a captain still has.
##
## Whether the lock holds is asked of the ship, which asks the terrain. The
## firing check asks the same question through the same call, so a contact that
## cannot be shot at is never shown as one that can (CLAUDE.md 4.1).
## The debug overlay's switches that belong to this screen rather than to the
## world: the second 3D render, and the whole interface.
func _apply_debug() -> void:
	_apply_hud_visible()
	# The plan inset is a SECOND render of the whole 3D world, and hiding its
	# frame does not stop it: a SubViewport keeps rendering to its target
	# whether or not anything is showing that target. So the overlays switch
	# has to reach the update mode as well, or it would hide the picture and
	# leave the cost, which is the opposite of what it is for.
	var inset: SubViewport = $Mid/ViewPanel/Stack/InsetFrame/InsetContainer/Inset
	var shown: bool = DebugFlags.on("hud") and DebugFlags.on("overlays")
	var want: int = SubViewport.UPDATE_WHEN_PARENT_VISIBLE if shown \
		else SubViewport.UPDATE_DISABLED
	if inset.render_target_update_mode != want:
		inset.render_target_update_mode = want


func _refresh_target_readout(me: ShipState, foe: ShipState) -> void:
	var seen: bool = me.can_see(foe.pos)
	if seen:
		_last_seen_range = me.pos.distance_to(foe.pos)
		_last_seen_bearing = Sectors.bearing_between(me.pos, foe.pos)
		_last_seen_at = battle.time
	# Range and bearing share a line: a five mount hull needs five weapon rows
	# below, and at the bitmap face's fixed size the column has no spare row.
	var body: Label = $Right/TargetPanel/V/Body
	body.text = "\n".join([
		String(foe.fit.hull()["name"]).to_upper(),
		"BOXES  %d / %d" % [foe.total_boxes(), foe.total_boxes_max()],
		"RANGE  %.1f   BRG  %03d" % [_last_seen_range, int(_last_seen_bearing)],
	])
	Paint.tint(body, "font_color", Palette.FG if seen else Palette.DIM)
	var lock: Label = $Right/TargetPanel/V/Lock
	lock.visible = not seen
	lock.text = "SENSOR LOCK LOST   %.1fs" % [battle.time - _last_seen_at]
	Paint.tint(lock, "font_color", Palette.CRIT)


func _position_ship_labels() -> void:
	if battle == null or not DebugFlags.on("hud") or not DebugFlags.on("overlays"):
		return
	var stamp: int = HudProfile.open("overlays")
	_position_ship_labels_body()
	HudProfile.close("overlays", stamp)


func _position_ship_labels_body() -> void:
	var world: Node3D = _world()
	var stack: Control = $Mid/ViewPanel/Stack
	var me: ShipState = battle.player()
	var foe: ShipState = battle.enemy()
	# Screen space offsets: world space label lifts collapse at plan pitch.
	var p: Vector2 = world.screen_pos(me.pos)
	stack.get_node("PlayerLabel").position = p + Vector2(-36, -55)
	stack.get_node("PlayerLabel").text = String(me.fit.hull()["name"]).to_upper()
	Paint.tint(stack.get_node("PlayerLabel"), "font_color", Palette.CYAN)
	# Which shields are down is a sensor reading like any other, so it goes with
	# the lock rather than surviving it.
	var seen: bool = me.can_see(foe.pos)
	var q: Vector2 = world.screen_pos(foe.pos)
	stack.get_node("EnemyLabel").position = q + Vector2(-41, -70)
	stack.get_node("EnemyLabel").text = String(foe.fit.hull()["name"]).to_upper()
	Paint.tint(stack.get_node("EnemyLabel"), "font_color", Palette.MAGENTA)
	var status: Label = stack.get_node("EnemyStatus")
	var downs: Array[String] = []
	for f in range(6):
		if foe.shields[f] <= 0.0:
			downs.append(Sectors.facing_mark(f))
	status.position = q + Vector2(-48, -50)
	status.text = "" if downs.is_empty() or not seen else "SHIELD %s DOWN" % " ".join(downs)
	Paint.tint(status, "font_color", Palette.AMBER)
	_refresh_brackets(world, stack)


## Draw a marker over each ship: faint corners under the cursor, a full
## bracket with name and hull bar on the one that is actually targeted.
##
## The bracket is sized from the ship's own projected extent rather than a
## fixed pixel box, so it hugs a frigate and opens out around a battlecruiser,
## and it keeps doing so as the camera zooms.
func _refresh_brackets(world: Node3D, stack: Control) -> void:
	var picked: int = _ship_under_mouse()
	var target: ShipState = battle.target_for(battle.player())
	for i in range(battle.ships.size()):
		if i >= BRACKET_COUNT:
			break
		var ship: ShipState = battle.ships[i]
		var bracket: Control = stack.get_node("Bracket%d" % i)
		# A contact the sensors cannot hold is not drawn. The bracket carries a
		# name and a hull bar, which are exactly the readings a broken lock has
		# taken away, so drawing it would claim knowledge the ship does not have.
		var seen: bool = i == 0 or battle.player().can_see(ship.pos)
		var state: int = TargetBracket.State.HIDDEN
		if seen and ship.alive and target != null and ship == target:
			state = TargetBracket.State.LOCKED
		elif seen and ship.alive and i == picked:
			state = TargetBracket.State.HOVER
		# A locked bracket carries the ship's name itself, so the floating label
		# for that ship stands down rather than printing the name twice on top
		# of itself. An unseen contact loses the label too: the readout is where
		# a stale position belongs, not floating over a hull nobody can find.
		var label: String = "PlayerLabel" if i == 0 else "EnemyLabel"
		stack.get_node(label).visible = seen and state != TargetBracket.State.LOCKED
		if state == TargetBracket.State.HIDDEN:
			bracket.visible = false
			continue
		var half: float = _ship_screen_radius(world, ship)
		var centre: Vector2 = world.screen_pos(ship.pos)
		bracket.size = Vector2(half * 2.0, half * 2.0)
		bracket.position = centre - Vector2(half, half)
		bracket.show_target(state, String(ship.fit.hull()["name"]).to_upper(),
			float(ship.total_boxes()) / maxf(1.0, float(ship.total_boxes_max())),
			Palette.CYAN if i == 0 else Palette.MAGENTA)


## Half the ship's on screen size, measured by projecting a point one hull
## radius to its side. Doing it from the projection rather than from a constant
## means the bracket tracks zoom and perspective without a second scale factor
## to keep in step with the camera.
##
## The radius is the simulation's (ShipState.radius), so the ring drawn around a
## contact is the circle the contact actually collides with.
func _ship_screen_radius(world: Node3D, ship: ShipState) -> float:
	var r: float = ship.radius()
	var centre: Vector2 = world.screen_pos(ship.pos)
	var edge: Vector2 = world.screen_pos(ship.pos + Vector2(r, 0.0))
	return clampf(centre.distance_to(edge), BRACKET_MIN_PX, BRACKET_MAX_PX)


## Which ship the cursor is over, or -1. Picking is done in screen space
## against the same projection the brackets are drawn from, so what lights up
## is exactly what is under the pointer.
func _ship_under_mouse() -> int:
	if _pointer_at == NO_POINTER:
		return -1
	var world: Node3D = _world()
	var mouse: Vector2 = _pointer_at
	var best: int = -1
	var best_d: float = INF
	for i in range(battle.ships.size()):
		var ship: ShipState = battle.ships[i]
		if not ship.alive:
			continue
		# A contact you cannot hold a lock on cannot be picked either. Otherwise
		# a player could right click a hull the guns will then refuse to fire on.
		if i != 0 and not battle.player().can_see(ship.pos):
			continue
		var d: float = mouse.distance_to(world.screen_pos(ship.pos))
		if d < _ship_screen_radius(world, ship) + BRACKET_PICK_SLACK and d < best_d:
			best_d = d
			best = i
	return best


func _note(line: String) -> void:
	_report_lines.append(line)
	if _report_lines.size() > 40:
		_report_lines = _report_lines.slice(-40)


## Show or hide each part of the interface, from the node paths in the flag
## data. One loop for every flag rather than a branch per panel, so adding a
## part is an entry in data/debug.json and nothing here (CLAUDE.md 5.4).
##
## The "hud" flag is the master: everything goes when it is off, whatever the
## individual switches say, so the coarse question can be asked without first
## putting ten fine ones back.
func _apply_hud_visible() -> void:
	var all_on: bool = DebugFlags.on("hud")
	for id in DebugFlags.ids():
		var paths: Array = DebugFlags.nodes(String(id))
		if paths.is_empty():
			continue
		var want: bool = all_on and DebugFlags.on(String(id))
		for path in paths:
			var node: CanvasItem = get_node_or_null(NodePath(String(path))) as CanvasItem
			if node != null and node.visible != want:
				node.visible = want
				# A panel coming back is showing whatever it held when it went
				# away, which may be a whole battle out of date.
				_feed.force()
