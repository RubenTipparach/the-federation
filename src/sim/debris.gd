class_name Debris
extends RefCounted

## One chunk of a ship that has come apart, still moving. Debris belongs to
## the SIMULATION, not to the view, for one reason: it deals collision damage,
## and anything that can change a ship's boxes has to live where the battle is
## decided (CLAUDE.md 5.2). The wreck on screen draws its plates wherever
## these pieces say they are, never the other way round.
##
## A piece flies out on the bearing it was thrown, slows under drag, and is
## gone when its clock runs out or when it strikes a hull, whichever comes
## first. It does not steer and it does not care who it hits: the ship that
## shed it is already dead, and every ship still alive is just plating in the
## way.
##
## No Node dependencies. Battle owns the list and steps it, exactly as it owns
## the seekers.

var pos: Vector2 = Vector2.ZERO
var vel: Vector2 = Vector2.ZERO
## The bearing this piece was thrown on, kept so the view can hand each piece
## to the hull fragment that sat on that side of the ship.
var bearing: float = 0.0
## How close a hull has to come to be struck, in sim units.
var radius: float = 0.0
var damage: float = 0.0
var age: float = 0.0
var ttl: float = 0.0
## Which ship shed this piece, as an index into Battle.ships. An index rather
## than a reference because the owner is dead and the view needs to know which
## wreck's plates these are.
var owner_index: int = -1


## Throw a dead ship's pieces. Bearings are spread evenly around the circle
## with the jitter smaller than the spacing, for the reason every scatter in
## this project records: independent draws leave gaps, and a ship that bursts
## with a bare quarter reads as a bug.
##
## `seed_value` must be derived from the battle's seed and tick, never from
## wall clock or a free running rng: a replay steps the same code and must
## throw the same pieces (CLAUDE.md 5.2).
static func burst(from: ShipState, index: int, combat: Dictionary,
		seed_value: int) -> Array[Debris]:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value
	var count: int = int(combat["debris_count"])
	var speed: float = from.radius() * float(combat["debris_speed_radii"])
	var out: Array[Debris] = []
	for i in range(count):
		var piece: Debris = Debris.new()
		var span: float = 360.0 / float(count)
		piece.bearing = span * float(i) + rng.randf_range(-span * 0.4, span * 0.4)
		piece.owner_index = index
		piece.pos = from.pos
		piece.vel = Vector2(sin(deg_to_rad(piece.bearing)),
			cos(deg_to_rad(piece.bearing))) * speed * rng.randf_range(0.7, 1.0)
		piece.radius = from.radius() * float(combat["debris_radius_frac"])
		piece.damage = float(combat["debris_damage"])
		piece.ttl = float(combat["debris_seconds"])
		out.append(piece)
	return out


## Coast one tick: out along the throw, slowing the whole way. pow rather
## than a flat multiply so the drag is the same per second whatever the tick
## rate, which determinism across machines depends on.
func step(dt: float, drag: float) -> void:
	pos += vel * dt
	vel *= pow(drag, dt)
	age += dt


func expired() -> bool:
	return age >= ttl
