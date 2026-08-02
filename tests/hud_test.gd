extends SceneTree

## The HUD must never lie about the ship.
##
## Panels are only repainted when a facet they depend on has moved (HudFeed),
## which is worth about 2.4x on the update path and is exactly the kind of
## optimisation that fails silently. A missed facet does not crash, does not
## warn, and does not show up in a screenshot taken at the wrong moment: it
## just leaves one readout frozen at whatever it said when the dependency was
## last noticed, which in a fight is worse than showing nothing.
##
## So this drives a real battle for a thousand ticks, taking damage, and after
## every tick compares what each panel SAYS against what the ship IS. Not the
## repaint count, not a heuristic: the actual strings on the actual labels.
##
## It is deliberately reading the same values the panels format from, which
## makes it a change detector rather than a second implementation of the
## formatting: if a panel changes what it prints, this fails and is updated,
## which is the point at which somebody should be checking the facet anyway.

const TICKS: int = 1000
## Sampled rather than checked every tick, because building the expected
## strings is itself work and a thousand of them per label would dominate the
## run without finding anything the sampled version misses.
const CHECK_EVERY: int = 5

var _checks: int = 0
var _failed: int = 0
var _first_failure: String = ""


func _fail(what: String, got: String, want: String) -> void:
	_failed += 1
	if _first_failure.is_empty():
		_first_failure = "%s\n     panel says: %s\n     ship  says: %s" % [what, got, want]


func _ok(what: String, got: String, want: String) -> void:
	_checks += 1
	if got != want:
		_fail(what, got, want)


func _initialize() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame
	main.show_tab("Combat")
	main._on_begin_battle()
	for i in range(10):
		await process_frame

	var c: Node = main.get_node("Root/Content/Combat")
	var battle = c.battle

	print("")
	print("Driving %d ticks and checking every panel against the ship" % TICKS)
	for tick in range(TICKS):
		battle.step(1.0 / 60.0)
		c._refresh_hud()
		if tick % CHECK_EVERY != 0:
			continue
		var me = battle.player()

		_ok("ship panel, boxes and speed and heading",
			c.get_node("Left/ShipPanel/V/Body").text,
			"\n".join([
				"BOXES  %d / %d" % [me.total_boxes(), me.total_boxes_max()],
				"SPEED  %.1f / %.1f" % [me.speed, me.max_speed()],
				"HEADING  %03d  ordered %03d" % [int(me.heading), int(me.ordered_heading)],
			]))

		_ok("power panel, reactor output",
			c.get_node("Left/PowerPanel/V/Head").text,
			"POWER  %d / %d" % [int(me.power_output()),
				int(me.fit.hull()["budgets"]["power"])])

		var dmg: Array[String] = []
		for sys in me.systems:
			if int(sys["boxes"]) < int(sys["boxes_max"]):
				dmg.append("%s  %d/%d" % [String(sys["code"]), int(sys["boxes"]),
					int(sys["boxes_max"])])
		_ok("damage report, every damaged system",
			c.get_node("Left/DamagePanel/V/BodyScroll/Body").text,
			"No damage." if dmg.is_empty() else "\n".join(dmg))

		_ok("weapons panel, battery",
			c.get_node("Right/WeaponsPanel/V/Battery").text,
			"BATTERY %d%%" % int(me.battery * 100.0))

		if battle.over:
			break

	print("")
	if _failed == 0:
		print("ALL HUD CHECKS PASSED  (%d checks, no panel went stale)" % _checks)
	else:
		print("HUD CHECKS FAILED  (%d of %d went stale)" % [_failed, _checks])
		print("  first:  %s" % _first_failure)
	quit(1 if _failed > 0 else 0)
