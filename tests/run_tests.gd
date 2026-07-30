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
const WeaponLib = preload("res://src/sim/weapon_model.gd")
const YardLib = preload("res://src/sim/shipyard.gd")

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
	test_sector_damage()
	test_falloff()
	test_movement_and_weapons()
	test_battle_and_ai()
	test_shipyard()
	print("")
	if failures == 0:
		print("ALL TESTS PASSED  (%d checks)" % checks)
	else:
		print("%d OF %d CHECKS FAILED" % [failures, checks])
	quit(0 if failures == 0 else 1)


func test_shipyard() -> void:
	print("\n== shipyard ==")
	var yard = YardLib.create(FitLib.create_default("wayfarer"), 12400,
		["lance", "photon", "ph1"], ["ph3"])
	yard.adopt_fit()

	eq(yard.cargo_capacity(), 30, "the wayfarer hold is 30 space")
	eq(yard.list_price(yard.shop[0]), 3400, "the shop charges list")
	eq(yard.sale_price(yard.cargo[0]), 252, "the yard pays 60 percent for fresh gear")
	var hurt: Dictionary = yard._make("ph1", true, 0.5)
	eq(yard.sale_price(hurt), 270, "damaged gear sells for its remaining fraction")

	# Moving your own gear costs nothing, in either direction.
	var fitted_m4: Dictionary = yard.fitted_in("M4")
	ok(not fitted_m4.is_empty(), "the default fit is adopted into the transaction")
	ok(bool(yard.move(String(fitted_m4["uid"]), YardLib.CARGO)["ok"]), "a mount can be stripped")
	eq(int(yard.tally()["balance"]), 0, "stripping a mount into the hold is free")
	ok(bool(yard.move(String(fitted_m4["uid"]), "mount", "M4")["ok"]), "and refitted")
	eq(int(yard.tally()["balance"]), 0, "refitting your own gear is free")

	# Buying and selling move the balance, and the two net off.
	var lance_uid: String = String(yard.shop[0]["uid"])
	ok(bool(yard.move(lance_uid, YardLib.CARGO)["ok"]), "a lance can be bought into the hold")
	eq(int(yard.tally()["purchases"]), 3400, "the purchase is tallied")
	eq(int(yard.tally()["credits_after"]), 12400 - 3400, "credits after reflects the purchase")
	ok(bool(yard.move(String(fitted_m4["uid"]), YardLib.SHOP)["ok"]), "a fitted phaser can be sold")
	eq(int(yard.tally()["sales"]), 540, "the sale is tallied at 60 percent")
	eq(int(yard.tally()["balance"]), 540 - 3400, "balance is sales minus purchases")

	# Nothing is charged until confirm.
	eq(yard.credits, 12400, "credits are untouched before confirming")
	ok(yard.can_confirm(), "a settleable transaction can be confirmed")
	eq(yard.confirm(), 12400 - 3400 + 540, "confirm settles once")
	eq(int(yard.tally()["balance"]), 0, "the tally is clear after settling")
	ok(not yard.can_confirm(), "an empty transaction cannot be confirmed")

	# The three refusals, each named.
	var poor = YardLib.create(FitLib.create_default("wayfarer"), 500, ["lance"])
	poor.adopt_fit()
	poor.move(String(poor.shop[0]["uid"]), YardLib.CARGO)
	ok(not poor.can_confirm(), "a captain cannot spend past zero")
	ok(String(poor.blockers()[0]).contains("Short"), "and is told how short they are")

	var stuffed = YardLib.create(FitLib.create_default("talon"), 99999,
		["lance", "photon", "disruptor"])
	stuffed.adopt_fit()
	for entry in stuffed.shop.duplicate():
		stuffed.move(String(entry["uid"]), YardLib.CARGO)
	ok(stuffed.cargo_used() > stuffed.cargo_capacity(), "the frigate hold overflows")
	ok(not stuffed.can_confirm(), "an overfull hold blocks confirming")
	ok(String(stuffed.blockers()[0]).contains("over capacity"), "and says by how much")

	var wrong = YardLib.create(FitLib.create_default("wayfarer"), 99999, ["photon"])
	wrong.adopt_fit()
	var refused: Dictionary = wrong.move(String(wrong.shop[0]["uid"]), "mount", "M2")
	ok(not bool(refused["ok"]), "a torpedo is refused by a beam mount")
	eq(wrong.shop.size(), 1, "a refused move leaves the item where it was")

	# A weapon dropped onto an occupied mount unships the old one to the hold.
	var swap = YardLib.create(FitLib.create_default("wayfarer"), 99999, ["ph1"])
	swap.adopt_fit()
	var held: int = swap.cargo.size()
	swap.move(String(swap.shop[0]["uid"]), "mount", "M2")
	eq(swap.cargo.size(), held + 1, "the displaced weapon lands in the hold")
	eq(String(swap.fit.slots["M2"]), "ph1", "and the new one is fitted")


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
	var runs: Array = SectorsLib.contiguous_runs([9, 10, 11, 0, 1])
	eq(runs.size(), 1, "wrap through zero groups into one run")
	eq(int(runs[0][0]), 9, "wrapped run starts at its true beginning")

	eq(SectorsLib.facing_name(0), "Bow", "facing 1 is the bow")
	eq(SectorsLib.facing_name(3), "Stern", "facing 4 is the stern")
	eq(SectorsLib.facing_arc_label(0), "330-030", "the bow arc straddles dead ahead")
	eq(SectorsLib.facing_arc_label(1), "030-090", "the starboard bow arc")
	eq(SectorsLib.facing_name(6), "Bow", "facing names wrap")


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
	hulk.apply_internal(200.0, 0)
	eq(hulk.total_boxes(), 0, "massive internal damage empties the ship")
	ok(not hulk.alive, "a ship with no boxes is destroyed")
	ok(hulk.mount_disabled(0), "weapon mounts are disabled with their boxes gone")

	# Fractional bleed through must not round up: the expected boxes destroyed
	# equal the damage on average, and never exceed ceil while integer amounts
	# stay exact. With amount 0.0 nothing may happen.
	var frac_ship = _fresh_ship("wayfarer", 11)
	var before: int = frac_ship.total_boxes()
	frac_ship.apply_internal(0.0, 0)
	eq(frac_ship.total_boxes(), before, "zero bleed destroys nothing")
	frac_ship.apply_internal(5.0, 0)
	eq(frac_ship.total_boxes(), before - 5, "integer bleed destroys exactly its amount")
	var lo: int = 0
	var hi: int = 0
	for trial in range(40):
		var t = _fresh_ship("wayfarer", 100 + trial)
		var b0: int = t.total_boxes()
		t.apply_internal(7.7, 0)
		var lost: int = b0 - t.total_boxes()
		ok(lost == 7 or lost == 8, "fractional bleed 7.7 destroys 7 or 8 boxes")
		if lost == 7:
			lo += 1
		else:
			hi += 1
	ok(lo > 0 and hi > 0, "fractional bleed is a chance, not a constant ceil")

	# Reinforcement spends the battery, once.
	var def = _fresh_ship()
	def.battery = 1.0
	def.shields[3] = 2.0
	ok(def.reinforce(3, CatalogLib.tuning()), "reinforce fires with a charged battery")
	near(def.shields[3], 8.0, "reinforce restores the tuned amount")
	ok(not def.reinforce(3, CatalogLib.tuning()), "battery is spent after one reinforce")

	# Target selection: the sim owns it, so the touch buttons and any future
	# squadron UI cycle the same thing the shot resolves against.
	var duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "talon", 77)
	var me = duel.player()
	eq(duel.foes_of(me).size(), 1, "a duel offers one target")
	eq(duel.target_for(me), duel.enemy(), "the default target is the only hostile")
	duel.set_target(me, duel.enemy())
	eq(duel.target_for(me), duel.enemy(), "an explicit target is remembered")
	duel.enemy().alive = false
	eq(duel.foes_of(me).size(), 0, "a dead hostile leaves the target list")
	ok(duel.target_for(me) != null, "target_for still answers with no hostiles left")


func test_sector_damage() -> void:
	print("\n== sector damage ==")
	var ship = _fresh_ship()
	eq(ship.boxes_in(0) + ship.boxes_in(1) + ship.boxes_in(2) + ship.boxes_in(3)
		+ ship.boxes_in(4) + ship.boxes_in(5) + ship.boxes_in(ShipLib.CORE),
		ship.total_boxes(), "every box belongs to exactly one sector or the core")
	eq(ship.boxes_in(ShipLib.CORE), 16, "the wayfarer core is hull plus armor")

	# A downed facing exposes its own sector and nothing else.
	var flanked = _fresh_ship("wayfarer", 3)
	var other_before: Array[int] = []
	for f in range(6):
		other_before.append(flanked.boxes_in(f))
	var core_before: int = flanked.boxes_in(ShipLib.CORE)
	flanked.shields[1] = 0.0
	flanked.apply_internal(4.0, 1)
	eq(flanked.boxes_in(1), other_before[1] - 4, "the struck sector loses exactly the bleed")
	eq(flanked.boxes_in(ShipLib.CORE), core_before, "the core is untouched while the sector holds")
	for f in [0, 2, 3, 4, 5]:
		eq(flanked.boxes_in(f), other_before[f], "sector %d is untouched" % (f + 1))

	# Strip a sector and the hull core takes the rest, in full.
	var stripped = _fresh_ship("wayfarer", 5)
	var sector_size: int = stripped.boxes_in(1)
	stripped.apply_internal(float(sector_size) + 5.0, 1)
	eq(stripped.boxes_in(1), 0, "the sector is stripped bare")
	eq(stripped.boxes_in(ShipLib.CORE), 16 - 5, "the overflow lands on the hull core")
	ok(stripped.alive, "a ship with a hollow sector is still fighting")

	# Only when the core is gone too does damage carry to the neighbours.
	var gutted = _fresh_ship("wayfarer", 9)
	var spill: int = gutted.boxes_in(1) + gutted.boxes_in(ShipLib.CORE)
	var neighbours_before: int = gutted.boxes_in(0) + gutted.boxes_in(2)
	var far_before: int = gutted.boxes_in(3) + gutted.boxes_in(4) + gutted.boxes_in(5)
	gutted.apply_internal(float(spill) + 3.0, 1)
	eq(gutted.boxes_in(1), 0, "sector emptied")
	eq(gutted.boxes_in(ShipLib.CORE), 0, "core emptied")
	eq(gutted.boxes_in(0) + gutted.boxes_in(2), neighbours_before - 3,
		"the adjacent facings take exactly what is left over")
	eq(gutted.boxes_in(3) + gutted.boxes_in(4) + gutted.boxes_in(5), far_before,
		"the far side of the ship is not touched while neighbours hold")
	ok(gutted.alive, "neighbours still holding means the ship lives")

	# A weapon dies with the sector it sits in.
	var silenced = _fresh_ship("wayfarer", 21)
	silenced.apply_internal(float(silenced.boxes_in(1)), 1)
	var m2_index: int = -1
	for i in range(silenced.weapons_rt.size()):
		if String(silenced.weapons_rt[i]["mount"]["id"]) == "M2":
			m2_index = i
	ok(m2_index >= 0 and silenced.mount_disabled(m2_index),
		"stripping the starboard bow silences the mount that lives there")

	# The talon has empty sectors on purpose: bleed through goes straight to the
	# core rather than vanishing.
	var frigate = _fresh_ship("talon", 4)
	eq(frigate.boxes_in(1), 0, "the talon carries nothing behind facing 2")
	var frigate_core: int = frigate.boxes_in(ShipLib.CORE)
	frigate.apply_internal(2.0, 1)
	eq(frigate.boxes_in(ShipLib.CORE), frigate_core - 2, "an empty sector passes damage to the core")

	# Every hull's totals survived the regrouping.
	for id in CatalogLib.hulls().keys():
		var s2 = ShipLib.create(FitLib.create_default(String(id)),
			RandomNumberGenerator.new(), false)
		ok(s2.total_boxes() > 0, "%s has internals" % [String(id)])
		eq(s2.boxes_in(ShipLib.CORE) > 0, true, "%s has a hull core" % [String(id)])


func test_falloff() -> void:
	print("\n== range falloff ==")
	var ph1: Dictionary = CatalogLib.weapon("ph1")
	var photon: Dictionary = CatalogLib.weapon("photon")
	var disr: Dictionary = CatalogLib.weapon("disruptor")

	near(WeaponLib.max_range(ph1), 10.0, "reach is the outer edge of the last band")
	eq(WeaponLib.max_damage(ph1), 8, "point blank damage is the first band")

	# A band edge belongs to its own band: at exactly 2.0 the shot is still
	# point blank, at a hair beyond it is not. Off by one here would silently
	# change every weapon's profile.
	eq(WeaponLib.damage_at(ph1, 2.0), 8, "the band edge is inside the band")
	eq(WeaponLib.damage_at(ph1, 2.001), 7, "just past the edge is the next band")
	eq(WeaponLib.damage_at(ph1, 0.0), 8, "muzzle contact is point blank")
	eq(WeaponLib.damage_at(ph1, 10.0), 2, "the last band reaches the stated range")
	eq(WeaponLib.damage_at(ph1, 10.5), 0, "beyond reach scores nothing")
	near(WeaponLib.hit_chance_at(ph1, 10.5), 0.0, "beyond reach cannot connect")

	# The three shapes from docs/09: beams lose damage and keep accuracy,
	# torpedoes keep damage and lose accuracy, disruptors lose both.
	near(WeaponLib.hit_chance_at(ph1, 9.0), 1.0, "a beam still connects at its edge")
	ok(WeaponLib.damage_at(ph1, 9.0) < WeaponLib.max_damage(ph1), "a beam weakens with range")
	eq(WeaponLib.damage_at(photon, 19.0), WeaponLib.max_damage(photon),
		"a torpedo hits as hard at the edge as at the muzzle")
	ok(WeaponLib.hit_chance_at(photon, 19.0) < 1.0, "a torpedo loses accuracy instead")
	ok(WeaponLib.damage_at(disr, 11.0) < WeaponLib.max_damage(disr)
		and WeaponLib.hit_chance_at(disr, 11.0) < 1.0, "a disruptor loses both")

	# Expected damage must never rise with range, for every weapon in the
	# catalog. A band typo that made a weapon better far away would pass every
	# test above and be found by a player instead.
	for id in CatalogLib.weapons().keys():
		var w: Dictionary = CatalogLib.weapon(String(id))
		var reach: float = WeaponLib.max_range(w)
		var prev: float = WeaponLib.expected_damage_at(w, 0.0)
		var monotonic: bool = true
		var d: float = 0.0
		while d <= reach:
			var cur: float = WeaponLib.expected_damage_at(w, d)
			if cur > prev + 0.0001:
				monotonic = false
			prev = cur
			d += reach / 40.0
		ok(monotonic, "%s never scores more at a longer range" % [String(id)])
		near(WeaponLib.expected_damage_at(w, reach + 0.1), 0.0,
			"%s scores nothing past its reach" % [String(id)])

	# Rolling honours the band: a certain weapon always scores its band damage,
	# and an uncertain one misses sometimes and scores full damage otherwise.
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 99
	var beam_rolls_low: bool = false
	for i in range(200):
		if WeaponLib.roll_damage(ph1, 5.0, rng) != 5:
			beam_rolls_low = true
	ok(not beam_rolls_low, "a certain beam always scores its band damage")

	var misses: int = 0
	var partials: int = 0
	for i in range(400):
		var scored: int = WeaponLib.roll_damage(photon, 18.0, rng)
		if scored == 0:
			misses += 1
		elif scored != WeaponLib.max_damage(photon):
			partials += 1
	ok(misses > 0, "a long torpedo shot can miss")
	eq(partials, 0, "a torpedo that connects scores in full")
	near(float(misses) / 400.0, 1.0 - WeaponLib.hit_chance_at(photon, 18.0),
		"miss rate tracks the band's hit chance", 0.08)

	near(WeaponLib.longest_range(), 22.0, "the arc chart scale comes from the catalog")

	# A shot resolved through a ship carries the same numbers.
	var shooter = _fresh_ship()
	var mark = _fresh_ship()
	mark.pos = shooter.pos + Vector2(0.0, 3.0)
	var fit: Variant = shooter.fit
	near(fit.expected_into(0, 0.0), float(fit.alpha_into(0)),
		"expected damage at point blank equals the projected alpha")
	ok(fit.expected_into(0, 9.0) < float(fit.alpha_into(0)),
		"the same broadside is worth less at range")


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

	# Events fired between steps must be returned by the NEXT step, never lost:
	# player fire buttons run from UI signals between physics frames.
	var shot_events: int = 0
	for e in duel.step(1.0 / 15.0):
		if String(e["type"]) == "shot":
			shot_events += 1
	ok(shot_events >= fired, "between step fire events survive into the next step")

	# The AI presents a STRONGER neighbor when its exposed facing is weak.
	# Turning the heading clockwise moves the foe's relative bearing counter
	# clockwise, so +offset presents the left facing; the sign was once
	# inverted and the AI showed its weaker side.
	var rot = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 42)
	var ai_ship = rot.enemy()
	ai_ship.pos = Vector2.ZERO
	ai_ship.heading = 0.0
	rot.player().pos = Vector2(0, 10)
	rot.player().heading = 180.0
	ai_ship.shields[0] = 0.5           # exposed fore facing is nearly gone
	ai_ship.shields[1] = ai_ship.shield_max
	ai_ship.shields[5] = 1.0           # left neighbor is nearly gone too
	var AiLib = preload("res://src/sim/ai.gd")
	AiLib.act(ai_ship, rot.player(), rot)
	# Right (facing 1) is the strong side; presenting it means turning the
	# heading counter clockwise, an ordered heading left of the foe bearing.
	near(SectorsLib.turn_delta(0.0, ai_ship.ordered_heading), -60.0,
		"ai turns to present the stronger neighbor facing", 0.5)
