class_name Session
extends RefCounted

## Shared state between the screens, created and injected by main.gd so the
## screens depend on this small object rather than on each other
## (dependency inversion, CLAUDE.md 4.2).

var fit: ShipFit
var enemy_hull_id: String = "bloodletter"

## Which map recipe the next skirmish is fought on, from data/maps.json. The
## picker that sets it is UI still awaiting a mockup (docs/13 section 8), so for
## now every battle starts in the empty arena.
var map_id: String = "open"

## THE FLEET: the hulls this command owns, the flagship first. Every entry is
## a dictionary { "hull_id", "name", "prize" (bool), "hull", "hull_max",
## "engines_out" (bool) }. hull and hull_max are internal boxes, the same
## number the sim fights with, so the roster and a battle cannot disagree
## about health. engines_out records a hull that cannot move itself (impulse
## or reactor gone at capture) and will need towing to a yard, docs/01
## section 8's aftermath; the tractor work that spends it is queued next.
## Past FLEET_MAX ships the roster still records a capture, because a prize
## must never be lost to a full berth list.
const FLEET_MAX: int = 4
var fleet: Array[Dictionary] = []
## Which fleet entry the player is flying. An index rather than a hull id,
## because two captured Kestrels are two ships.
var helm: int = 0


## Which navy's console the interface wears: the one that built the hull the
## player is flying. Nothing here decides it. A skin belongs to a faction in
## data/palette.json and a faction belongs to a hull in data/ships.json, so
## flying a captured Kthaari cruiser puts you behind a Kthaari console without
## a line of code knowing that is what happened.
func faction() -> String:
	return String(Catalog.hull(fit.hull_id)["faction"])


static func _entry(hull_id: String, prize: bool, hull: int, hull_max: int,
		engines_out: bool) -> Dictionary:
	return {
		"hull_id": hull_id,
		"name": String(Catalog.hull(hull_id)["name"]),
		"prize": prize,
		"hull": hull,
		"hull_max": hull_max,
		"engines_out": engines_out,
	}


## A captured hull joins the fleet, carrying the damage it was taken with.
func add_prize(hull_id: String, hull: int, hull_max: int,
		engines_out: bool) -> void:
	fleet.append(_entry(hull_id, true, hull, hull_max, engines_out))


## The helm moves to another ship in the fleet: the fit becomes that hull's
## default until the fitting screen dresses it properly.
func take_helm(index: int) -> void:
	# The guard on the current helm matters: re-picking the bridge already
	# stood on must not quietly replace a dressed fit with the default one.
	if index < 0 or index >= fleet.size() or index == helm:
		return
	helm = index
	fit = ShipFit.create_default(String(fleet[index]["hull_id"]))


## The shipyard or the design list replaced the fit. The helm row follows,
## arriving whole: a redesign is a fresh hull off the slip, not a repair of
## the one it replaces.
func refit(p_fit: ShipFit) -> void:
	fit = p_fit
	var full: int = ShipState.full_boxes(fit.hull_id)
	fleet[helm] = _entry(fit.hull_id, false, full, full, false)


static func create() -> Session:
	var s: Session = Session.new()
	s.fit = ShipFit.create_default("wayfarer")
	var full: int = ShipState.full_boxes("wayfarer")
	s.fleet.append(_entry("wayfarer", false, full, full, false))
	return s
