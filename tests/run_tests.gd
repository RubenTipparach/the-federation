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
const SeekerLib = preload("res://src/sim/seeker.gd")
const LogLib = preload("res://src/sim/battle_log.gd")
const RepairLib = preload("res://src/sim/repair_model.gd")
const TerrainLib = preload("res://src/sim/terrain.gd")
const TractorLib = preload("res://src/sim/tractor.gd")
const BoardingLib = preload("res://src/sim/boarding.gd")
const SessionLib = preload("res://src/ui/session.gd")

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
	test_overload()
	test_movement_and_weapons()
	test_battle_and_ai()
	test_contacts()
	test_debris()
	test_boarding()
	test_fleet()
	test_seekers()
	test_shields()
	test_repairs()
	test_shipyard()
	test_planet_materials()
	test_terrain()
	test_tractors()
	test_replay()
	print("")
	if failures == 0:
		print("ALL TESTS PASSED  (%d checks)" % checks)
	else:
		print("%d OF %d CHECKS FAILED" % [failures, checks])
	quit(0 if failures == 0 else 1)


## Everything a hull's size decides: when two of them are touching, what that
## costs, and the distance the opponent will not come inside.
func test_contacts() -> void:
	print("\n== ships in contact ==")
	var combat: Dictionary = CatalogLib.tuning()["combat"]
	var AiLib = preload("res://src/sim/ai.gd")

	var big = _fresh_ship("ironhold")
	var small = _fresh_ship("talon")
	ok(big.radius() > small.radius(), "a heavier hull is a bigger hull")
	near(big.radius(), float(CatalogLib.hull("ironhold")["tonnage"])
		* float(combat["hull_radius_per_ton"]), "and its size comes from the tuning file")
	near(big.contact_distance(small), small.contact_distance(big),
		"contact distance reads the same from either side")

	small.pos = Vector2.ZERO
	big.pos = Vector2(0.0, small.contact_distance(big) * 0.9)
	ok(small.touching(big), "hulls closer than that are touching")
	big.pos = Vector2(0.0, small.contact_distance(big) * 1.1)
	ok(not small.touching(big), "and further apart are not")

	# A real contact in a real battle. Capacitors start empty and a single
	# thirtieth of a second charges nothing, so the only damage either hull can
	# take over the next two steps is the collision.
	var duel = BattleLib.create_duel(FitLib.create_default("talon"), "ironhold", 5)
	var light = duel.player()
	var heavy = duel.enemy()
	light.pos = Vector2.ZERO
	heavy.pos = Vector2(0.0, light.contact_distance(heavy) * 0.5)
	var rams: int = 0
	for e in duel.step(1.0 / 30.0):
		if String(e.get("hazard", "")) == "ship":
			rams += 1
	eq(rams, 2, "contact bills both hulls, not only the one that moved")
	var light_hurt: float = _hurt(light)
	var heavy_hurt: float = _hurt(heavy)
	ok(light_hurt > 0.0 and heavy_hurt > 0.0, "both of them pay for it")
	ok(light_hurt > heavy_hurt, "and the lighter hull pays more")
	ok(light.collision_grace > 0.0 and heavy.collision_grace > 0.0,
		"both are given a moment before it can happen again")

	var again: int = 0
	for e in duel.step(1.0 / 30.0):
		if String(e.get("hazard", "")) == "ship":
			again += 1
	eq(again, 0, "so resting in contact is not billed every tick")

	# The keep out distance. Put the opponent well inside it and it stops
	# fighting and runs, whatever its guns or its shields would prefer.
	var keep = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 31)
	var idle = keep.player()
	var foe = keep.enemy()
	idle.pos = Vector2.ZERO
	foe.pos = Vector2(0.0, foe.contact_distance(idle) * 2.0)
	var away: float = SectorsLib.bearing_between(idle.pos, foe.pos)
	AiLib.act(foe, idle, keep)
	near(SectorsLib.turn_delta(away, foe.ordered_heading), 0.0,
		"inside the keep out the ai steers straight away from the player", 0.5)
	near(foe.ordered_throttle, 1.0, "and gives it everything")

	# And over a whole battle it never gets there in the first place. The
	# player is left at rest, so every closing decision in this run is the
	# opponent's own.
	var run = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 77)
	var closest: float = 1.0e9
	for i in range(3000):
		if run.over:
			break
		run.step(1.0 / 30.0)
		closest = minf(closest, run.player().pos.distance_to(run.enemy().pos))
	ok(closest > run.player().contact_distance(run.enemy()),
		"a captain who never touches the helm is never rammed by the ai")
	ok(closest > run.player().contact_distance(run.enemy())
		* float(CatalogLib.tuning()["ai"]["standoff_radii"]) * 0.5,
		"and the ai keeps a real distance rather than shaving it")


## Damage a ship is carrying, shields and boxes together, as one number to
## compare two hulls with.
func _hurt(ship: Variant) -> float:
	var standing: float = 0.0
	for v in ship.shields:
		standing += float(v)
	return float(ship.shield_max) * float(ship.shields.size()) - standing \
		+ float(ship.total_boxes_max() - ship.total_boxes())


func test_seekers() -> void:
	print("\n== seeking weapons ==")
	var tuning: Dictionary = CatalogLib.tuning()
	var battle = BattleLib.create_duel(FitLib.create_default("ironhold"), "talon", 5)
	var me = battle.player()
	var foe = battle.enemy()
	# Put them nose to nose so the drone rack bears and the flight is short.
	me.pos = Vector2.ZERO
	foe.pos = Vector2(0.0, 6.0)
	me.heading = 0.0
	for i in range(400):
		me.step(1.0 / 15.0, tuning)

	var drone_index: int = -1
	for i in range(me.weapons_rt.size()):
		if String(me.weapons_rt[i]["mount"]["id"]) == "M5":
			drone_index = i
	ok(drone_index >= 0, "the ironhold carries a drone rack aft")
	me.heading = 180.0  # bring the aft mount to bear on a target dead astern
	foe.pos = Vector2(0.0, 6.0)

	var boxes_before: int = foe.total_boxes()
	var shields_before: float = 0.0
	for f in range(6):
		shields_before += foe.shields[f]
	ok(battle.try_fire(me, drone_index), "the rack launches")
	eq(battle.seekers.size(), 1, "a launch puts a weapon in flight, not damage on the target")
	eq(foe.total_boxes(), boxes_before, "nothing has been hit yet")

	# Fly it home. The frigate has no point defense, so it arrives.
	for i in range(240):
		battle.step(1.0 / 15.0)
		if battle.seekers.is_empty():
			break
	eq(battle.seekers.size(), 0, "the seeker resolves rather than orbiting forever")
	var shields_after: float = 0.0
	for f in range(6):
		shields_after += foe.shields[f]
	# The frigate's shield takes it, which is the point: a drone that lands is
	# damage on the facing it arrived through, not a free hit on the internals.
	ok(shields_after < shields_before or foe.total_boxes() < boxes_before,
		"and it damages what it reaches")

	# Point defense: the wayfarer's PH-3 shoots drones down.
	var defended = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 9)
	var guard = defended.player()
	guard.pos = Vector2.ZERO
	near(guard.point_defense_dps(Vector2(0.0, 2.0)), 1.6, "a PH-3 defends at close range")
	var pd_reach: float = float(CatalogLib.weapon("ph3")["pd_range"])
	near(guard.point_defense_dps(Vector2(0.0, pd_reach * 1.5)), 0.0,
		"and not across the arena")
	for sys in guard.systems:
		if String(sys["mount_id"]) == "M5":
			sys["boxes"] = 0
	near(guard.point_defense_dps(Vector2(0.0, 2.0)), 0.0,
		"a destroyed mount stops defending")

	var hunted = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 3)
	hunted.player().pos = Vector2.ZERO
	hunted.enemy().pos = Vector2(0.0, 5.0)
	var drone: Dictionary = CatalogLib.weapon("drone")
	var seeker = SeekerLib.launch(hunted.enemy(), hunted.player(), drone)
	hunted.seekers.append(seeker)
	var start_boxes: int = hunted.player().total_boxes()
	for i in range(200):
		hunted.step(1.0 / 15.0)
		if hunted.seekers.is_empty():
			break
	ok(hunted.seekers.is_empty(), "the drone is resolved one way or the other")
	eq(hunted.player().total_boxes(), start_boxes,
		"point defense kills the drone before it lands")


func test_shields() -> void:
	print("\n== shields ==")
	var tuning: Dictionary = CatalogLib.tuning()
	var ship = _fresh_ship()

	# Federation Commander 3C7: a shield box is bought for energy, and nothing
	# comes back unbought. A ship spending nothing on shields recovers nothing,
	# however long it waits.
	var broke = _fresh_ship()
	broke.shields[0] = 0.0
	broke.set_alloc_units("shields", 0.0)
	for i in range(300):
		broke.step(1.0 / 15.0, tuning)
	near(broke.shields[0], 0.0, "with no power to the shields nothing regenerates")

	# Bias is which shield is bought for, not a weighting: the picked facing
	# takes every box until it is full.
	ship.shields[0] = 0.0
	ship.shields[1] = 0.0
	ship.shield_bias = 0
	for i in range(60):
		ship.step(1.0 / 15.0, tuning)
	ok(ship.shields[0] > 0.0, "the picked facing is bought back")
	near(ship.shields[1], 0.0, "and the others get nothing while it is short")

	# Boxes are whole. A shield never sits on a fraction of one.
	near(ship.shields[0] - floorf(ship.shields[0]), 0.0, "regeneration arrives in whole boxes")

	# With no facing picked, the weakest is the one bought for, so two equally
	# hurt facings come back together rather than one being starved.
	var unbiased = _fresh_ship()
	unbiased.shields[0] = 0.0
	unbiased.shields[1] = 0.0
	for i in range(60):
		unbiased.step(1.0 / 15.0, tuning)
	ok(absf(unbiased.shields[0] - unbiased.shields[1]) <= 1.0,
		"with no pick the weakest facing is bought for, so the two stay level")
	ok(unbiased.shields[0] + unbiased.shields[1] > 0.0, "and they do recover")

	# Transfer, Federation Commander 3C3: adjacent only, never above full.
	var mover = _fresh_ship()
	mover.shields[1] = 10.0
	ok(mover.transfer_shield(0, 1, tuning), "strength moves to an adjacent facing")
	near(mover.shields[1], 15.0, "the neighbour gains the transfer amount")
	near(mover.shields[0], mover.shield_max - 5.0, "and the donor loses it")
	ok(not mover.transfer_shield(0, 3, tuning), "a facing two steps away is refused")
	ok(not mover.transfer_shield(2, 2, tuning), "a facing cannot feed itself")
	var full = _fresh_ship()
	ok(not full.transfer_shield(0, 1, tuning), "nothing moves into an undamaged facing")
	var drained = _fresh_ship()
	drained.shields[0] = 0.0
	drained.shields[1] = 0.0
	ok(not drained.transfer_shield(0, 1, tuning), "an empty facing has nothing to give")
	var partial = _fresh_ship()
	partial.shields[1] = partial.shield_max - 2.0
	ok(partial.transfer_shield(0, 1, tuning), "a nearly full facing takes what it can")
	near(partial.shields[1], partial.shield_max, "and stops at full")
	near(partial.shields[0], partial.shield_max - 2.0, "the donor gives only that much")


func test_repairs() -> void:
	print("\n== repairs ==")
	var tuning: Dictionary = CatalogLib.tuning()
	var ship = _fresh_ship()

	ok(ship.parts > 0, "a ship sails with spare parts aboard")
	eq(ship.parts, ship.parts_max, "and starts with a full hold")

	# Find a weapon system and shoot two boxes off it.
	var index: int = -1
	for i in range(ship.systems.size()):
		if String(ship.systems[i]["family"]) == "weapon" and int(ship.systems[i]["boxes_max"]) >= 3:
			index = i
			break
	ok(index >= 0, "the hull carries a weapon system to break")
	var sys: Dictionary = ship.systems[index]
	var full: int = int(sys["boxes_max"])
	sys["boxes"] = full - 2

	# Pricing is per box, not per system (5G4).
	var per_box: int = RepairLib.parts_per_box("weapon", tuning)
	eq(RepairLib.job_cost(sys, tuning), per_box * 2, "a job costs per box, not per system")
	ok(RepairLib.parts_per_box("weapon", tuning) > RepairLib.parts_per_box("hull", tuning),
		"a weapon box costs more than a hull box, as 5G3 orders them")

	# Queueing rules.
	ok(ship.queue_repair(index, tuning), "a damaged system can be queued")
	ok(not ship.queue_repair(index, tuning), "and cannot be queued twice")
	eq(ship.repair_queue.size(), 1, "the queue holds it once")
	var whole: int = -1
	for i in range(ship.systems.size()):
		if int(ship.systems[i]["boxes"]) >= int(ship.systems[i]["boxes_max"]):
			whole = i
			break
	ok(whole >= 0, "the ship has an undamaged system")
	ok(not ship.queue_repair(whole, tuning), "an undamaged system is refused")

	# Work it. One box at a time, paid for out of the hold.
	var before: int = ship.parts
	var need: float = RepairLib.seconds_per_box("weapon", tuning)
	var per_step: float = 1.0 / 15.0
	var steps: int = int(need / float(ship.damage_control) / per_step) + 2
	for i in range(steps):
		ship.step(per_step, tuning)
	eq(int(sys["boxes"]), full - 1, "one box comes back at a time")
	eq(ship.parts, before - per_box, "and is paid for out of the hold")

	# Finishing the job clears it from the queue.
	for i in range(steps):
		ship.step(per_step, tuning)
	eq(int(sys["boxes"]), full, "the job runs to full")
	eq(ship.repair_queue.size(), 0, "and leaves the queue when it is done")

	# A queue the hold cannot pay for stalls rather than working for free.
	var poor = _fresh_ship()
	var pi: int = -1
	for i in range(poor.systems.size()):
		if String(poor.systems[i]["family"]) == "weapon":
			pi = i
			break
	poor.systems[pi]["boxes"] = 0
	poor.parts = 0
	ok(poor.queue_repair(pi, tuning), "a job can be ordered with an empty hold")
	for i in range(steps * 2):
		poor.step(per_step, tuning)
	eq(int(poor.systems[pi]["boxes"]), 0, "but nothing is repaired without parts")
	eq(poor.repair_queue.size(), 1, "and the job waits rather than being dropped")

	# Shields are not repaired this way at all (5G3).
	var shielded = _fresh_ship()
	shielded.shields[0] = 0.0
	for entry in shielded.systems:
		ok(String(entry["family"]) != "shield", "no system claims the shield family")
		break

	# Dropping a job takes it out and lets the next one start.
	var two = _fresh_ship()
	var a: int = -1
	var b: int = -1
	for i in range(two.systems.size()):
		if int(two.systems[i]["boxes_max"]) >= 2:
			two.systems[i]["boxes"] = int(two.systems[i]["boxes_max"]) - 1
			if a < 0:
				a = i
			elif b < 0:
				b = i
			else:
				break
	two.queue_repair(a, tuning)
	two.queue_repair(b, tuning)
	eq(two.repair_queue.size(), 2, "two jobs queue in order")
	eq(two.repair_queue[0], a, "the first ordered is the first worked")
	ok(two.drop_repair(a), "a job can be dropped")
	eq(two.repair_queue[0], b, "and the next takes its place")
	ok(not two.drop_repair(a), "dropping it again does nothing")

	# The whole queue's price is what the panel warns against.
	eq(RepairLib.queue_cost(two.systems, two.repair_queue, tuning),
		RepairLib.job_cost(two.systems[b], tuning),
		"the queue costs the sum of its jobs")


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


## A scripted battle: the same orders given at the same ticks every time, which
## is what a replay has to reproduce exactly.
func _scripted_battle(record: bool) -> Variant:
	var fit = FitLib.create_default("wayfarer")
	# M2 carries a disruptor rather than the default beam, so the script can
	# exercise an overload. A replay that never overloads would not prove the
	# order replays, and the overloaded shot is the one whose damage depends on
	# a flag rather than on the geometry.
	fit.set_slot("M2", "disruptor")
	var battle = BattleLib.create_duel(fit, "bloodletter", 4242)
	if record:
		battle.log = LogLib.create(fit, "bloodletter", 4242, 1.0 / 30.0)
	var script: Dictionary = {
		0: [[0, "order", [45.0, 1.0]], [0, "power", ["weapons", 16.0]],
			[0, "power", ["reserve", 20.0]]],
		20: [[0, "fire_family", ["beam"]]],
		48: [[0, "order", [180.0, 0.6]], [0, "shield_bias", [3]]],
		90: [[0, "fire_family", ["heavy"]], [0, "reinforce", [0]]],
		140: [[0, "transfer_shield", [1, 2]], [0, "fire_family", ["beam"]]],
		210: [[0, "order", [300.0, 1.0]], [0, "overload", [1, true]]],
		240: [[0, "fire_family", ["disruptor"]]],
	}
	for i in range(420):
		if script.has(battle.tick):
			for c in script[battle.tick]:
				battle.apply_command(int(c[0]), String(c[1]), c[2])
		if battle.over:
			break
		battle.step(1.0 / 30.0)
	if battle.log != null and battle.log.end_tick < 0:
		battle.log.close(battle)
	return battle


## Terrain: what is in the arena besides the ships (docs/13 sections 1 to 5).
##
## The geometry tests build a Terrain by hand rather than by recipe, because a
## recipe places bodies randomly and a test of "does a gravity well pull" should
## not also be a test of where the planet landed.
## Two worlds in one arena must not share one material.
##
## They did, and it was invisible until a gas giant turned up beside a moon: a
## scene sub resource is SHARED by every instance of that scene unless it is
## marked local, so every world wrote its radius and its colours into the same
## material and the last one placed won. The big world was then drawn at the
## moon's radius, which at tactical range looks exactly like a world that failed
## to render, ring and atmosphere still in place around nothing.
func test_planet_materials() -> void:
	print("\n== planet materials ==")
	var scene: PackedScene = load("res://scenes/terrain/planet.tscn")
	var world: Node3D = scene.instantiate()
	var moon: Node3D = scene.instantiate()
	world.place({"pos": Vector2(120.0, -40.0), "body": 50.0, "field": 180.0,
		"variant": "gas"})
	moon.place({"pos": Vector2(190.0, 30.0), "body": 11.0, "field": 0.0,
		"variant": "moon"})
	var world_mat: ShaderMaterial = world.get_node("Body").material_override
	var moon_mat: ShaderMaterial = moon.get_node("Body").material_override
	ok(world_mat != moon_mat, "two worlds do not share one body material")
	near(float(world_mat.get_shader_parameter("radius")), 50.0,
		"the world keeps its own radius after a moon is placed")
	near(float(moon_mat.get_shader_parameter("radius")), 11.0,
		"the moon keeps its own radius")
	ok(world.get_node("Ring").visible, "a gas giant shows its ring")
	ok(not moon.get_node("Ring").visible, "a moon does not")
	ok(world.get_node("Atmosphere").visible, "a gas giant has air")
	ok(not moon.get_node("Atmosphere").visible, "a moon has none")
	world.free()
	moon.free()


func test_terrain() -> void:
	print("\n== terrain ==")

	# The empty arena must be genuinely free. If placing "open" drew even one
	# number from the battle rng, every battle recorded before terrain existed
	# would replay differently, so this is checked directly.
	var untouched = RandomNumberGenerator.new()
	untouched.seed = 77
	TerrainLib.create("open", untouched, [])
	var fresh = RandomNumberGenerator.new()
	fresh.seed = 77
	near(untouched.randf(), fresh.randf(), "the open map draws nothing from the battle rng")

	var before = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 31)
	var after = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 31, "open")
	for _i in range(120):
		before.step(1.0 / 30.0)
		after.step(1.0 / 30.0)
	eq(str(LogLib.fingerprint(before)), str(LogLib.fingerprint(after)),
		"an open battle matches one created without a map at all")

	# Same seed, same map, same arena. This is what lets a replay rebuild the
	# terrain from the recipe name instead of storing every circle.
	var twin_a = BattleLib.create_duel(FitLib.create_default("wayfarer"), "talon", 4242, "belt")
	var twin_b = BattleLib.create_duel(FitLib.create_default("wayfarer"), "talon", 4242, "belt")
	eq(str(twin_a.terrain.features), str(twin_b.terrain.features),
		"the same seed places the same terrain")
	ok(twin_a.terrain.features.size() >= 8, "the debris belt places a field of rocks")

	# Every recipe must land inside the arena and leave the starting positions
	# survivable, on any seed.
	var half: float = float(CatalogLib.tuning()["combat"]["arena_half_extent"])
	var clearance: float = float(CatalogLib.tuning()["terrain"]["spawn_clearance"])
	var contained: bool = true
	var clear_of_spawns: bool = true
	var bodies_apart: bool = true
	var opens_with_lock: bool = true
	for map_id in CatalogLib.map_ids():
		for seed_value in [1, 2, 3, 17, 900]:
			var b = BattleLib.create_duel(FitLib.create_default("kestrel"),
				"talon", seed_value, String(map_id))
			var starts: Array = [b.player().pos, b.enemy().pos]
			if b.terrain.lock_broken(starts[0], starts[1]):
				opens_with_lock = false
			for f in b.terrain.features:
				var at: Vector2 = f["pos"]
				var body: float = float(f["body"])
				var field: float = float(f["field"])
				if absf(at.x) > half - field + 0.001 or absf(at.y) > half - field + 0.001:
					contained = false
				for start in starts:
					if String(f["kind"]) == TerrainLib.KIND_NEBULA:
						if at.distance_to(start) <= field:
							clear_of_spawns = false
					elif at.distance_to(start) <= clearance + body:
						clear_of_spawns = false
				for g in b.terrain.features:
					if g == f or body <= 0.0 or float(g["body"]) <= 0.0:
						continue
					if at.distance_to(g["pos"]) <= body + float(g["body"]):
						bodies_apart = false
	ok(contained, "every feature lands inside the arena, field and all")
	ok(clear_of_spawns, "nothing is placed on top of a starting position")
	ok(bodies_apart, "solid bodies never overlap each other")

	# Moons. A moon is a planet with no well, which is what keeps it on one
	# collision rule and one scene instead of becoming a second kind of thing.
	var moons_seen: int = 0
	var moons_are_solid: bool = true
	var moons_have_no_well: bool = true
	var moons_are_smaller: bool = true
	for seed_value in [1, 2, 3, 17, 31, 900, 4242]:
		var b = BattleLib.create_duel(FitLib.create_default("kestrel"),
			"talon", seed_value, "orbit")
		var world: Dictionary = {}
		for f in b.terrain.features:
			if String(f.get("variant", "")) != "moon":
				world = f
		for f in b.terrain.features:
			if String(f.get("variant", "")) != "moon":
				continue
			moons_seen += 1
			if String(f["kind"]) != TerrainLib.KIND_PLANET:
				moons_are_solid = false
			if float(f["body"]) <= 0.0:
				moons_are_solid = false
			if float(f["field"]) != 0.0:
				moons_have_no_well = false
			if float(f["body"]) >= float(world["body"]):
				moons_are_smaller = false
			# The one that matters: standing on a moon must not tug, because a
			# moon carries no well at all.
			var just_outside: Vector2 = Vector2(f["pos"]) \
				+ Vector2(float(f["body"]) + 1.0, 0.0)
			var pull_here: Vector2 = b.terrain.pull_at(just_outside)
			var without_moon: Vector2 = (Vector2(world["pos"]) - just_outside)
			if pull_here.length() > 0.0 and not without_moon.is_zero_approx():
				# Any pull here has to point at the WORLD, never at the moon.
				if absf(pull_here.normalized().angle_to(without_moon.normalized())) > 0.001:
					moons_have_no_well = false
	ok(moons_seen > 0, "the orbit map places moons")
	ok(moons_are_solid, "a moon is a solid planet body like any other")
	ok(moons_have_no_well, "a moon has no gravity well and tugs nothing")
	ok(moons_are_smaller, "a moon is smaller than the world it belongs to")
	ok(opens_with_lock, "no map begins with the two sides unable to see each other")

	# Every feature a recipe can produce must have a scene that draws it. A
	# variant named in data/maps.json with no matching scene would place a world
	# the arena simply does not render, and nothing else would say so.
	var FieldLib = preload("res://src/ui/terrain_field.gd")
	var all_drawable: bool = true
	var variants_seen: Dictionary = {}
	for map_id in CatalogLib.map_ids():
		for seed_value in range(1, 60):
			var b = BattleLib.create_duel(FitLib.create_default("wayfarer"),
				"talon", seed_value, String(map_id))
			for f in b.terrain.features:
				variants_seen[String(f["kind"]) + "/" + String(f.get("variant", ""))] = true
				if FieldLib.scene_for(f) == null:
					all_drawable = false
	ok(all_drawable, "every feature a recipe can place has a scene that draws it")
	var every_world: bool = true
	for want in ["terran", "ice", "barren", "gas"]:
		if not variants_seen.has("planet/" + want):
			every_world = false
	ok(every_world, "and every kind of world turns up")

	# ---- nebulae: obscuration is a path length, not a flag ----
	var cloudy = TerrainLib.new()
	cloudy.features.append({ "kind": TerrainLib.KIND_NEBULA,
		"pos": Vector2.ZERO, "body": 0.0, "field": 100.0 })
	var opacity: float = float(CatalogLib.tuning()["terrain"]["nebula_opacity_length"])
	near(cloudy.obscuration(Vector2(-200, 0), Vector2(200, 0)), 200.0 / opacity,
		"a line straight through a cloud counts its whole chord")
	near(cloudy.obscuration(Vector2(200, 0), Vector2(-200, 0)), 200.0 / opacity,
		"obscuration is the same in both directions")
	eq(cloudy.obscuration(Vector2(-200, 200), Vector2(200, 200)), 0.0,
		"a line that misses the cloud is not obscured")
	# Sitting just inside the edge hides almost nothing, which is the point of
	# measuring the path rather than testing a flag.
	ok(cloudy.obscuration(Vector2(-95.0, 0), Vector2(-200, 0)) < 0.1,
		"one step inside the edge hides almost nothing")

	var penalty: float = float(CatalogLib.tuning()["terrain"]["nebula_range_penalty"])
	near(cloudy.apparent_range(Vector2(-120, 0), Vector2(120, 0), 240.0),
		240.0 + 200.0 / opacity * penalty, "cloud is added to the range the guns see")
	ok(cloudy.lock_broken(Vector2(-120, 0), Vector2(120, 0)),
		"a full crossing breaks the lock")
	ok(not cloudy.lock_broken(Vector2(-300, 0), Vector2(-250, 0)),
		"a clear line holds the lock")

	# Blinded means it cannot be shot at, through the same call the bracket uses.
	var blind = BattleLib.create_duel(FitLib.create_default("wayfarer"), "talon", 11)
	blind.terrain = cloudy
	for s in blind.ships:
		s.terrain = cloudy
	blind.player().pos = Vector2(-120, 0)
	blind.enemy().pos = Vector2(120, 0)
	for w in blind.player().weapons_rt:
		w["charge"] = 1.0
	ok(not blind.player().can_see(blind.enemy().pos), "a blinded ship cannot see")
	eq(String(blind.player().fire_check(0, blind.enemy().pos)["reason"]), "no lock",
		"the firing check refuses without a lock")
	eq(blind.try_fire(blind.player(), 0), false, "and no shot leaves the tube")

	# ---- planets: the well pulls, the surface hurts ----
	var world = TerrainLib.new()
	world.features.append({ "kind": TerrainLib.KIND_PLANET,
		"pos": Vector2(0, 120), "body": 40.0, "field": 180.0 })
	var tuning: Dictionary = CatalogLib.tuning()
	var drifter = ShipLib.create(FitLib.create_default("wayfarer"),
		RandomNumberGenerator.new())
	drifter.terrain = world
	drifter.pos = Vector2.ZERO
	drifter.heading = 180.0
	drifter.set_order(180.0, 0.0)
	for _i in range(60):
		drifter.step(1.0 / 10.0, tuning)
	ok(drifter.drift.y > 0.0, "a gravity well gives a ship drift toward the planet")
	ok(drifter.pos.y > 5.0, "and the ship slides toward it with its engines idle")
	near(drifter.heading, 180.0, "without turning the ship away from where it points", 0.5)
	eq(world.pull_at(Vector2(0, -200)), Vector2.ZERO, "outside the well there is no pull")

	# Leaving the well sheds the drift rather than keeping it forever.
	drifter.terrain = TerrainLib.new()
	for _i in range(200):
		drifter.step(1.0 / 10.0, tuning)
	near(drifter.drift.length(), 0.0, "drift decays once the well is behind you", 0.001)

	# ---- asteroids: the halo grinds, the rock collides ----
	var rocks = TerrainLib.new()
	rocks.features.append({ "kind": TerrainLib.KIND_ASTEROID,
		"pos": Vector2.ZERO, "body": 10.0, "field": 40.0 })
	var terrain_tuning: Dictionary = tuning["terrain"]
	var floor_factor: float = float(terrain_tuning["asteroid_grind_speed_floor"])
	var dps: float = float(terrain_tuning["asteroid_grind_dps"])
	eq(rocks.grind_at(Vector2(0, 50), 16.0), 0.0, "outside the halo there is no dust")
	near(rocks.grind_at(Vector2(0, 25.0), 0.0), dps * 0.5 * floor_factor,
		"the halo grinds harder the deeper you are in it")
	ok(rocks.grind_at(Vector2(0, 25.0), 24.0) > rocks.grind_at(Vector2(0, 25.0), 0.0),
		"and harder the faster you cross it")

	var grinding = BattleLib.create_duel(FitLib.create_default("wayfarer"), "talon", 21)
	grinding.terrain = rocks
	for s in grinding.ships:
		s.terrain = rocks
	var victim = grinding.player()
	victim.pos = Vector2(0, 25.0)
	victim.heading = 0.0
	victim.speed = 0.0
	for _i in range(300):
		victim.pos = Vector2(0, 25.0)
		grinding._step_terrain(1.0 / 10.0)
	ok(victim.shields[0] < victim.shield_max,
		"dust wears the facing the ship is pointing along")
	near(victim.shields[3], victim.shield_max, "and leaves the trailing facing alone")

	var crashing = BattleLib.create_duel(FitLib.create_default("wayfarer"), "talon", 22)
	crashing.terrain = rocks
	for s in crashing.ships:
		s.terrain = rocks
	var wreck = crashing.player()
	wreck.pos = Vector2(2.0, 0.0)
	wreck.speed = 16.0
	var before_shields: float = 0.0
	for v in wreck.shields:
		before_shields += v
	crashing._step_terrain(1.0 / 10.0)
	var after_shields: float = 0.0
	for v in wreck.shields:
		after_shields += v
	near(before_shields - after_shields,
		float(terrain_tuning["asteroid_collision_damage"]),
		"running into a rock costs a lump of shield")
	ok(wreck.speed < 4.0, "and most of the ship's way")
	crashing._step_terrain(1.0 / 10.0)
	var again: float = 0.0
	for v in wreck.shields:
		again += v
	near(again, after_shields, "the cooldown stops a rock hitting every tick")

	# A collision narrates itself, so the comm log can explain what happened.
	var narrated: bool = false
	wreck.collision_grace = 0.0
	for e in crashing._drain():
		pass
	crashing._step_terrain(1.0 / 10.0)
	for e in crashing._drain():
		if String(e["type"]) == "hazard":
			narrated = true
	ok(narrated, "a hazard emits an event the comm log can print")


## Tractor beams: the auction, and what a beam does to the two ships
## (docs/13 section 6). The contest is ours, not a citation; docs/09 section 6
## records that the free rulebook leaves tractors out on purpose.
##
## Ships are stepped directly rather than through Battle.step so the AI is not
## steering the prisoner in the middle of a test about towing.
func test_tractors() -> void:
	print("\n== tractor beams ==")
	var tuning: Dictionary = CatalogLib.tuning()
	var t: Dictionary = tuning["tractor"]

	var duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 12)
	var me = duel.player()
	var foe = duel.enemy()
	me.pos = Vector2.ZERO
	foe.pos = Vector2(0, 24.0)

	# ---- what stops a latch ----
	eq(String(TractorLib.latch_check(me, foe, tuning)["reason"]), "no power",
		"a tractor with nothing in its sink cannot latch")
	me.set_alloc_units("tractor", 6.0)
	eq(String(TractorLib.latch_check(me, foe, tuning)["reason"]), "ready",
		"with power in the sink it can")
	foe.pos = Vector2(0, float(t["range"]) + 8.0)
	eq(String(TractorLib.latch_check(me, foe, tuning)["reason"]), "range",
		"a tractor is short ranged and says so")
	foe.pos = Vector2(0, 24.0)
	for sys in me.systems:
		if String(sys["code"]) == TractorLib.BOX:
			sys["boxes"] = 0
	eq(String(TractorLib.latch_check(me, foe, tuning)["reason"]), "destroyed",
		"a shot out emitter cannot latch (Federation Commander 5A2c)")
	for sys in me.systems:
		if String(sys["code"]) == TractorLib.BOX:
			sys["boxes"] = int(sys["boxes_max"])

	# ---- latching goes through the one command path, so it is recorded ----
	duel.log = LogLib.create(me.fit, "bloodletter", duel.seed_value, 1.0 / 30.0)
	ok(duel.apply_command(0, "tractor_latch", [1]), "the latch order is accepted")
	eq(duel.log.commands.size(), 1, "and written down like any other order")
	ok(not duel.apply_command(0, "tractor_latch", [1]), "one emitter holds one ship")
	eq(duel.log.commands.size(), 1, "and a refused latch is not recorded")
	ok(duel.tractor_on(foe) != null, "the prisoner knows it is held")

	# ---- the auction ----
	var beam = duel.tractor_on(me)
	foe.set_alloc_units("tractor", 6.0)
	var ratio: float = TractorLib.tonnage(foe) / TractorLib.tonnage(me)
	near(beam.break_bid(), foe.alloc_units("tractor") * ratio,
		"the prisoner's shove is weighted by the tonnage ratio")
	# Weight for weight: the standoff is put on the neutral middle step so the
	# tonnage ratio is the only thing being compared. Off that step the plan's
	# own multiplier is in the grip, which is the point of the plan and would
	# make this a test of two things at once.
	beam.standoff = 0.5
	ok(beam.break_bid() > beam.hold_bid(tuning),
		"the heavier ship out-shoves an equal bid")

	# Losing the auction does not snap the beam at once: the holder has
	# break_seconds to raise the bid, and raising it resets the struggle.
	for _i in range(10):
		duel._step_tractors(1.0 / 10.0, tuning)
	ok(duel.tractors.size() == 1, "the beam survives a second of losing the auction")
	ok(beam.strain > 0.9, "but the strain is showing")
	me.set_alloc_units("tractor", 12.0)
	duel._step_tractors(1.0 / 10.0, tuning)
	near(beam.strain, 0.0, "outbidding the prisoner resets the struggle")

	# Sustained, the prisoner wins and the pair cannot be regrabbed at once.
	me.set_alloc_units("tractor", 3.0)
	var freed: bool = false
	for _i in range(int(float(t["break_seconds"]) * 10.0) + 3):
		duel._step_tractors(1.0 / 10.0, tuning)
		if duel.tractors.is_empty():
			freed = true
			break
	ok(freed, "sustained, the prisoner breaks free")
	me.set_alloc_units("tractor", 12.0)
	ok(not duel.apply_command(0, "tractor_latch", [1]),
		"and cannot be grabbed again while the emitter recovers")
	for _i in range(int(float(t["relatch_cooldown"]) * 10.0) + 2):
		duel._step_tractors(1.0 / 10.0, tuning)
	ok(duel.apply_command(0, "tractor_latch", [1]), "once the cooldown lapses it can")

	# ---- range and damage snap it ----
	foe.pos = Vector2(0, float(t["range"]) + 20.0)
	duel._step_tractors(1.0 / 10.0, tuning)
	ok(duel.tractors.is_empty(), "opening the range past the beam snaps it")
	foe.pos = Vector2(0, 24.0)
	for _i in range(int(float(t["relatch_cooldown"]) * 10.0) + 2):
		duel._step_tractors(1.0 / 10.0, tuning)
	ok(duel.apply_command(0, "tractor_latch", [1]), "and it can be re-established")
	for sys in me.systems:
		if String(sys["code"]) == TractorLib.BOX:
			sys["boxes"] = 0
	duel._step_tractors(1.0 / 10.0, tuning)
	ok(duel.tractors.is_empty(), "shooting the emitter out drops the beam")

	# ---- what a beam does to the two ships ----
	var tow_duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 13)
	var tug = tow_duel.player()
	var prize = tow_duel.enemy()
	tug.pos = Vector2.ZERO
	prize.pos = Vector2(0, 24.0)
	tug.heading = 0.0
	tug.speed = 20.0
	prize.heading = 0.0
	prize.speed = 0.0
	tug.set_alloc_units("tractor", 10.0)
	ok(tow_duel.apply_command(0, "tractor_latch", [1]), "a tow can be set up")
	var m_tug: float = TractorLib.tonnage(tug)
	var m_prize: float = TractorLib.tonnage(prize)
	var common: Vector2 = Vector2(0, 20.0) * m_tug / (m_tug + m_prize)
	# Parked exactly on her commanded station, so the momentum sharing is the
	# only term left in the tow and can be checked on its own. A prize off her
	# station also gets the work that drags her onto it, which the plan block
	# below tests separately.
	prize.pos = tow_duel.tractor_on(tug).station_point(tuning)
	tow_duel._step_tractors(1.0 / 10.0, tuning)
	near(prize.tow_target.y, common.y,
		"a held ship is asked for the pair's common momentum")
	near(tug.tow_target.y, common.y - 20.0, "and so is the holder, from the other side")

	var towed_from: float = prize.pos.y
	for _i in range(200):
		for s in tow_duel.ships:
			s.tow_target = Vector2.ZERO
		tow_duel._step_tractors(1.0 / 20.0, tuning)
		# The holder is kept under way. Without an order its speed bleeds off
		# to the throttle it was never given, and a tow behind a ship that has
		# coasted to a stop proves nothing about towing.
		tug.set_order(tug.heading, 1.0)
		prize.set_order(prize.heading, 0.0)
		for s in tow_duel.ships:
			s.step(1.0 / 20.0, tuning)
	ok(prize.pos.y > towed_from + 2.0,
		"and it is dragged along behind the ship holding it")
	near(tug.pos.distance_to(prize.pos),
		tow_duel.tractor_on(tug).standoff_range(tuning),
		"still riding the station the plan gave it", 4.0)
	# Attitude is deliberately untouched: taking a ship's arcs away takes the
	# game away, and 5D says the beam holds position, not heading.
	prize.set_order(90.0, 0.0)
	for _i in range(200):
		for s in tow_duel.ships:
			s.tow_target = Vector2.ZERO
		tow_duel._step_tractors(1.0 / 20.0, tuning)
		for s in tow_duel.ships:
			s.step(1.0 / 20.0, tuning)
	near(prize.heading, 90.0, "a held ship can still come about and shoot back", 1.0)
	ok(tow_duel.tractors.size() == 1, "and the beam is still on it while it turns")

	# Letting go stops the tow rather than leaving it stuck on.
	ok(tow_duel.apply_command(0, "tractor_release", []), "a holder may let go")
	for _i in range(200):
		for s in tow_duel.ships:
			s.tow_target = Vector2.ZERO
		tow_duel._step_tractors(1.0 / 20.0, tuning)
		for s in tow_duel.ships:
			s.step(1.0 / 20.0, tuning)
	near(prize.tow.length(), 0.0, "and the tow bleeds away once the beam is gone", 0.001)

	# ---- reeling in ----
	var reel_duel = BattleLib.create_duel(FitLib.create_default("ironhold"), "talon", 14)
	var winch = reel_duel.player()
	var catch = reel_duel.enemy()
	winch.pos = Vector2.ZERO
	catch.pos = Vector2(0, 32.0)
	winch.speed = 0.0
	catch.speed = 0.0
	winch.set_alloc_units("tractor", 10.0)
	ok(reel_duel.apply_command(0, "tractor_latch", [1]), "the winch takes hold")
	var reel_beam = reel_duel.tractor_on(winch)
	ok(reel_duel.apply_command(0, "tractor_plan", [reel_beam.bearing, 0.05]),
		"and can be told to pull the catch closer (5D)")
	var gap_before: float = winch.pos.distance_to(catch.pos)
	var winch_start: Vector2 = winch.pos
	var catch_start: Vector2 = catch.pos
	for _i in range(120):
		for s in reel_duel.ships:
			s.tow_target = Vector2.ZERO
		reel_duel._step_tractors(1.0 / 20.0, tuning)
		winch.set_order(winch.heading, 0.0)
		catch.set_order(catch.heading, 0.0)
		for s in reel_duel.ships:
			s.step(1.0 / 20.0, tuning)
	ok(winch.pos.distance_to(catch.pos) < gap_before - 4.0, "reeling closes the range")
	ok(catch_start.distance_to(catch.pos) > winch_start.distance_to(winch.pos) * 2.0,
		"and the light ship is the one that actually travels")

	# ---- the tow plan: a bearing off the nose and a standoff ----
	# The trade the plan exists for: reach far and hold weakly, or bring her in
	# and hold hard. Halfway out is exactly neutral, which is what makes the
	# default plan a reading a captain can measure the others against.
	var plan_duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "kestrel", 31)
	var hauler = plan_duel.player()
	var catch2 = plan_duel.enemy()
	hauler.pos = Vector2.ZERO
	hauler.heading = 0.0
	catch2.pos = Vector2(0.0, 60.0)
	hauler.set_alloc_units("tractor", 10.0)
	ok(plan_duel.apply_command(0, "tractor_latch", [1]), "the beam takes hold")
	var plan = plan_duel.tractor_on(hauler)
	near(plan.bearing, 0.0, "a fresh beam adopts the bearing it found her on")
	near(plan.standoff, TractorLib.frac_for_range(60.0, tuning),
		"and the fraction of range it found her at")

	plan.standoff = 0.5
	near(plan.grip_multiplier(tuning), 1.0,
		"halfway out is exactly neutral grip", 0.001)
	plan.standoff = 0.0
	var close_grip: float = plan.hold_bid(tuning)
	plan.standoff = 1.0
	var far_grip: float = plan.hold_bid(tuning)
	ok(close_grip > far_grip * 2.0,
		"holding her close grips far harder than holding her out")
	near(far_grip, TractorLib.bid_of(hauler) * float(t["grip_far"]),
		"and the far end is the tuned floor times the bid")
	ok(TractorLib.clamp_frac(0.0, tuning) > 0.0,
		"no order is a zero standoff")
	near(TractorLib.clamp_frac(9.0, tuning), 1.0,
		"and none reaches past the beam")
	# The floor is the hulls' own contact circle, not a share of range: the
	# closest the slider can be dragged would otherwise station her prize
	# inside a heavy ship's collision radius and grind it to scrap for free.
	plan.standoff = 0.0
	ok(plan.standoff_range(tuning) > hauler.contact_distance(catch2),
		"and the closest station clears both hulls")

	# The station is a point on the HOLDER: turning the hull swings the prize
	# around with it, which is what makes steering her into a rock piloting.
	plan.standoff = 0.5
	plan.bearing = 90.0
	var station: Vector2 = plan.station_point(tuning)
	near(station.x, plan.standoff_range(tuning),
		"bearing 090 stations her off the starboard beam", 0.01)
	near(station.y, 0.0, "and level with the bow", 0.01)
	hauler.heading = 180.0
	near(plan.station_point(tuning).x, -plan.standoff_range(tuning),
		"and the station swings with the holder's heading", 0.01)

	# The prize is worked toward her station, wherever the plan puts her.
	hauler.heading = 0.0
	plan.bearing = 0.0
	plan.standoff = 0.12
	var gap_start: float = hauler.pos.distance_to(catch2.pos)
	for _i in range(200):
		for s in plan_duel.ships:
			s.tow_target = Vector2.ZERO
		plan_duel._step_tractors(1.0 / 20.0, tuning)
		hauler.set_order(hauler.heading, 0.0)
		catch2.set_order(catch2.heading, 0.0)
		for s in plan_duel.ships:
			s.step(1.0 / 20.0, tuning)
	var gap_end: float = hauler.pos.distance_to(catch2.pos)
	ok(gap_end < gap_start, "a shorter standoff drags her in")
	near(gap_end, plan.standoff_range(tuning),
		"and she settles ON the commanded standoff rather than through it", 6.0)

	# ---- holding needs an emitter, breaking does not ----
	ok(not TractorLib.emitter_ready(catch), "the Talon carries no tractor")
	eq(String(TractorLib.latch_check(catch, winch, tuning)["reason"]), "destroyed",
		"so it cannot latch anything")
	catch.set_alloc_units("tractor", 4.0)
	var caught = reel_duel.tractor_on(catch)
	ok(caught.break_bid() > 0.0,
		"but it can still shove against a beam already on it")

	# ---- the opponent fights back ----
	# Without this the auction would be a button: the player would win every
	# contest unopposed. The ships are held still so the only thing that can
	# snap the beam is the contest itself, not the range opening.
	var AiLib = preload("res://src/sim/ai.gd")
	var contested = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 15)
	var grip = contested.player()
	var prisoner = contested.enemy()
	grip.pos = Vector2.ZERO
	prisoner.pos = Vector2(0, 24.0)
	grip.set_alloc_units("tractor", 8.0)
	eq(prisoner.alloc_units("tractor"), 0.0, "an untouched ai spends nothing on tractors")
	ok(contested.apply_command(0, "tractor_latch", [1]), "the ai can be caught")
	var broke: bool = false
	for _i in range(200):
		AiLib.act(prisoner, grip, contested)
		contested._step_tractors(1.0 / 20.0, tuning)
		if contested.tractors.is_empty():
			broke = true
			break
	ok(broke, "and shoves its way out rather than being towed forever")
	AiLib.act(prisoner, grip, contested)
	near(prisoner.alloc_units("tractor"), 0.0, "then stops paying once it is loose", 0.01)


func test_replay() -> void:
	print("\n== battle log and replay ==")
	var live = _scripted_battle(true)
	var log = live.log
	ok(log != null, "a battle can be recorded")
	# Only the orders that took effect are recorded, so this is fewer than the
	# script issued: a fire order with nothing bearing changed nothing.
	ok(log.commands.size() >= 5, "the orders that took effect are written down")
	ok(log.commands.size() <= 15, "and the ones that did nothing are not")
	eq(int(log.commands[0][0]), 0, "commands carry the tick they were given on")
	eq(String(log.commands[0][2]), "order", "and the kind")

	# The same run, twice, from the log alone.
	var replayed = log.replay()
	var live_print: Dictionary = LogLib.fingerprint(live)
	var replay_print: Dictionary = LogLib.fingerprint(replayed)
	eq(JSON.stringify(replay_print), JSON.stringify(live_print),
		"a replay reproduces the battle exactly, box for box")

	var again = log.replay()
	eq(JSON.stringify(LogLib.fingerprint(again)), JSON.stringify(live_print),
		"and does so every time")

	# A second live run with the same seed and script matches too, which is
	# what proves the determinism is in the simulation, not in the log.
	var twin = _scripted_battle(false)
	eq(JSON.stringify(LogLib.fingerprint(twin)), JSON.stringify(live_print),
		"the same seed and the same orders give the same battle")

	# A different seed must not, or the seed is being ignored somewhere.
	var other_fit = FitLib.create_default("wayfarer")
	var other = BattleLib.create_duel(other_fit, "bloodletter", 999)
	for i in range(420):
		if other.over:
			break
		other.step(1.0 / 30.0)
	ok(JSON.stringify(LogLib.fingerprint(other)) != JSON.stringify(live_print),
		"a different seed gives a different battle")

	# Round trip through JSON, which is what a file is.
	var text: String = JSON.stringify(log.to_dict())
	var parsed = LogLib.from_dict(JSON.parse_string(text))
	eq(parsed.seed_value, log.seed_value, "the seed survives the round trip")
	eq(parsed.commands.size(), log.commands.size(), "so do the commands")
	eq(JSON.stringify(LogLib.fingerprint(parsed.replay())), JSON.stringify(live_print),
		"and a log read back from text replays identically")

	# On disk, which is the point of the whole exercise.
	var path: String = "user://test_replay.json"
	ok(log.save(path), "a log writes to disk")
	var loaded = LogLib.load_from(path)
	ok(loaded != null, "and reads back")
	eq(int(loaded.end_tick), int(log.end_tick), "including how long it ran")
	eq(JSON.stringify(LogLib.fingerprint(loaded.replay())), JSON.stringify(live_print),
		"a saved replay reproduces the battle it recorded")
	eq(int(loaded.dt * 1000.0), int(log.dt * 1000.0), "the step size is part of the setup")
	eq(String(loaded.player_hull), "wayfarer", "the design is part of the setup")
	eq(String(loaded.enemy_hull), "bloodletter", "and so is the opponent")


	# Only valid commands are recorded: a refused order is not part of the
	# battle, and replaying it would diverge from what happened.
	var strict = BattleLib.create_duel(FitLib.create_default("wayfarer"), "talon", 8)
	strict.log = LogLib.create(strict.player().fit, "talon", 8, 1.0 / 30.0)
	ok(strict.apply_command(0, "order", [90.0, 1.0]), "a helm order is valid")
	eq(strict.log.commands.size(), 1, "and is recorded")
	strict.player().shields[0] = strict.player().shield_max
	ok(not strict.apply_command(0, "transfer_shield", [1, 0]),
		"a transfer into a full facing is refused")
	eq(strict.log.commands.size(), 1, "and is not recorded")
	ok(not strict.apply_command(0, "fire", [0]), "an uncharged weapon cannot fire")
	eq(strict.log.commands.size(), 1, "and that is not recorded either")
	ok(not strict.apply_command(9, "order", [0.0, 0.0]), "an unknown actor is refused")
	eq(strict.log.commands.size(), 1, "and nothing is written for it")

	# Replaying a log must never alter it.
	var before: int = log.commands.size()
	log.replay()
	eq(log.commands.size(), before, "replaying a log does not append to it")


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
	eq(boxes_before, 75, "wayfarer starts with 75 internal boxes")

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
	# The reported facing is checked alongside the shield it drained, because
	# the battle view lights a shield from that report rather than working the
	# facing out again, and the two must never disagree.
	var turned = _fresh_ship()
	turned.heading = 90.0
	var hit_fore: Dictionary = turned.apply_damage(90.0, 10.0)
	near(turned.shields[0], turned.shield_max - 10.0, "world 090 on heading 090 strikes the fore facing")
	eq(int(hit_fore["facing"]), 0, "and reports facing 1 as the one struck")
	near(float(hit_fore["absorbed"]), 10.0, "reporting what the shield absorbed")
	var flank = _fresh_ship()
	var hit_flank: Dictionary = flank.apply_damage(90.0, 10.0)
	near(flank.shields[2], flank.shield_max - 10.0, "world 090 on heading 000 strikes facing 3")
	eq(int(hit_flank["facing"]), 2, "and reports facing 3 as the one struck")

	# A hit on a facing whose shield is already gone still reports that facing,
	# so the view can flash a downed shield rather than going quiet.
	var stripped = _fresh_ship()
	stripped.shields[2] = 0.0
	var hit_down: Dictionary = stripped.apply_damage(90.0, 6.0)
	eq(int(hit_down["facing"]), 2, "a stripped facing still reports itself")
	near(float(hit_down["absorbed"]), 0.0, "with nothing absorbed")

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

	# Every distance below is read out of the catalog rather than written down.
	# When the arena grew ten times and weapon reach four, a suite full of
	# literal ranges failed in a dozen places and said nothing about whether the
	# falloff RULE still held, which is the only thing this test is about.
	var ph1_reach: float = WeaponLib.max_range(ph1)
	var ph1_band: float = float(ph1["falloff"][0]["to"])
	near(ph1_reach, float(ph1["falloff"][-1]["to"]),
		"reach is the outer edge of the last band")
	eq(WeaponLib.max_damage(ph1), int(ph1["falloff"][0]["damage"]),
		"point blank damage is the first band")

	# A band edge belongs to its own band: at exactly the edge the shot is still
	# point blank, at a hair beyond it is not. Off by one here would silently
	# change every weapon's profile.
	eq(WeaponLib.damage_at(ph1, ph1_band), int(ph1["falloff"][0]["damage"]),
		"the band edge is inside the band")
	eq(WeaponLib.damage_at(ph1, ph1_band + 0.001), int(ph1["falloff"][1]["damage"]),
		"just past the edge is the next band")
	eq(WeaponLib.damage_at(ph1, 0.0), int(ph1["falloff"][0]["damage"]),
		"muzzle contact is point blank")
	eq(WeaponLib.damage_at(ph1, ph1_reach), int(ph1["falloff"][-1]["damage"]),
		"the last band reaches the stated range")
	eq(WeaponLib.damage_at(ph1, ph1_reach * 1.05), 0, "beyond reach scores nothing")
	near(WeaponLib.hit_chance_at(ph1, ph1_reach * 1.05), 0.0,
		"beyond reach cannot connect")

	# The three shapes from docs/09: beams lose damage and keep accuracy,
	# torpedoes keep damage and lose accuracy, disruptors lose both.
	near(WeaponLib.hit_chance_at(ph1, ph1_reach * 0.9), 1.0,
		"a beam still connects at its edge")
	ok(WeaponLib.damage_at(ph1, ph1_reach * 0.9) < WeaponLib.max_damage(ph1),
		"a beam weakens with range")
	var photon_edge: float = WeaponLib.max_range(photon) * 0.95
	eq(WeaponLib.damage_at(photon, photon_edge), WeaponLib.max_damage(photon),
		"a torpedo hits as hard at the edge as at the muzzle")
	ok(WeaponLib.hit_chance_at(photon, photon_edge) < 1.0,
		"a torpedo loses accuracy instead")
	var disr_edge: float = WeaponLib.max_range(disr) * 0.9
	ok(WeaponLib.damage_at(disr, disr_edge) < WeaponLib.max_damage(disr)
		and WeaponLib.hit_chance_at(disr, disr_edge) < 1.0, "a disruptor loses both")

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
	var mid_band: float = ph1_reach * 0.5
	var mid_damage: int = WeaponLib.damage_at(ph1, mid_band)
	for i in range(200):
		if WeaponLib.roll_damage(ph1, mid_band, rng) != mid_damage:
			beam_rolls_low = true
	ok(not beam_rolls_low, "a certain beam always scores its band damage")

	var misses: int = 0
	var partials: int = 0
	var long_shot: float = WeaponLib.max_range(photon) * 0.9
	for i in range(400):
		var scored: int = WeaponLib.roll_damage(photon, long_shot, rng)
		if scored == 0:
			misses += 1
		elif scored != WeaponLib.max_damage(photon):
			partials += 1
	ok(misses > 0, "a long torpedo shot can miss")
	eq(partials, 0, "a torpedo that connects scores in full")
	near(float(misses) / 400.0, 1.0 - WeaponLib.hit_chance_at(photon, long_shot),
		"miss rate tracks the band's hit chance", 0.08)

	near(WeaponLib.longest_range(), WeaponLib.max_range(CatalogLib.weapon("lance")),
		"the arc chart scale comes from the catalog")

	# A shot resolved through a ship carries the same numbers.
	var shooter = _fresh_ship()
	var mark = _fresh_ship()
	mark.pos = shooter.pos + Vector2(0.0, 3.0)
	var fit: Variant = shooter.fit
	near(fit.expected_into(0, 0.0), float(fit.alpha_into(0)),
		"expected damage at point blank equals the projected alpha")
	# Past the first band edge of the shortest weapon covering that sector, so
	# at least one gun in the broadside has dropped a band. Derived rather than
	# written down: a literal 9 was inside the first band the moment reaches
	# moved out, and the check silently stopped meaning anything.
	ok(fit.expected_into(0, ph1_band * 1.5) < float(fit.alpha_into(0)),
		"the same broadside is worth less at range")


## Overload: reach traded for weight, paid for out of the battery and out of
## the shields (docs/01 sections 3 and 5.1). Every number below is read from
## the catalog, so retuning the disruptor retunes the test with it.
func test_overload() -> void:
	print("\n== overload ==")
	var tuning: Dictionary = CatalogLib.tuning()
	var combat: Dictionary = tuning["combat"]
	var disr: Dictionary = CatalogLib.weapon("disruptor")
	var ph1: Dictionary = CatalogLib.weapon("ph1")

	ok(WeaponLib.can_overload(disr), "the disruptor bank can overload")
	ok(not WeaponLib.can_overload(ph1), "the beam cannot")
	ok(not WeaponLib.can_overload({}), "and neither can an empty mount")

	var reach: float = WeaponLib.max_range(disr)
	var over_reach: float = WeaponLib.max_range(disr, true)
	var range_scale: float = float(disr["overload"]["range"])
	var damage_scale: float = float(disr["overload"]["damage"])
	near(over_reach, reach * range_scale, "an overload trades reach away")
	eq(WeaponLib.max_damage(disr, true),
		roundi(float(WeaponLib.max_damage(disr)) * damage_scale),
		"and buys weight with it")

	# The compressed range is the whole rule: an overloaded shot reads the band
	# it would need to be range_scale as close for, accuracy included.
	var half: float = over_reach * 0.5
	eq(WeaponLib.damage_at(disr, half, true),
		roundi(float(WeaponLib.damage_at(disr, half / range_scale)) * damage_scale),
		"an overloaded shot reads the band from its compressed range")
	near(WeaponLib.hit_chance_at(disr, half, true),
		WeaponLib.hit_chance_at(disr, half / range_scale),
		"and takes that band's accuracy with it")
	eq(WeaponLib.damage_at(disr, over_reach * 1.05, true), 0,
		"past the shortened reach it scores nothing")
	ok(WeaponLib.damage_at(disr, over_reach * 1.05) > 0,
		"where the same weapon unarmed still reaches")

	# The same monotonic guarantee test_falloff makes for every weapon, made
	# again for the armed profile: a compressed band table could invert it.
	var monotonic: bool = true
	var prev: float = WeaponLib.expected_damage_at(disr, 0.0, true)
	var d: float = 0.0
	while d <= over_reach:
		var cur: float = WeaponLib.expected_damage_at(disr, d, true)
		if cur > prev + 0.0001:
			monotonic = false
		prev = cur
		d += over_reach / 40.0
	ok(monotonic, "an overloaded disruptor never scores more at a longer range")

	# Arming is a property of what is fitted. The kestrel carries disruptors on
	# M1 and M2 and a light beam on M3.
	var ship = _fresh_ship("kestrel")
	ok(ship.can_overload(0), "a fitted disruptor can be armed")
	ok(not ship.can_overload(2), "a fitted beam cannot")
	ok(ship.set_overload(0, true), "arming reports the change")
	ok(not ship.set_overload(0, true), "arming again reports nothing, so nothing is logged")
	ok(ship.overloaded(0), "the mount is armed")
	ok(not ship.set_overload(2, true), "a beam refuses to arm")
	ok(ship.set_overload(0, false), "and it disarms")

	# The battery gate. Charged, in arc, in range, and still refused because the
	# reserve cannot pay for it.
	var target_pos: Vector2 = ship.pos + Vector2(0.0, 4.0)
	ship.set_order(0.0, 0.0)
	for i in range(200):
		ship.step(1.0 / 15.0, tuning)
	eq(String(ship.fire_check(0, target_pos)["reason"]), "bears",
		"an unarmed disruptor bears")
	ship.battery = 0.0
	ship.set_overload(0, true)
	eq(String(ship.fire_check(0, target_pos)["reason"]), "battery",
		"an armed mount with a flat battery says so")
	ship.battery = float(combat["overload_battery_cost"])
	eq(String(ship.fire_check(0, target_pos)["reason"]), "bears",
		"and bears once the reserve can pay")

	# Armed, the same mount cannot reach what it could reach unarmed.
	var far_pos: Vector2 = ship.pos + Vector2(0.0, over_reach * 1.1)
	eq(String(ship.fire_check(0, far_pos)["reason"]), "range",
		"an armed mount loses the far half of its envelope")
	ship.set_overload(0, false)
	eq(String(ship.fire_check(0, far_pos)["reason"]), "bears",
		"which it had unarmed")
	ship.set_overload(0, true)

	# The shot itself, at a range inside the compressed first band so the roll
	# cannot miss and the damage is exactly what the model projects.
	var foe = _fresh_ship("kestrel", 11)
	foe.pos = target_pos
	var shot: Dictionary = ship.fire_at(0, foe)
	ok(bool(shot["overload"]), "the shot is marked as an overload")
	eq(int(shot["damage"]), WeaponLib.damage_at(disr, 4.0, true),
		"and scores what the model projects for an armed shot")
	ok(int(shot["damage"]) > WeaponLib.damage_at(disr, 4.0),
		"which is more than the same mount unarmed")
	near(ship.battery, 0.0, "the reserve is spent")
	near(ship.shield_sag, float(combat["overload_shield_sag_sec"]),
		"the generators go off line for the stated seconds")
	ok(not ship.overloaded(0),
		"and the switch springs back, so one order is one shot")

	# The sag is the real cost: nothing is bought while it runs, and the energy
	# drawn in those seconds is not handed back afterwards.
	ship.shields[0] = 0.0
	var sag_ticks: int = int(float(combat["overload_shield_sag_sec"]) * 30.0) - 3
	for i in range(sag_ticks):
		ship.step(1.0 / 30.0, tuning)
	near(ship.shields[0], 0.0, "no shield box is bought while the generators sag")
	near(ship.shield_credit, 0.0, "and the energy drawn meanwhile is not banked")
	for i in range(1800):
		ship.step(1.0 / 30.0, tuning)
	ok(ship.shields[0] > 0.0, "once recovered they buy boxes again")

	# The same thing as an order, which is the path a battle and a replay take.
	# Two identical duels, nose to nose inside the compressed first band so the
	# roll cannot miss, one armed and one not.
	var scored: Array = []
	for armed in [false, true]:
		var duel = BattleLib.create_duel(FitLib.create_default("kestrel"), "talon", 77)
		duel.log = LogLib.create(duel.player().fit, "talon", 77, 1.0 / 30.0)
		var me = duel.player()
		me.pos = Vector2.ZERO
		me.heading = 0.0
		me.battery = float(combat["overload_battery_cost"])
		me.weapons_rt[0]["charge"] = 1.0
		duel.enemy().pos = Vector2(0.0, 4.0)
		if bool(armed):
			ok(duel.apply_command(0, "overload", [0, true]), "the arming order is accepted")
			eq(String(duel.log.commands[0][2]), "overload", "and written down for the replay")
		ok(duel.apply_command(0, "fire", [0]), "the mount fires on order")
		# The player's shot is appended before the step runs, so it is the
		# first one drained. Anything the opponent fires back comes after.
		var found: bool = false
		for e in duel.step(1.0 / 30.0):
			if found or String(e.get("type", "")) != "shot":
				continue
			found = true
			scored.append(int(e["damage"]))
			eq(bool(e["overload"]), bool(armed), "the event says whether it was overloaded")
	eq(scored.size(), 2, "both duels produced a shot")
	eq(int(scored[1]), roundi(float(scored[0]) * damage_scale),
		"and the armed one landed the heavier hit")

	# A weapon with no overload block is untouched by any of it: same reach,
	# same damage, armed or not, which is what keeps the flag from leaking into
	# the seven weapons that do not have one.
	near(WeaponLib.max_range(ph1, true), WeaponLib.max_range(ph1),
		"a weapon without an overload keeps its reach")
	eq(WeaponLib.damage_at(ph1, 4.0, true), WeaponLib.damage_at(ph1, 4.0),
		"and its damage")


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
	var past_reach: float = WeaponLib.longest_range() * 1.5
	eq(String(still.fire_check(0, still.pos + Vector2(0, past_reach))["reason"]), "range",
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
	# Well outside the AI's keep out distance, or it would break away rather
	# than present anything, which is the correct behaviour and not the one
	# this check is about.
	rot.player().pos = Vector2(0, 160)
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


func test_debris() -> void:
	print("\n== debris ==")
	var combat: Dictionary = CatalogLib.tuning()["combat"]
	var count: int = int(combat["debris_count"])
	var dt: float = 1.0 / 30.0

	# A kill spawns the wreckage. The hull is beaten down outside the step so
	# the step itself is what notices the death, exactly as a battle would.
	var duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 11)
	var victim = duel.enemy()
	# Well apart, so the survivor is not standing in the blast for the spawn
	# checks below.
	# Apart but inside the arena, which clamps positions each step: a spawn
	# point written outside it would be dragged to the rim and the checks
	# below would measure the clamp, not the debris.
	duel.player().pos = Vector2(-150.0, -150.0)
	victim.pos = Vector2(150.0, 150.0)
	while victim.alive:
		victim.apply_damage(0.0, 50.0)
	duel.step(dt)
	ok(duel.over, "the battle is decided when the hull comes apart")
	eq(duel.debris.size(), count, "and the dead ship sheds every piece of itself")
	ok(duel.debris_active(), "which the battle reports as still flying")

	var spawn: Array[Vector2] = []
	for piece in duel.debris:
		spawn.append(piece.pos)
		near(piece.pos.distance_to(Vector2(150.0, 150.0)), 0.0,
			"a piece starts where the ship died", 6.0)
	duel.step(dt)
	var moved: int = 0
	for i in range(duel.debris.size()):
		if duel.debris[i].pos.distance_to(spawn[i]) > 0.001:
			moved += 1
	eq(moved, count, "the verdict does not stop the wreckage: every piece flies on")

	# A piece is a hazard. Park the survivor on one and it is struck through
	# the same collision path ramming uses, and the piece is spent on the hit.
	var before: int = duel.debris.size()
	var target = duel.player()
	target.collision_grace = 0.0
	target.pos = duel.debris[0].pos
	var struck: int = 0
	for e in duel.step(dt):
		if String(e.get("hazard", "")) == "debris":
			struck += 1
	eq(struck, 1, "a chunk that reaches a hull strikes it")
	eq(duel.debris.size(), before - 1, "and shatters on it")
	ok(_hurt(target) > 0.0, "the survivor pays for standing in the wreck")

	# Time is the other way out.
	for piece in duel.debris:
		piece.age = piece.ttl - dt * 0.5
	duel.step(dt)
	eq(duel.debris.size(), 0, "a piece that outlives its clock is gone")
	ok(not duel.debris_active(), "and the battle knows the sky is clear")

	# The same seed throws the same wreck. Two battles, identical orders,
	# stepped identically: every piece lands in the same place, which is what
	# a replay showing the same debris field depends on.
	var one = _debris_run(17)
	var two = _debris_run(17)
	eq(one.size(), two.size(), "the same seed sheds the same count")
	var same: bool = true
	for i in range(one.size()):
		if one[i].distance_to(two[i]) > 0.0001:
			same = false
	ok(same, "and flies every piece down the same path")


## Kill the enemy, step a while, and report where the pieces got to.
func _debris_run(seed_value: int) -> Array[Vector2]:
	var duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", seed_value)
	duel.player().pos = Vector2(-150.0, -150.0)
	var victim = duel.enemy()
	victim.pos = Vector2(150.0, 150.0)
	while victim.alive:
		victim.apply_damage(0.0, 50.0)
	for i in range(40):
		duel.step(1.0 / 30.0)
	var out: Array[Vector2] = []
	for piece in duel.debris:
		out.append(piece.pos)
	return out


func test_boarding() -> void:
	print("\n== boarding ==")
	var combat: Dictionary = CatalogLib.tuning()["combat"]
	var limit: int = int(combat["hits_to_kill"])
	var dt: float = 1.0 / 30.0

	var duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", 21)
	var me = duel.player()
	var foe = duel.enemy()
	eq(me.marines.size(), 4, "a crew's marines are its MRNE boxes")
	eq(me.pad_cycles.size(), 3, "and its pads are its TRAN boxes")
	eq(foe.marines.size(), 5, "the enemy cruiser garrisons five")

	# Out of range, then in range but shielded, then legal: the check names
	# each refusal, the same contract every fire_check follows.
	me.pos = Vector2.ZERO
	me.heading = 0.0
	foe.pos = Vector2(0.0, 200.0)
	foe.heading = 0.0
	eq(String(BoardingLib.beam_check(me, foe, combat)["reason"]), "range",
		"too far to beam")
	foe.pos = Vector2(0.0, 30.0)
	var facing: int = SectorsLib.facing_of_relative_bearing(
		SectorsLib.relative_bearing(
			SectorsLib.bearing_between(foe.pos, me.pos), foe.heading))
	ok(foe.shields[facing] > 0.0, "the facing toward us starts shielded")
	eq(String(BoardingLib.beam_check(me, foe, combat)["reason"]), "shielded",
		"and a raised shield refuses the beam")
	foe.shields[facing] = 0.0
	eq(String(BoardingLib.beam_check(me, foe, combat)["reason"]), "ready",
		"a downed facing opens the door")

	# EACH PAD HAS ITS OWN CYCLE: sending two spends two pads and leaves the
	# third ready, so a third man can follow at once while the first two pads
	# recharge alone.
	ok(duel.apply_command(0, "beam", [2]), "two marines beam over")
	eq(me.away.size(), 2, "and stand on the enemy deck")
	eq(me.marines.size(), 2, "leaving two at home")
	eq(me.pads_ready().size(), 1, "two pads are cycling, one is not")
	ok(duel.apply_command(0, "beam", [2]), "the last ready pad still fires")
	eq(me.away.size(), 3, "sending the one marine it could")
	eq(me.pads_ready().size(), 0, "and now every pad is cycling")
	ok(not duel.apply_command(0, "beam", [1]), "with no pad ready the beam refuses")

	# The pads come back on their own clocks.
	for i in range(int(float(combat["pad_cycle_sec"]) * 30.0) + 2):
		me.step(dt, CatalogLib.tuning())
	eq(me.pads_ready().size(), 3, "every pad recharges on its own clock")

	# The deck fight: volleys on the interval until one side is done. The foe
	# is softened so the fight resolves inside the test's patience; what is
	# being proved is the loop, not the odds.
	for i in range(foe.marines.size()):
		foe.marines[i] = limit - 1
	var guard: int = 0
	while not duel.over and guard < 3000:
		duel.step(dt)
		guard += 1
	ok(duel.over, "the deck fight ends the battle")
	eq(duel.winner, 0, "the raiders' side takes the ship")
	eq(foe.captured_by, 0, "which the hull records")
	ok(ShipLib.count_alive(foe.marines, limit) == 0, "no defender left standing")

	# Same seed, same fight: the volley dice come from the battle's own rng.
	var first = _boarding_run(33)
	var second = _boarding_run(33)
	eq(str(first), str(second), "the same seed fights the same deck fight")

	# Recall: the away team comes home through the same pads, wounds and all,
	# even when nobody is left on the home deck to send.
	var back = BattleLib.create_duel(FitLib.create_default("kestrel"), "bloodletter", 9)
	var crew = back.player()
	var host = back.enemy()
	crew.pos = Vector2.ZERO
	host.pos = Vector2(0.0, 25.0)
	host.heading = 0.0
	var f2: int = SectorsLib.facing_of_relative_bearing(
		SectorsLib.relative_bearing(
			SectorsLib.bearing_between(host.pos, crew.pos), host.heading))
	host.shields[f2] = 0.0
	ok(back.apply_command(0, "beam", [2]), "the team goes over")
	for i in range(int(float(combat["pad_cycle_sec"]) * 30.0) + 2):
		crew.step(dt, CatalogLib.tuning())
	var aboard: int = crew.away.size()
	ok(back.apply_command(0, "recall", []), "and can be recalled")
	eq(crew.away.size(), 0, "the deck over there is empty again")
	eq(crew.marines.size(), 4, "and everyone is home")
	ok(aboard == 2, "both of them came back")


## Beam a team over and let the fight run a fixed number of steps, reporting
## every marine's wounds on both sides.
func _boarding_run(seed_value: int) -> Array:
	var combat: Dictionary = CatalogLib.tuning()["combat"]
	var duel = BattleLib.create_duel(FitLib.create_default("wayfarer"), "bloodletter", seed_value)
	var me = duel.player()
	var foe = duel.enemy()
	me.pos = Vector2.ZERO
	foe.pos = Vector2(0.0, 30.0)
	foe.heading = 0.0
	var facing: int = SectorsLib.facing_of_relative_bearing(
		SectorsLib.relative_bearing(
			SectorsLib.bearing_between(foe.pos, me.pos), foe.heading))
	foe.shields[facing] = 0.0
	duel.apply_command(0, "beam", [3])
	for i in range(600):
		duel.step(1.0 / 30.0)
		if duel.over:
			break
	return [me.marines.duplicate(), me.away.duplicate(),
		foe.marines.duplicate(), foe.away.duplicate(), duel.over, duel.winner]


## The fleet roster: what a session records when ships are won, refit, and
## flown. UI side state, but pure RefCounted arithmetic with no scene under
## it, so it is tested here beside the sim it counts boxes with.
func test_fleet() -> void:
	print("\n== fleet roster ==")
	var s = SessionLib.create()
	eq(s.fleet.size(), 1, "a new session sails with its flagship on the roster")
	eq(s.helm, 0, "and the helm is the flagship")
	var full: int = ShipLib.full_boxes("wayfarer")
	eq(int(s.fleet[0]["hull"]), full, "the flagship arrives whole")
	eq(int(s.fleet[0]["hull_max"]), full, "with hull_max the sim's own count")
	ok(not bool(s.fleet[0]["engines_out"]), "and her engines online")

	s.add_prize("bloodletter", 21, 39, false)
	eq(s.fleet.size(), 2, "a capture joins the roster")
	ok(bool(s.fleet[1]["prize"]), "marked as a prize")
	eq(int(s.fleet[1]["hull"]), 21, "carrying the damage she was taken with")

	s.take_helm(1)
	eq(s.helm, 1, "taking a helm moves the helm")
	eq(s.fit.hull_id, "bloodletter", "and the fit becomes that hull's")

	var custom = FitLib.create_default("bloodletter")
	s.fit = custom
	s.take_helm(1)
	ok(s.fit == custom, "re-taking the held helm keeps the dressed fit")
	s.take_helm(9)
	eq(s.helm, 1, "an index off the roster is refused")

	s.refit(FitLib.create_default("kestrel"))
	eq(String(s.fleet[1]["hull_id"]), "kestrel", "a refit replaces the helm row")
	eq(int(s.fleet[1]["hull"]), ShipLib.full_boxes("kestrel"),
		"and the new hull arrives whole")
	ok(not bool(s.fleet[1]["prize"]), "a refit hull is not a prize")

	s.add_prize("talon", 10, 40, true)
	ok(bool(s.fleet[2]["engines_out"]), "a dead drive is recorded at capture")
	s.add_prize("kestrel", 5, 34, false)
	s.add_prize("kestrel", 5, 34, false)
	eq(s.fleet.size(), 5, "a capture past the berth count is still recorded")
