class_name Sectors
extends RefCounted

## Bearing and sector math for the 12 sector arc model (docs/02 section 4.1).
##
## Bearing 000 is dead ahead and increases clockwise. Sector i covers
## [i*30, i*30+30). Each of the six shield facings is exactly two sectors, so
## resolving which facing a shot strikes is a lookup, never boundary
## arithmetic. This file is the only place that mapping exists (CLAUDE.md 4.1).

const COUNT: int = 12
const SECTOR_DEG: float = 30.0
const FACING_COUNT: int = 6

## World convention shared with the 3D scene: position is Vector2(x, z) and a
## bearing b points along direction (sin b, cos b), which matches rotate_y.


static func wrap_deg(deg: float) -> float:
	return fposmod(deg, 360.0)


static func sector_of_bearing(deg: float) -> int:
	return int(wrap_deg(deg) / SECTOR_DEG) % COUNT


static func facing_of_sector(sector: int) -> int:
	# facing 0 (fore) is sectors {11, 0}, facing 1 is {1, 2}, and so on.
	@warning_ignore("integer_division")
	return posmod(sector + 1, COUNT) / 2


static func facing_of_relative_bearing(deg: float) -> int:
	return facing_of_sector(sector_of_bearing(deg))


static func relative_bearing(world_bearing: float, heading: float) -> float:
	return wrap_deg(world_bearing - heading)


static func bearing_between(from_pos: Vector2, to_pos: Vector2) -> float:
	var d: Vector2 = to_pos - from_pos
	return wrap_deg(rad_to_deg(atan2(d.x, d.y)))


static func facing_center_bearing(facing: int) -> float:
	# Facing f spans [f*60 - 30, f*60 + 30), so its center is f*60.
	return wrap_deg(float(facing) * 60.0)


## Shortest signed turn from heading a to heading b, in degrees, range -180..180.
static func turn_delta(from_deg: float, to_deg: float) -> float:
	return wrap_deg(to_deg - from_deg + 180.0) - 180.0


## Human readable label for a sector set, e.g. [5, 6, 7] -> "150-240".
## Runs that wrap through sector 0 are joined, matching the mockup.
static func label_for_sectors(sectors: Array) -> String:
	if sectors.is_empty():
		return "none"
	if sectors.size() >= COUNT:
		return "000-360"
	var sorted: Array = sectors.duplicate()
	sorted.sort()
	var runs: Array = []
	var current: Array = [sorted[0]]
	for i in range(1, sorted.size()):
		if int(sorted[i]) == int(sorted[i - 1]) + 1:
			current.append(sorted[i])
		else:
			runs.append(current)
			current = [sorted[i]]
	runs.append(current)
	if runs.size() > 1 and int(runs[0][0]) == 0 and int(runs[-1][-1]) == COUNT - 1:
		var tail: Array = runs.pop_back()
		tail.append_array(runs[0])
		runs[0] = tail
	var parts: Array[String] = []
	for run in runs:
		var a: int = int(run[0]) * int(SECTOR_DEG)
		var b: int = (int(run[-1]) + 1) * int(SECTOR_DEG) % 360
		parts.append("%03d-%03d" % [a % 360, b])
	return ", ".join(parts)
