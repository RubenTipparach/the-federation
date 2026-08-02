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
## Accumulated per tick and averaged over the panel's sample window, because a
## single tick of any one panel is noise: the damage report costs nothing until
## something is damaged, and the station panels cost whatever the open station
## happens to be.
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


## Microseconds a part costs per tick, or -1 when it has not been measured
## since the last flush. Minus one rather than zero, because "not running" and
## "free" are different answers and a reader deserves to be able to tell.
static func cost_us(part: String) -> float:
	return float(_shown.get(part, -1.0))


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
