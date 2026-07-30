extends SceneTree

## Headless test suite for the simulation library. Runs without instantiating
## a single game scene, which is exactly what CLAUDE.md 5.2 demands of the sim.
##
##   ./scripts/run-tests.sh
##   (or) godot --headless --script res://tests/run_tests.gd
##
## Scripts are preloaded by path, not referenced by class_name, so the suite
## also runs on a cold checkout before the editor has built its class cache.

const SectorsLib = preload("res://src/sim/sectors.gd")
const CatalogLib = preload("res://src/sim/catalog.gd")
const PowerLib = preload("res://src/sim/power.gd")
const FitLib = preload("res://src/sim/fit.gd")
const ShipLib = preload("res://src/sim/ship_state.gd")
const BattleLib = preload("res://src/sim/battle.gd")

var checks: int = 0
var failures: int = 0


func ok(cond: bool, label: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAIL  ", label)
	else:
		print("ok    ", label)


func eq(a: Variant, b: Variant, label: String) -> void:
	ok(a == b, "%s  (got %s, want %s)" % [label, str(a), str(b)])


func near(a: float, b: float, label: String, tol: float = 0.001) -> void:
	ok(absf(a - b) <= tol, "%s  (got %f, want %f)" % [label, a, b])


func _initialize() -> void:
	test_sectors()
	test_catalog()
	test_fit()
	test_power()
	test_damage()
	test_movement_and_weapons()
	test_battle_and_ai()
	print("")
	if failures == 0:
		print("ALL TESTS PASSED  (%d checks)" % checks)
	else:
		print("%d OF %d CHECKS FAILED" % [failures, checks])
	quit(0 if failures == 0 else 1)


func test_sectors() -> void:
	print("\n== sectors ==")
	# The facing table from docs/02 section 4.1, verified exhaustively.
	var expected: Array = [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 0]
	for s in range(12):
		eq(SectorsLib.facing_of_sector(s), expected[s], "facing of sector %d" % s)
	eq(SectorsLib.sector_of_bearing(0.0), 0, "bearing 0 in sector 0")
	eq(SectorsLib.sector_of_bearing(29.9), 0, "bearing 29.9 in sector 0")
	eq(SectorsLib.sector_of_bearing(30.0), 1, "bearing 30 in sector 1")
	eq(SectorsLib.sector_of_bearing(345.0), 11, "bearing 345 in sector 11")
	eq(SectorsLib.sector_of_bearing(-15.0), 11, "bearing -15 wraps to sector 11")
	eq(SectorsLib.facing_of_relative_bearing(359.0), 0, "359 is the fore facing")
	eq(SectorsLib.facing_of_relative_bearing(90.0), 2, "090 is aft starboard")
	near(SectorsLib.bearing_between(Vector2.ZERO, Vector2(0, 10)), 0.0, "bearing to +z is 000")
	near(SectorsLib.bearing_between(Vector2.ZERO, Vector2(10, 0)), 90.0, "bearing to +x is 090")
	near(SectorsLib.turn_delta(350.0, 10.0), 20.0, "turn delta wraps left to right")
	near(SectorsLib.turn_delta(10.0, 350.0), -20.0, "turn delta wraps right to left")
	eq(SectorsLib.label_for_sectors([5, 6, 7]), "150-240", "run label")
	eq(SectorsLib.label_for_sectors([8]), "240-270", "single sector label")
	eq(SectorsLib.label_for_sectors([11, 0]), "330-030", "wrapped run label")
	eq(SectorsLib.label_for_sectors([]), "none", "empty label")
	eq(SectorsLib.label_for_sectors(range(12)), "000-360", "full circle label")


func test_catalog() -> void:
	print("\n== catalog ==")
	ok(CatalogLib.hulls().size() >= 5, "hull catalog loads")
	ok(CatalogLib.weapons().size() >= 6, "weapon catalog loads")
	ok(CatalogLib.tuning().has("camera"), "tuning loads")
	eq(CatalogLib.playable_hull_ids().size(), 3, "three playable hulls")
	eq(CatalogLib.ai_hull_ids().size(), 2, "two ai hulls")
	var field: Array = CatalogLib.to_int_array(CatalogLib.hull("wayfarer")["mounts"][0]["field"])
	ok(field[0] is int, "sector fields coerce to int")
	var floor_deg: float = float(CatalogLib.tuning()["camera"]["pitch_floor_deg"])
	ok(floor_deg >= 25.0, "camera pitch floor is downward only")


func test_fit() -> void:
	print("\n== fitting ==")
	var fit = FitLib.create_default("wayfarer")
	var b: Dictionary = fit.budgets()
	# These exact numbers are the approved mockup's budget readout.
	near(b["space"]["used"], 118.0, "default wayfarer space used")
	near(b["power"]["used"], 38.0, "default wayfarer power demand")
	near(b["mass"]["used"], 131.0, "default wayfarer mass used")
	near(b["crew"]["used"], 152.0, "default wayfarer crew used, over budget by design")
	ok(b["crew"]["used"] > b["crew"]["max"], "crew overage is representable")

	eq(fit.blind_sectors(), Array([8], TYPE_INT, "", null), "wayfarer blind bearing is sector 8")
	eq(fit.derived()["blind_label"], "240-270", "blind label matches mockup")
	eq(fit.alpha_into(0), 24, "alpha into the bow is 24")
	eq(fit.alpha_into(8), 0, "alpha into the blind sector is 0")

	var mounts: Array = fit.mounts()
	ok(not fit.is_legal(mounts[1], CatalogLib.weapon("photon")), "torpedo rejected by family in a beam mount")
	ok(not fit.is_legal(mounts[4], CatalogLib.weapon("ph1")), "medium weapon rejected by a light mount")
	ok(fit.is_legal(mounts[4], CatalogLib.weapon("omni")), "special weapon accepted anywhere it fits")
	ok(fit.set_slot("M5", "omni"), "omni fits the aft mount")
	eq(fit.blind_sectors().size(), 0, "special override closes the blind bearing")
	eq(fit.alpha_into(8), 5, "omni projects 5 into the old blind sector")
	ok(not fit.set_slot("M5", "photon"), "illegal refit is refused and")
	eq(String(fit.slots["M5"]), "omni", "the slot is unchanged after a refused refit")


func test_power() -> void:
	print("\n== power ==")
	var split: Dictionary = PowerLib.default_split()
	near(PowerLib.total_frac(split), 1.0, "default split sums to 1")
	PowerLib.rebalance(split, "weapons", 0.9)
	near(PowerLib.total_frac(split), 1.0, "sum invariant after a large push")
	near(float(split["weapons"]), 0.9, "pushed sink holds its value")
	PowerLib.rebalance(split, "shields", 1.0)
	near(PowerLib.total_frac(split), 1.0, "sum invariant at the extreme")
	PowerLib.rebalance(split, "engines", 0.0)
	near(PowerLib.total_frac(split), 1.0, "sum invariant after zeroing")


func _fresh_ship(hull: String = "wayfarer", seed_value: int = 7) -> Variant:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	return ShipLib.create(FitLib.create_default(hull), rng)


func test_damage() -> void:
	print("\n== damage model ==")
	var ship = _fresh_ship()
	var boxes_before: int = ship.total_boxes()
	eq(boxes_before, 70, "wayfarer starts with 70 internal boxes")

	# 16 into a 24 shield: absorbed fully, nothing inside is touched.
	ship.apply_damage(0.0, 16.0)
	near(ship.shields[0], 8.0, "16 damage leaves the fore shield at 8")
	eq(ship.total_boxes(), boxes_before, "no internal damage while the shield holds")

	# 16 more: the facing collapses and exactly 8 boxes bleed through.
	ship.apply_damage(0.0, 16.0)
	near(ship.shields[0], 0.0, "fore shield collapses")
	eq(ship.total_boxes(), boxes_before - 8, "exactly the bleed through reaches internals")
	for f in range(1, 6):
		near(ship.shields[f], ship.shield_max, "facing %d untouched" % (f + 1))

	# Heading matters: the same world bearing now strikes a different facing.
	var turned = _fresh_ship()
	turned.heading = 90.0
	turned.apply_damage(90.0, 10.0)
	near(turned.shields[0], turned.shield_max - 10.0, "world 090 on heading 090 strikes the fore facing")
	var flank = _fresh_ship()
	flank.apply_damage(90.0, 10.0)
	near(flank.shields[2], flank.shield_max - 10.0, "world 090 on heading 000 strikes facing 3")

	# Destroying a weapon's boxes disables its mount.
	var hulk = _fresh_ship()
	hulk.apply_internal(200.0)
	eq(hulk.total_boxes(), 0, "massive internal damage empties the ship")
	ok(not hulk.alive, "a ship with no boxes is destroyed")
	ok(hulk.mount_disabled(0), "weapon mounts are disabled with their boxes gone")

	# Reinforcement spends the battery, once.
	var def = _fresh_ship()
	def.battery = 1.0
	def.shields[3] = 2.0
	ok(def.reinforce(3, CatalogLib.tuning()), "reinforce fires with a charged battery")
	near(def.shields[3], 8.0, "reinforce restores the tuned amount")
	ok(not def.reinforce(3, CatalogLib.tuning()), "battery is spent after one reinforce")


func test_movement_and_weapons() -> void:
	print("\n== movement and weapons ==")
	var tuning: Dictionary = CatalogLib.tuning()
	var ship = _fresh_ship()
	ship.set_order(90.0, 1.0)
	for i in range(600):
		ship.step(1.0 / 15.0, tuning)
	near(ship.heading, 90.0, "ship settles on the ordered heading", 0.5)
	ok(ship.speed > ship.max_speed() * 0.8, "ship reaches cruise under full throttle")

	var still = _fresh_ship()
	still.set_order(0.0, 0.0)
	# In arc and range dead ahead.
	var target_pos: Vector2 = still.pos + Vector2(0, 8)
	eq(String(still.fire_check(1, target_pos)["reason"]), "charging", "capacitor gates the shot")
	for i in range(200):
		still.step(1.0 / 15.0, tuning)
	eq(String(still.fire_check(1, target_pos)["reason"]), "bears", "charged weapon in arc and range bears")
	# The blind quarter: sector 8 for the wayfarer fit.
	var blind_pos: Vector2 = still.pos + Vector2(
		sin(deg_to_rad(255.0)), cos(deg_to_rad(255.0))) * 5.0
	var none_bear: bool = true
	for i in range(still.weapons_rt.size()):
		if bool(still.fire_check(i, blind_pos)["ok"]):
			none_bear = false
	ok(none_bear, "nothing fires into the blind bearing")
	eq(String(still.fire_check(0, still.pos + Vector2(0, 25))["reason"]), "range",
		"out of range is reported as range")

	# Engine damage slows the ship through one shared integrity path.
	var lame = _fresh_ship()
	for sys in lame.systems:
		if String(sys["family"]) == "power":
			sys["boxes"] = 0
	near(lame.max_speed(), 0.0, "no power boxes means no speed")
	near(lame.power_output(), 0.0, "no power boxes means no reactor output")


func test_battle_and_ai() -> void:
	print("\n== battle and ai ==")
	var battle = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 1234)
	eq(battle.ships.size(), 2, "duel has two ships")
	var dist0: float = battle.player().pos.distance_to(battle.enemy().pos)
	# The player sits idle; the AI must close and eventually land hits.
	battle.player().set_order(battle.player().heading, 0.0)
	var shield_hit: bool = false
	for i in range(15 * 120):
		battle.step(1.0 / 15.0)
		if battle.over:
			break
		for f in range(6):
			if battle.player().shields[f] < battle.player().shield_max - 0.5:
				shield_hit = true
	var dist1: float = battle.player().pos.distance_to(battle.enemy().pos)
	ok(dist1 < dist0, "the ai closes the range")
	ok(shield_hit, "the ai lands hits on an idle target")
	ok(is_finite(battle.enemy().pos.x) and is_finite(battle.enemy().pos.y), "no numeric blowups")

	# Victory is declared when a ship runs out of boxes.
	var quick = BattleLib.create_duel(FitLib.create_default("wayfarer"), "talon", 99)
	quick.enemy().apply_internal(500.0)
	quick.step(1.0 / 15.0)
	ok(quick.over, "battle ends when a ship is destroyed")
	eq(quick.winner, 0, "the surviving side wins")

	# The player fire path is the same code the ai uses.
	var duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 5)
	duel.player().pos = Vector2.ZERO
	duel.player().heading = 0.0
	duel.enemy().pos = Vector2(0, 8)
	# Pin the target heading too: the shot arrives at world bearing 180, which
	# on heading 000 is relative 180, sector 6, the aft facing (index 3).
	duel.enemy().heading = 0.0
	for w in duel.player().weapons_rt:
		w["charge"] = 1.0
	var fired: int = duel.fire_family(duel.player(), "beam")
	ok(fired >= 1, "fire_family fires the beams that bear")
	ok(duel.enemy().shields[3] < duel.enemy().shield_max, "shots strike the facing toward the attacker")
