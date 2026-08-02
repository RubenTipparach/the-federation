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
## Taps on the version label, for the screens that show one. The battle hides
## the top bar for the whole engagement (CLAUDE.md 6.2), which is exactly when
## this is wanted, so the gesture above is the one that actually matters.
const SUMMON_TAPS: int = 3
const SUMMON_WINDOW: float = 1.5

var _since_sample: float = 0.0
var _taps: int = 0
var _tap_window: float = 0.0
## Frame times since the last readout, so the number shown is an average over
## the sample window rather than whichever frame happened to land on it.
var _frames: int = 0
var _elapsed: float = 0.0
## Script time accumulated over the same window as _elapsed. Godot reports its
## timing monitors for the LAST frame only, so sampling one of them against an
## averaged frame time compares two different frames and the split can come out
## inverted. Observed doing exactly that before this was averaged: 18 script
## against 129 rest on one sample and 139 against 5 on the next, with the total
## barely moving.
var _script_elapsed: float = 0.0
## Touch indices currently down. Watched, never consumed: the overlay must not
## be able to swallow a helm order it happened to see first.
var _fingers: Dictionary = {}


func _ready() -> void:
	# The layer stays visible so the summon button does; only the panel hides.
	$Panel.visible = false
	var ids: Array = DebugFlags.ids()
	for i in range(SLOTS):
		var b: Button = _slot(i)
		var wanted: bool = i < ids.size()
		b.visible = wanted
		if wanted:
			b.pressed.connect(_on_flag.bind(String(ids[i])))
	$Summon.pressed.connect(_toggle)
	$Panel/V/Head/Close.pressed.connect(func() -> void: $Panel.visible = false)
	$Panel/V/Head/Reset.pressed.connect(func() -> void:
		DebugFlags.reset()
		_paint_buttons())
	if ids.size() > SLOTS:
		push_warning("debug panel has %d flags and %d slots" % [ids.size(), SLOTS])
	_paint_buttons()


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
	$Panel.visible = not $Panel.visible
	if $Panel.visible:
		_paint_buttons()


## Count taps on whatever handle summons this. Three inside a second and a half,
## which is a run nobody performs by accident and anybody can perform on a
## touch screen without a keyboard.
func note_summon_tap() -> void:
	if _tap_window <= 0.0:
		_taps = 0
	_tap_window = SUMMON_WINDOW
	_taps += 1
	if _taps >= SUMMON_TAPS:
		_taps = 0
		_toggle()


func _process(delta: float) -> void:
	if _tap_window > 0.0:
		_tap_window -= delta
	if not $Panel.visible:
		return
	# Every frame goes into the graph; only the readout and the repaint are
	# throttled. A spike that lands between samples is exactly the thing worth
	# seeing, so it must not be the thing that gets dropped.
	$Panel/V/Graph.push(delta * 1000.0)
	_frames += 1
	_elapsed += delta
	_script_elapsed += (Performance.get_monitor(Performance.TIME_PROCESS)
		+ Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS))
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
	_script_elapsed = 0.0


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
	# Averaged over the same window as the frame time, because Godot reports
	# these for the last frame only and comparing one frame's script time to a
	# hundred frames' average is how a split comes out backwards.
	var script_ms: float = (_script_elapsed / maxf(1.0, float(_frames))) * 1000.0
	var rest_ms: float = maxf(ms - script_ms, 0.0)
	# The parts total against the script total, because the difference is the
	# most useful number on the panel and nobody should have to add up eleven
	# buttons to find it. Script minus parts is everything the interface does
	# NOT account for: the simulation, the 3D rig update, and the engine's own
	# container sorting and minimum size work, which is charged to the process
	# step and is invisible to any stopwatch we put around our own calls.
	var parts_ms: float = HudProfile.total_us() / 1000.0
	$Panel/V/Counters.text = "\n".join([
		"%5.1f ms      %5.1f fps" % [ms, 1000.0 / maxf(ms, 0.001)],
		"%5.1f script  %5.1f rest" % [script_ms, rest_ms],
		"%5.2f ui parts of that script" % [parts_ms],
		"%5d draws   %6d prims" % [draws, prims],
		"%5.1f MB video" % [mem],
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
			var us: float = HudProfile.cost_us(part)
			# Minus one is "not measured since the last flush", which is what a
			# part that is switched off reads. A dash rather than 0.00, because
			# "not running" and "free" are different answers.
			caption += "   %s" % ("    -" if us < 0.0 else "%5.2f ms" % (us / 1000.0))
		b.text = caption
		var entry: Dictionary = DebugFlags.spec(id)
		var default_on: bool = String(entry["kind"]) != "bool" or DebugFlags.on(id)
		Paint.tint(b, "font_color",
			Palette.FG if default_on else Palette.AMBER)
		b.tooltip_text = "%s\ncost: %s" % [String(entry["note"]), String(entry["cost"])]
