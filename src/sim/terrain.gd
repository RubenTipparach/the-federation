class_name Terrain
extends RefCounted

## What is in the arena besides the ships (docs/13 sections 1 to 5).
##
## Terrain is circles on the combat plane, because the simulation is planar
## (docs/01) and because a circle is the only shape a player can judge the edge
## of from a plan inset. A feature has a centre, a body radius that is solid,
## and a field radius that does something at a distance.
##
## Pure simulation: no nodes, no rendering. The renderer asks this class the
## same questions the battle does, so there is exactly one answer to "can I see
## him" and one answer to "am I in the dust" (CLAUDE.md 4.1, 5.2).

const KIND_NEBULA: String = "nebula"
const KIND_ASTEROID: String = "asteroid"
const KIND_PLANET: String = "planet"

## Which recipe this was built from. "open" is the empty arena.
var map_id: String = "open"

## Each entry is {kind: String, pos: Vector2, body: float, field: float}.
var features: Array[Dictionary] = []

## The terrain block of data/tuning.json, read once. Held rather than passed in
## per call so that a query needs nothing but geometry (CLAUDE.md 5.4 still
## applies: none of these numbers are written here).
var tuning: Dictionary = {}


func _init() -> void:
	tuning = Catalog.tuning()["terrain"]


## Build the terrain for one battle. Everything is drawn from the battle's own
## rng, so a replay that reproduces the seed reproduces the map with it.
##
## keep_clear holds the starting positions: no ship begins inside a cloud or
## next to a rock, because being wrecked on the first tick is not a tactical
## situation.
##
## The "open" recipe draws nothing at all from the rng, which is what lets an
## open battle stay bit for bit identical to one from before terrain existed.
static func create(p_map_id: String, rng: RandomNumberGenerator,
		keep_clear: Array[Vector2]) -> Terrain:
	var t: Terrain = Terrain.new()
	t.map_id = p_map_id
	var recipe: Dictionary = Catalog.map(p_map_id)
	var half: float = float(Catalog.tuning()["combat"]["arena_half_extent"])
	for spec in recipe["features"]:
		t._place_group(spec, rng, half, keep_clear)
	return t


func _place_group(spec: Dictionary, rng: RandomNumberGenerator, half: float,
		keep_clear: Array[Vector2]) -> void:
	var kind: String = String(spec["kind"])
	var groups: int = _pick_int(spec["count"], rng)
	var tries: int = int(tuning["placement_tries"])
	for _g in range(groups):
		var per_group: int = _pick_int(spec["cluster"], rng)
		var spread: float = float(spec["spread"])
		# A cluster is anchored once and its bodies scatter around the anchor,
		# so a rock field reads as a field rather than as evenly spaced bollards.
		var anchor: Vector2 = Vector2.ZERO
		var anchored: bool = false
		for _i in range(per_group):
			var body: float = _pick_float(spec["body"], rng)
			var field: float = _pick_float(spec["field"], rng)
			var limit: float = maxf(0.0, half - field)
			# A body that will not fit after this many attempts is simply not
			# placed. A recipe asking for five clouds in a crowded arena gets
			# four, rather than an infinite loop or an overlap.
			for _try in range(tries):
				var at: Vector2
				if anchored and spread > 0.0:
					at = anchor + Vector2(
						rng.randf_range(-spread, spread),
						rng.randf_range(-spread, spread))
					at.x = clampf(at.x, -limit, limit)
					at.y = clampf(at.y, -limit, limit)
				else:
					at = Vector2(rng.randf_range(-limit, limit),
						rng.randf_range(-limit, limit))
				if not _acceptable(kind, at, body, field, keep_clear):
					continue
				features.append({ "kind": kind, "pos": at, "body": body, "field": field })
				if not anchored:
					anchor = at
					anchored = true
				break


## Where a body may go. Solid bodies keep clear of the starting positions and of
## each other; clouds only have to leave the starting positions outside
## themselves, because clouds are meant to overlap and to reach across the map.
func _acceptable(kind: String, at: Vector2, body: float, field: float,
		keep_clear: Array[Vector2]) -> bool:
	var clearance: float = float(tuning["spawn_clearance"])
	for start in keep_clear:
		if kind == KIND_NEBULA:
			if at.distance_to(start) <= field:
				return false
		elif at.distance_to(start) <= clearance + body:
			return false
	# A battle must open with a lock. Clouds may degrade the opening line as far
	# as they like, but a fight that begins with neither side able to see the
	# other reads as broken rather than as tense; losing contact should be
	# something a captain does, not something the map did before the first tick.
	if kind == KIND_NEBULA and keep_clear.size() >= 2:
		var opacity: float = maxf(0.001, float(tuning["nebula_opacity_length"]))
		var already: float = obscuration(keep_clear[0], keep_clear[1]) * opacity
		var added: float = _segment_circle_length(keep_clear[0], keep_clear[1], at, field)
		if (already + added) / opacity >= float(tuning["nebula_lock_obscuration"]):
			return false
	if body <= 0.0:
		return true
	for f in features:
		if float(f["body"]) <= 0.0:
			continue
		if at.distance_to(f["pos"]) <= body + float(f["body"]):
			return false
	return true


static func _pick_int(range_pair: Array, rng: RandomNumberGenerator) -> int:
	var lo: int = int(range_pair[0])
	var hi: int = int(range_pair[1])
	return lo if hi <= lo else rng.randi_range(lo, hi)


static func _pick_float(range_pair: Array, rng: RandomNumberGenerator) -> float:
	var lo: float = float(range_pair[0])
	var hi: float = float(range_pair[1])
	return lo if hi <= lo else rng.randf_range(lo, hi)


# ---- line of sight -----------------------------------------------------------

## How much cloud lies between two points, as a multiple of the length that
## counts as fully opaque. Zero in clear space, and it grows with the path
## through the cloud rather than switching on at its edge, so hiding one metre
## inside a nebula hides nothing (docs/13 section 2.1).
func obscuration(a: Vector2, b: Vector2) -> float:
	if features.is_empty():
		return 0.0
	var inside: float = 0.0
	for f in features:
		if String(f["kind"]) != KIND_NEBULA:
			continue
		inside += _segment_circle_length(a, b, f["pos"], float(f["field"]))
	if inside <= 0.0:
		return 0.0
	return inside / maxf(0.001, float(tuning["nebula_opacity_length"]))


## The range the gunnery computer believes it is shooting at. Cloud is added to
## the true distance, and the existing range falloff in WeaponModel does the
## rest: no second damage rule is written for nebulae (CLAUDE.md 4.1).
func apparent_range(a: Vector2, b: Vector2, actual: float) -> float:
	if features.is_empty():
		return actual
	return actual + obscuration(a, b) * float(tuning["nebula_range_penalty"])


## True when there is too much cloud in the way to hold a lock at all. Both
## directions give the same answer because it is the same segment, which is what
## stops a nebula from being a free win.
func lock_broken(a: Vector2, b: Vector2) -> bool:
	if features.is_empty():
		return false
	return obscuration(a, b) >= float(tuning["nebula_lock_obscuration"])


## Length of the part of segment a-b that lies inside a circle. Solved rather
## than sampled, so the answer does not depend on a step size and a replay
## cannot drift.
static func _segment_circle_length(a: Vector2, b: Vector2, centre: Vector2,
		radius: float) -> float:
	if radius <= 0.0:
		return 0.0
	var d: Vector2 = b - a
	var span: float = d.length()
	if span <= 0.0001:
		return 0.0
	var f: Vector2 = a - centre
	var qa: float = d.dot(d)
	var qb: float = 2.0 * f.dot(d)
	var qc: float = f.dot(f) - radius * radius
	var disc: float = qb * qb - 4.0 * qa * qc
	if disc <= 0.0:
		return 0.0
	var root: float = sqrt(disc)
	var t0: float = clampf((-qb - root) / (2.0 * qa), 0.0, 1.0)
	var t1: float = clampf((-qb + root) / (2.0 * qa), 0.0, 1.0)
	return maxf(0.0, t1 - t0) * span


# ---- hazards -----------------------------------------------------------------

## The drift a gravity well wants to give a ship here: toward the centre, zero
## at the well's edge, strongest at the surface. This is a velocity the ship
## acquires, not a force integrated into its own, which is stable at any
## timestep and therefore replayable (docs/13 section 4.1).
func pull_at(at: Vector2) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for f in features:
		if String(f["kind"]) != KIND_PLANET:
			continue
		var to_centre: Vector2 = Vector2(f["pos"]) - at
		var dist: float = to_centre.length()
		var field: float = float(f["field"])
		if dist >= field or dist <= 0.0001:
			continue
		var depth: float = 1.0 - dist / field
		total += to_centre / dist * float(tuning["planet_pull"]) * depth
	return total


## Damage per second from micrometeor dust here, at this speed. Halos stack, so
## the middle of a cluster is the worst place to be, and a ship crawling through
## takes far less than one charging through.
func grind_at(at: Vector2, speed: float) -> float:
	var total: float = 0.0
	for f in features:
		if String(f["kind"]) != KIND_ASTEROID:
			continue
		var dist: float = at.distance_to(f["pos"])
		var body: float = float(f["body"])
		var field: float = float(f["field"])
		if dist >= field or field <= body:
			continue
		var depth: float = clampf((field - dist) / (field - body), 0.0, 1.0)
		total += float(tuning["asteroid_grind_dps"]) * depth
	if total <= 0.0:
		return 0.0
	var factor: float = float(tuning["asteroid_grind_speed_floor"]) \
		+ speed / maxf(0.001, float(tuning["asteroid_grind_speed_ref"]))
	return total * factor


## The solid body a point is inside, if any: {kind, pos, damage}. A collision is
## an event with a cost, not a simulation of contact (docs/13 section 3.2).
func collision_at(at: Vector2) -> Dictionary:
	for f in features:
		var body: float = float(f["body"])
		if body <= 0.0:
			continue
		if at.distance_to(f["pos"]) > body:
			continue
		return {
			"kind": String(f["kind"]),
			"pos": Vector2(f["pos"]),
			"damage": collision_damage(String(f["kind"])),
		}
	return {}


func collision_damage(kind: String) -> float:
	match kind:
		KIND_PLANET:
			return float(tuning["planet_collision_damage"])
		KIND_ASTEROID:
			return float(tuning["asteroid_collision_damage"])
	return 0.0


func features_of(kind: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in features:
		if String(f["kind"]) == kind:
			out.append(f)
	return out
