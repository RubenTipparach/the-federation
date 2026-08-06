class_name ArcWheelControl
extends Control

## The 12 sector firing arc wheel (docs/02 section 4.4). Angle is bearing,
## radius is effective range: both dimensions carry information. Everything
## drawn here is read from a ShipFit through the one fitting implementation;
## this control computes nothing about arcs itself.

## How many range rings to rule the wheel with. A drawing decision like the
## step count of an arc, not a tuning value: WHERE they fall is read from the
## catalog, which is the part that has to stay honest.
const RANGE_RINGS: int = 4

var _fit: ShipFit
var _isolated_mount: String = ""
var _range_max: float = WeaponModel.longest_range()


func show_fit(fit: ShipFit, isolated_mount: String) -> void:
	_fit = fit
	_isolated_mount = isolated_mount
	queue_redraw()


func _radius_for_range(rng: float, r0: float, r_max: float) -> float:
	return r0 + minf(rng, _range_max) / _range_max * (r_max - r0)


func _dir(bearing_deg: float) -> Vector2:
	var a: float = deg_to_rad(bearing_deg)
	return Vector2(sin(a), -cos(a))


func _sector_band(center: Vector2, sectors: Array[int], r0: float,
		r1: float) -> Array[PackedVector2Array]:
	# One polygon per contiguous run so a wrapped arc draws correctly. The
	# grouping itself lives in Sectors.contiguous_runs, shared with the labels.
	var out: Array[PackedVector2Array] = []
	for run in Sectors.contiguous_runs(sectors):
		var deg0: float = float(int(run[0])) * Sectors.SECTOR_DEG
		var deg1: float = deg0 + float(run.size()) * Sectors.SECTOR_DEG
		var steps: int = maxi(run.size() * 4, 4)
		var poly: PackedVector2Array = PackedVector2Array()
		for i in range(steps + 1):
			poly.append(center + _dir(lerpf(deg0, deg1, float(i) / steps)) * r1)
		for i in range(steps + 1):
			poly.append(center + _dir(lerpf(deg1, deg0, float(i) / steps)) * r0)
		out.append(poly)
	return out


func _draw() -> void:
	if _fit == null:
		return
	var center: Vector2 = size * 0.5
	var r_max: float = minf(size.x, size.y) * 0.40
	var r0: float = r_max * 0.16
	var font: Font = get_theme_default_font()

	# Range rings, at even fractions of the longest reach in the catalog.
	#
	# These were the literals 5, 10, 15 and 20, which is the hardcoded tuning
	# CLAUDE.md 5.4 forbids, and it had already stopped meaning anything: the
	# wheel's outer edge is the longest weapon in the catalog, so once that was
	# 88 the four rings were all inside the innermost quarter, and once it was
	# 352 they were a squashed stack of digits over the hub. A grid drawn from
	# the same number the wheel is scaled to cannot go out of step with it
	# again, whatever the reaches are retuned to.
	for step in range(1, RANGE_RINGS + 1):
		var rng: float = _range_max * float(step) / float(RANGE_RINGS)
		var rr: float = _radius_for_range(rng, r0, r_max)
		draw_arc(center, rr, 0.0, TAU, 64, Palette.LINE, 1.0)
		draw_string(font, center + Vector2(4, -rr + 12), str(int(rng)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, Paint.TYPE_SIZE, Palette.DIM)

	# Sector spokes and bearing labels.
	for i in range(Sectors.COUNT):
		var d: Vector2 = _dir(float(i) * Sectors.SECTOR_DEG)
		draw_line(center + d * r0, center + d * r_max, Palette.LINE, 1.0)
		var mid: Vector2 = _dir(float(i) * Sectors.SECTOR_DEG + Sectors.SECTOR_DEG * 0.5)
		var brg_w: float = Paint.type_width(4)
		draw_string(font, center + mid * (r_max + 10.0) + Vector2(-brg_w * 0.5, 4),
			"%03d" % (i * int(Sectors.SECTOR_DEG)),
			HORIZONTAL_ALIGNMENT_CENTER, brg_w, Paint.TYPE_SIZE, Palette.DIM)

	# Shield facing bands outside, so arcs read against facings.
	for f in range(Sectors.FACING_COUNT):
		var a0: float = deg_to_rad(f * 60.0 - 25.0) - PI * 0.5
		var a1: float = deg_to_rad(f * 60.0 + 25.0) - PI * 0.5
		draw_arc(center, r_max + 22.0, a0, a1, 16, Palette.CYAN_DIM, 4.0)
		var mid: Vector2 = _dir(f * 60.0)
		var fm_w: float = Paint.type_width(2)
		draw_string(font, center + mid * (r_max + 36.0) + Vector2(-fm_w * 0.5, 4),
			Sectors.facing_mark(f), HORIZONTAL_ALIGNMENT_CENTER, fm_w,
			Paint.TYPE_SIZE, Palette.CYAN)

	# Blind bearings, hatched critical.
	var blind: Array[int] = _fit.blind_sectors()
	if not blind.is_empty():
		for poly in _sector_band(center, blind, r0, r_max):
			draw_colored_polygon(poly, Palette.with_alpha(Palette.CRIT, 0.14))
			draw_polyline(poly + PackedVector2Array([poly[0]]),
				Palette.with_alpha(Palette.CRIT, 0.6), 1.0)

	# One wedge per fitted mount, radius is that weapon's range.
	for m in _fit.mounts():
		var w: Dictionary = _fit.weapon_in(String(m["id"]))
		if w.is_empty():
			continue
		var isolated: bool = _isolated_mount == String(m["id"])
		var dimmed: bool = not _isolated_mount.is_empty() and not isolated
		var field: Array[int] = _fit.effective_field(m)
		var rr: float = _radius_for_range(WeaponModel.max_range(w), r0, r_max)
		var fill_alpha: float = 0.07 if dimmed else (0.3 if isolated else 0.15)
		var overridden: bool = bool(w.get("special", false)) and w.has("override_field")
		var edge: Color = Palette.AMBER if overridden else Palette.MAGENTA
		for poly in _sector_band(center, field, r0, rr):
			draw_colored_polygon(poly, Palette.with_alpha(Palette.MAGENTA, fill_alpha))
			if not dimmed:
				draw_polyline(poly + PackedVector2Array([poly[0]]),
					Palette.with_alpha(edge, 0.8), 1.4)
		# The isolated mount also shows its permitted field as a thin outline,
		# which is what separates the mount's arc from the weapon's reach.
		if isolated:
			var mount_field: Array[int] = Catalog.to_int_array(m["field"])
			for poly in _sector_band(center, mount_field, r0, r_max):
				draw_polyline(poly + PackedVector2Array([poly[0]]),
					Palette.with_alpha(Palette.CYAN_DIM, 0.75), 1.0)

	# Hub.
	draw_circle(center, r0 - 5.0, Palette.PANEL_2)
	draw_arc(center, r0 - 5.0, 0.0, TAU, 32, Palette.LINE, 1.0)
	var bow_w: float = Paint.type_width(8)
	draw_string(font, center + Vector2(-bow_w * 0.5, 4), "BOW 000",
		HORIZONTAL_ALIGNMENT_CENTER, bow_w, Paint.TYPE_SIZE, Palette.DIM)
