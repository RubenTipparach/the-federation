class_name Session
extends RefCounted

## Shared state between the screens, created and injected by main.gd so the
## screens depend on this small object rather than on each other
## (dependency inversion, CLAUDE.md 4.2).

var fit: ShipFit
var enemy_hull_id: String = "bloodletter"


static func create() -> Session:
	var s: Session = Session.new()
	s.fit = ShipFit.create_default("wayfarer")
	return s
