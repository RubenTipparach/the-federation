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


## Which navy's console the interface wears: the one that built the hull the
## player is flying. Nothing here decides it. A skin belongs to a faction in
## data/palette.json and a faction belongs to a hull in data/ships.json, so
## flying a captured Kthaari cruiser puts you behind a Kthaari console without
## a line of code knowing that is what happened.
func faction() -> String:
	return String(Catalog.hull(fit.hull_id)["faction"])


static func create() -> Session:
	var s: Session = Session.new()
	s.fit = ShipFit.create_default("wayfarer")
	return s
