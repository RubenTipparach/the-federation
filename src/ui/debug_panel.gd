extends CanvasLayer

## An instrument for finding out what a frame costs, on the device it is slow on.
##
## This is not part of the game. It is a tool, and it sits on its own CanvasLayer
## above every screen rather than inside any of them. CLAUDE.md 6.2 says nothing
## but fighting belongs in the tactical view, and that stands: this is not
## something a player reaches for under fire, it is something a developer
## reaches for instead of playing.
##
## It is opened by a button in the corner, which is on screen at all times. That
## button was a gesture first, hidden so as not to put a control in the battle
## view, and that was the wrong trade: an instrument nobody can find on the
## machine it was built for is not an instrument. The gestures below still work
## and cost nothing, but the button is the way in.
##
## Everything it switches is view only (see DebugFlags), so a battle plays out
## identically whatever is off. That is what makes it safe to leave in a
## shipped build, and leaving it in is the point: the machine that is slow is a
## phone running the web export, and it cannot be attached to a profiler.
##
## Nothing is constructed here. The buttons are authored in debug_panel.tscn and
## configured from data/debug.json, exactly as the subsystem tab strip is.

## How many authored button slots there are. A flag list longer than this shows
## the first SLOTS and says so, rather than silently dropping the rest.
const SLOTS: int = 14
## The counters and the graph repaint far slower than they sample, because a
## readout that repaints every frame is measuring itself. Ten a second is fast
## enough to watch a toggle take effect and slow enough to cost nothing.
const SAMPLE_HZ: float = 10.0
## Fingers that must be down at once to summon it. Three, because the battle
## view already uses one for the helm and two for pinch zoom, so three is the
## first count that cannot be reached by playing.
const SUMMON_FINGERS: int = 3

var _since_sample: float = 0.0
## Frame times since the last readout, so the number shown is an average over
## the sample window rather than whichever frame happened to land on it.
var _frames: int = 0
var _elapsed: float = 0.0
## Touch indices currently down. Watched, never consumed: the overlay must not
## be able to swallow a helm order it happened to see first.
var _fingers: Dictionary = {}

## The sweep. It switches each part off in turn, waits for the frame time to
## settle, averages it, and puts it back, so what lands on each button is what
## the frame actually gained rather than what a stopwatch around our own calls
## managed to see. That distinction is the whole reason it exists: on the phone
## the parts reported 1.07 ms between them and removing them took 18.1 ms off
## the frame, because almost none of the work happens inside the call.
##
## It is exactly what a person would otherwise do by hand, which somebody did,
## eleven times, with screenshots. Doing it in the panel takes twenty seconds
## and does not depend on anybody being careful.
var _sweep: Array = []
var _sweep_at: int = -1
var _sweep_frames: int = 0
var _sweep_elapsed: float = 0.0
var _sweep_baseline: float = -1.0
## Frames thrown away after a switch moves, then frames averaged. The discard
## matters more than it looks: hiding a panel makes its container re-sort and
## every sibling re-fit, and the frame that lands in is not the steady state.
const SWEEP_SETTLE: int = 6
const SWEEP_SAMPLE: int = 30
## Passes over the whole list, averaged. One pass on the phone produced -13.6 ms
## for a panel, which is impossible: removing something cannot make the frame
## slower, so that number was the noise floor rather than a measurement. Three
## passes and a paused battle bring it down far enough for the small parts to be
## distinguishable from zero.
const SWEEP_PASSES: int = 3
var _sweep_pass: int = 0
var _sweep_sum: Dictionary = {}
## The battle is paused for the duration. A sweep takes half a minute, and in
## that time the ships close, the terrain slides past and the damage report
## fills up, so an unpaused sweep measures the battle changing as much as it
## measures the panels. It is restored to whatever it was when the sweep ends.
var _sweep_was_paused: bool = false
## Each part is measured against a baseline taken IMMEDIATELY before it, rather
## than against one baseline at the start. A sweep takes half a minute, the
## ships close and the terrain slides past in that time, and a single baseline
## turns that drift into a per part cost. Two passes per part is twice as long
## and the only version whose numbers survive being repeated.
var _sweep_phase: int = 0


## Ask the ENGINE what rendering cost, rather than inferring it from a frame
## time minus a script time. That inference was wrong, provably: it once
## reported 57.6 ms of script inside a 22.0 ms frame. Godot measures its own
## render time per viewport, split into the CPU that builds the command lists
## and the GPU that executes them, and it does not need us to guess.
##
## The 3D subviewport is measured separately from the window, so the readout
## can say which of the two renders is expensive.
func _enable_render_timing() -> void:
	var vp: Viewport = get_viewport()
	if vp != null:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	var view: SubViewport = get_node_or_null(
		"/root/Main/Root/Content/Combat/Mid/ViewPanel/Stack/ViewContainer/View")
	if view != null:
		RenderingServer.viewport_set_measure_render_time(view.get_viewport_rid(), true)


func _ready() -> void:
	# The layer stays visible and only the panel hides, so the overlay can be
	# turned on before a battle and still be there during one. That is the whole
	# route now that the corner button is gone: the gear that opens settings
	# lives on the top bar, and the top bar is hidden in a fight.
	$Panel.visible = false
	var ids: Array = DebugFlags.ids()
	for i in range(SLOTS):
		var b: Button = _slot(i)
		var wanted: bool = i < ids.size()
		b.visible = wanted
		if wanted:
			b.pressed.connect(_on_flag.bind(String(ids[i])))
	$Panel/V/Head/Measure.pressed.connect(_start_sweep)
	$Panel/V/Head/Close.pressed.connect(func() -> void: $Panel.visible = false)
	$Panel/V/Head/Reset.pressed.connect(func() -> void:
		DebugFlags.reset()
		_paint_buttons())
	if ids.size() > SLOTS:
		push_warning("debug panel has %d flags and %d slots" % [ids.size(), SLOTS])
	_paint_buttons()
	_enable_render_timing()


func _slot(i: int) -> Button:
	return $Panel/V/Flags.get_node("F%d" % i)


## Summon by gesture, which is the route that works during a battle.
##
## _input rather than _unhandled_input, because the battle view takes touches
## through gui_input on its viewport container and they never reach the unhandled
## pass. Nothing is accepted here: the events go on to whoever wanted them, and
## the overlay only counts.
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_fingers[event.index] = true
			if _fingers.size() >= SUMMON_FINGERS:
				_fingers.clear()
				_toggle()
		else:
			_fingers.erase(event.index)
	elif event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F3:
		_toggle()


func _toggle() -> void:
	set_shown(not $Panel.visible)


## Whether the overlay is up. The settings panel asks, so its box reads the
## overlay rather than a copy of the answer kept beside it.
func is_shown() -> bool:
	return $Panel.visible


func set_shown(on: bool) -> void:
	$Panel.visible = on
	if on:
		_paint_buttons()


func _process(delta: float) -> void:
	if not $Panel.visible:
		return
	if not _sweep.is_empty():
		_step_sweep(delta)
		return
	# Every frame goes into the graph; only the readout and the repaint are
	# throttled. A spike that lands between samples is exactly the thing worth
	# seeing, so it must not be the thing that gets dropped.
	$Panel/V/Graph.push(delta * 1000.0)
	_frames += 1
	_elapsed += delta
	_since_sample += delta
	if _since_sample < 1.0 / SAMPLE_HZ:
		return
	_paint_counters()
	_paint_buttons()
	HudProfile.flush()
	$Panel/V/Graph.queue_redraw()
	_since_sample = 0.0
	_frames = 0
	_elapsed = 0.0


## What a frame costs, and the one split that says who to blame.
##
## SCRIPT is time inside _process and _physics_process: our GDScript, which is
## the simulation and every panel repaint. REST is the frame minus that: the
## engine's own culling and command recording, submitting to the driver, and
## waiting for the GPU.
##
## That split is the whole point of this readout, because without it "the frame
## is 119 milliseconds" has at least four possible causes and no way to choose
## between them. Script large means our code. Rest large with few draw calls
## means fill rate or shaders. Rest large with many draw calls means driver
## overhead, which on a phone running WebGL is a real and separate thing.
##
## Draw calls and primitives stay because they tell the last two apart.
func _paint_counters() -> void:
	var ms: float = (_elapsed / maxf(1.0, float(_frames))) * 1000.0
	var draws: int = int(Performance.get_monitor(
		Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims: int = int(Performance.get_monitor(
		Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var mem: float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	# There was a script and rest split here. It is gone, because it was wrong:
	# on the phone it reported 57.6 ms of script inside a 22.0 ms frame, which
	# cannot happen, so every reading it ever gave was suspect. The sweep
	# measures the same question by removing things and timing the result, which
	# cannot report an impossible number because it only ever compares two
	# frame times.
	# The parts total against the script total, because the difference is the
	# most useful number on the panel and nobody should have to add up eleven
	# buttons to find it. Script minus parts is everything the interface does
	# NOT account for: the simulation, the 3D rig update, and the engine's own
	# container sorting and minimum size work, which is charged to the process
	# step and is invisible to any stopwatch we put around our own calls.
	var vp: Viewport = get_viewport()
	var rend_cpu: float = 0.0
	var rend_gpu: float = 0.0
	if vp != null:
		var rid: RID = vp.get_viewport_rid()
		rend_cpu = RenderingServer.viewport_get_measured_render_time_cpu(rid)
		rend_gpu = RenderingServer.viewport_get_measured_render_time_gpu(rid)
	$Panel/V/Counters.text = "\n".join([
		"%5.1f ms      %5.1f fps" % [ms, 1000.0 / maxf(ms, 0.001)],
		"%5.1f gpu     %5.1f render cpu" % [rend_gpu, rend_cpu],
		"%5d draws   %6d prims" % [draws, prims],
		"%5.1f MB video" % [mem],
		"MEASURE times each part for real" if not HudProfile.has_measured()
			else "measured: ms the frame gains without it",
	])
	# The graph's scale is printed rather than assumed, because it snaps when a
	# frame goes badly and a reader comparing two screenshots would otherwise
	# read a shorter bar as a faster frame.
	$Panel/V/GraphNote.text = "200 frames, lines at 60 and 30 fps, top %d ms" % [
		int($Panel/V/Graph.ceiling_ms())]
	Paint.tint($Panel/V/GraphNote, "font_color", Palette.DIM)
	Paint.tint($Panel/V/Counters, "font_color",
		Palette.OK if ms < 20.0 else (Palette.AMBER if ms < 40.0 else Palette.CRIT))
	# A frame measured with something switched off is not the game's frame, and
	# it is very easy to forget that and quote the number anyway.
	var dirty: bool = DebugFlags.modified()
	$Panel/V/Head/Title.text = "DEBUG  (MODIFIED)" if dirty else "DEBUG"
	Paint.tint($Panel/V/Head/Title, "font_color",
		Palette.AMBER if dirty else Palette.DIM)


func _on_flag(id: String) -> void:
	DebugFlags.advance(id)
	_paint_buttons()


## Each switch, with what that part of the interface actually costs beside it.
##
## The number is the point. A switch says what something is worth by removing
## it, which needs two readings and a steady hand, and there are eleven of them.
## Printing the measurement means the list reads worst first at a glance and
## nobody has to toggle anything to find out where the time went.
func _paint_buttons() -> void:
	var ids: Array = DebugFlags.ids()
	for i in range(mini(SLOTS, ids.size())):
		var id: String = String(ids[i])
		var b: Button = _slot(i)
		var caption: String = DebugFlags.caption(id)
		var part: String = DebugFlags.part(id)
		if not part.is_empty():
			# The measured cost when the sweep has produced one, and the issue
			# time in brackets until then. Never the issue time alone and never
			# unlabelled: it reads like a cost, it is not one, and presenting it
			# as one sent two rounds of work at the wrong target.
			if HudProfile.is_measured(part):
				caption += "   %+5.1f ms" % (HudProfile.measured_us(part) / 1000.0)
			else:
				var us: float = HudProfile.issue_us(part)
				caption += "   %s" % ("      -" if us < 0.0
					else "(%.2f)" % (us / 1000.0))
		b.text = caption
		var entry: Dictionary = DebugFlags.spec(id)
		var default_on: bool = String(entry["kind"]) != "bool" or DebugFlags.on(id)
		Paint.tint(b, "font_color",
			Palette.FG if default_on else Palette.AMBER)
		b.tooltip_text = "%s\ncost: %s" % [String(entry["note"]), String(entry["cost"])]


## Measure every part by removing it, one at a time.
##
## Only bool flags that own a timing bucket are swept. The master switch is not
## one of them: it would measure the whole interface, which is the one number
## the panel can already show by being turned off once.
func _start_sweep() -> void:
	_sweep = []
	for id in DebugFlags.ids():
		var key: String = String(id)
		if key == "hud" or DebugFlags.part(key).is_empty():
			continue
		if String(DebugFlags.spec(key)["kind"]) != "bool":
			continue
		_sweep.append(key)
	# Everything back on first, or a part left off from a previous session
	# would be measured against a baseline that already excluded it.
	DebugFlags.reset()
	var combat: Node = get_node_or_null("/root/Main/Root/Content/Combat")
	if combat != null:
		_sweep_was_paused = bool(combat.paused)
		combat.paused = true
	_sweep_sum = {}
	_sweep_pass = 0
	_sweep_at = 0
	_sweep_phase = 0
	_sweep_baseline = -1.0
	_sweep_frames = 0
	_sweep_elapsed = 0.0


## One frame of the sweep. -1 is the baseline pass with everything on; every
## step after it has exactly one part switched off.
func _step_sweep(delta: float) -> void:
	_sweep_frames += 1
	if _sweep_frames > SWEEP_SETTLE:
		_sweep_elapsed += delta
	if _sweep_frames < SWEEP_SETTLE + SWEEP_SAMPLE:
		_paint_sweep_progress()
		return

	var ms: float = (_sweep_elapsed / float(SWEEP_SAMPLE)) * 1000.0
	var id: String = String(_sweep[_sweep_at])
	if _sweep_phase == 0:
		# Baseline for this part, with everything on. Now switch it off.
		_sweep_baseline = ms
		_sweep_phase = 1
		DebugFlags.set_on(id, false)
	else:
		# The frame gained this much without it. Accumulated across passes and
		# divided at the end, so one unlucky pass cannot be the answer.
		var part: String = DebugFlags.part(id)
		_sweep_sum[part] = float(_sweep_sum.get(part, 0.0)) \
			+ (_sweep_baseline - ms) * 1000.0
		DebugFlags.set_on(id, true)
		_sweep_phase = 0
		_sweep_at += 1
	_sweep_frames = 0
	_sweep_elapsed = 0.0
	if _sweep_at < _sweep.size():
		return
	_sweep_at = 0
	_sweep_pass += 1
	if _sweep_pass < SWEEP_PASSES:
		return
	for part in _sweep_sum:
		HudProfile.set_measured(String(part),
			float(_sweep_sum[part]) / float(SWEEP_PASSES))
	_sweep = []
	_sweep_at = -1
	var combat: Node = get_node_or_null("/root/Main/Root/Content/Combat")
	if combat != null:
		combat.paused = _sweep_was_paused
	_paint_buttons()


func _paint_sweep_progress() -> void:
	$Panel/V/Head/Title.text = "MEASURING %d/%d  pass %d/%d" % [
		_sweep_at + 1, _sweep.size(), _sweep_pass + 1, SWEEP_PASSES]
	Paint.tint($Panel/V/Head/Title, "font_color", Palette.CYAN)
	$Panel/V/Counters.text = "hold still.\nswitching each part off in turn\nand timing the frame without it."
