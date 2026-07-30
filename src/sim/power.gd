class_name PowerModel
extends RefCounted

## The energy allocation model (docs/01 section 3). Allocation is stored as
## FRACTIONS of reactor output summing to 1.0, so when reactor boxes are
## destroyed every sink scales down automatically and the invariant "the total
## is always exactly the output" cannot drift.

const EPS: float = 0.0001


static func sinks() -> Array:
	return Catalog.tuning()["power"]["sinks"]


static func default_split(ai_ship: bool = false) -> Dictionary:
	var key: String = "ai_split" if ai_ship else "default_split"
	var src: Dictionary = Catalog.tuning()["power"][key]
	var out: Dictionary = {}
	for s in sinks():
		out[s] = float(src.get(s, 0.0))
	_normalize(out)
	return out


## Set one sink to a target fraction and take the difference from the other
## sinks, largest first, so the sum stays exactly 1. Mirrors the approved
## mockup's rebalance behavior.
static func rebalance(split: Dictionary, key: String, want_frac: float) -> void:
	assert(split.has(key), "unknown power sink: " + key)
	var want: float = clampf(want_frac, 0.0, 1.0)
	var delta: float = want - float(split[key])
	split[key] = want
	var guard: int = 0
	while absf(delta) > EPS and guard < 200:
		guard += 1
		var others: Array = []
		for s in split:
			if s != key:
				others.append(s)
		others.sort_custom(func(a, b): return float(split[a]) > float(split[b]))
		var moved: bool = false
		for s in others:
			if delta > 0.0 and float(split[s]) > 0.0:
				var take: float = minf(float(split[s]), delta)
				split[s] = float(split[s]) - take
				delta -= take
				moved = true
				break
			elif delta < 0.0:
				split[s] = float(split[s]) - delta
				delta = 0.0
				moved = true
				break
		if not moved:
			# Every other sink is empty and more was requested: give it back.
			split[key] = float(split[key]) - delta
			delta = 0.0
	_normalize(split)


static func _normalize(split: Dictionary) -> void:
	var total: float = 0.0
	for s in split:
		total += float(split[s])
	if total <= EPS:
		for s in split:
			split[s] = 1.0 / float(split.size())
		return
	for s in split:
		split[s] = float(split[s]) / total


static func total_frac(split: Dictionary) -> float:
	var t: float = 0.0
	for s in split:
		t += float(split[s])
	return t
