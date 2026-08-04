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
## a dictionary { "hull_id", "name", "prize" (bool), "tow" (bool) }: prize
## marks a capture, tow marks a hull that cannot move itself (engines or
## reactor gone) and has to be dragged to a yard, docs/01 section 8's
## aftermath. The fleet screen that manages this is awaiting its mockup; the
## record exists now so a capture is never lost to the screen not existing.
const FLEET_MAX: int = 4
var fleet: Array[Dictionary] = []


## Which navy's console the interface wears: the one that built the hull the
## player is flying. Nothing here decides it. A skin belongs to a faction in
## data/palette.json and a faction belongs to a hull in data/ships.json, so
## flying a captured Kthaari cruiser puts you behind a Kthaari console without
## a line of code knowing that is what happened.
func faction() -> String:
	return String(Catalog.hull(fit.hull_id)["faction"])


## A captured hull joins the fleet. Past FLEET_MAX ships it is still recorded,
## flagged for towing regardless of its engines: a full fleet has no crew to
## sail it, so it is a prize on a rope either way.
func add_prize(hull_id: String, needs_tow: bool) -> void:
	var over_strength: bool = fleet.size() + 1 >= FLEET_MAX
	fleet.append({
		"hull_id": hull_id,
		"name": String(Catalog.hull(hull_id)["name"]),
		"prize": true,
		"tow": needs_tow or over_strength,
	})


## The helm moves to another hull in the fleet: the fit becomes that hull's
## default until the fitting screen dresses it properly.
func take_helm(hull_id: String) -> void:
	fit = ShipFit.create_default(hull_id)


static func create() -> Session:
	var s: Session = Session.new()
	s.fit = ShipFit.create_default("wayfarer")
	return s
