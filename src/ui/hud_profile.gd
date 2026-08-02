class_name HudProfile
extends RefCounted

## What each part of the interface costs, measured on the machine it is slow on.
##
## The overlay's switches say what a part is worth by removing it, which needs a
## toggle, a steady hand and two readings. This says the same thing without
## touching anything, which matters because the interface has eleven parts and
## nobody is going to toggle eleven switches twice on a phone.
##
## It exists because of one reading. On the phone the overlay was built for:
## 45.8 milliseconds a frame, 38.4 of it script and 7.4 of it everything the
## renderer does. Eighty four percent of the frame was our own GDScript. Once
## that is known, the only useful question left is WHICH of our code, and no
## instrument answered it on the device.
##
## TWO NUMBERS, AND ONLY ONE OF THEM IS THE ANSWER.
##
## `issue_us` is time spent inside the call that updates a panel. It is honest
## about what it measures and it is NOT what the panel costs, because almost
## none of the work happens there. Setting `Label.text` returns in under a
## microsecond: it marks the item dirty and leaves. Re-shaping the text and
## rebuilding that item's draw commands happen later, in the engine's canvas
## flush, outside any bracket we can put around our own calls.
##
## Measured on the phone, which is how this was caught: switching off panels
## whose issue time totalled 1.07 ms took 18.1 ms off the frame. Seventeen
## times. Quoting the issue time as the cost was wrong and it sent two rounds
## of work at the wrong target.
##
## `measured_us` is the truth: the frame got this much faster with the part
## switched off. It comes from the sweep in debug_panel.gd, which does by
## itself what a person would otherwise do by hand with a stopwatch and eleven
## screenshots. It catches everything, including the drawing and the engine
## work that no stopwatch of ours can see.
##
## Issue time is kept because the gap between the two IS information: a part
## whose issue time is most of its measured cost is our code, and one where it
## is a rounding error is the renderer.
##
## One implementation, called from one place per part (CLAUDE.md 4.1). Do not
## time a panel at its call site with a second stopwatch: two of these would
## disagree about what "the weapons panel" includes, and the number would stop
## meaning anything the moment they did.
##
## The cost of measuring is one Time.get_ticks_usec pair per part per tick,
## which is eleven pairs, and is the reason the parts are panels rather than
## individual labels. An instrument that changes what it measures is worse than
## no instrument.

## Microseconds accumulated since the last flush, per part name.
static var _spent: Dictionary = {}
## Microseconds per part, averaged over the last window. What the panel reads.
static var _shown: Dictionary = {}
static var _ticks: int = 0
static var _open: int = 0


## Start timing a part. Returns the stamp to hand back to close().
##
## A stamp rather than a stack, so a part that returns early cannot leave the
## profiler holding an open timer that silently charges its microseconds to
## whatever ran next.
static func open(_part: String) -> int:
	_open += 1
	return Time.get_ticks_usec()


## Close the part opened at `stamp`.
static func close(part: String, stamp: int) -> void:
	_open -= 1
	_spent[part] = float(_spent.get(part, 0.0)) + float(Time.get_ticks_usec() - stamp)


## One whole tick has been accounted for.
static func tick() -> void:
	_ticks += 1


## Average every part over the ticks since the last flush, and start again.
## Called by the debug panel on its own sample window, so the numbers on screen
## and the numbers in the graph came from the same span of time.
static func flush() -> void:
	var ticks: float = maxf(1.0, float(_ticks))
	_shown = {}
	for part in _spent:
		_shown[part] = float(_spent[part]) / ticks
	_spent = {}
	_ticks = 0


## Microseconds spent ISSUING a part's update, per tick, or -1 when it has not
## run since the last flush. Minus one rather than zero, because "not running"
## and "free" are different answers and a reader deserves to tell them apart.
##
## Read the class docstring before quoting this as what a panel costs. It is
## not that, and treating it as that is the mistake this file exists to stop
## anybody making twice.
static func issue_us(part: String) -> float:
	return float(_shown.get(part, -1.0))


## What the frame actually gained with this part switched off, in microseconds,
## or -1 when the sweep has not measured it. This is the number to trust.
static var _measured: Dictionary = {}


static func set_measured(part: String, us: float) -> void:
	_measured[part] = us


## Whether the sweep has a reading for this part. A separate question from the
## value, because a part can genuinely measure NEGATIVE: it is a difference of
## two frame times and noise goes both ways. Using -1 as "no reading" collided
## with that and hid every part whose cost fell below the noise floor, which is
## exactly the set a reader most needs to see marked as measured and small.
static func is_measured(part: String) -> bool:
	return _measured.has(part)


static func measured_us(part: String) -> float:
	return float(_measured.get(part, 0.0))


static func has_measured() -> bool:
	return not _measured.is_empty()


## Everything measured, worst first. For a caller that wants the whole picture
## rather than one part.
static func worst_first() -> Array:
	var out: Array = []
	for part in _shown:
		out.append([float(_shown[part]), String(part)])
	out.sort_custom(func(a, b): return a[0] > b[0])
	return out


## Total across every part, which is what the interface costs per tick.
static func total_us() -> float:
	var sum: float = 0.0
	for part in _shown:
		sum += float(_shown[part])
	return sum
