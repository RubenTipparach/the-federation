class_name Seeker
extends RefCounted

## A weapon in flight: a drone chasing its target across the plane. Federation
## Commander distinguishes direct fire, which is resolved by a die roll the
## moment it is fired, from seeking weapons, which are shown on the map and
## move toward their target until they arrive or are killed (docs/09, 4F).
## That distinction is the whole point of this class: a seeker can be shot
## down, so light beams that would otherwise be too weak to matter earn their
## space as point defense.
##
## No Node dependencies. Battle owns the list and steps it (CLAUDE.md 5.2).

var pos: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var damage: int = 0
var hp: float = 0.0
var age: float = 0.0
var short: String = ""

## The ship that launched it, and the ship it is chasing. Held as references
## because a seeker outlives neither: if its target dies it is discarded.
var owner: ShipState = null
var target: ShipState = null


static func launch(from: ShipState, at: ShipState, weapon: Dictionary) -> Seeker:
	var s: Seeker = Seeker.new()
	s.owner = from
	s.target = at
	s.pos = from.pos
	s.speed = float(weapon["seeker_speed"])
	s.damage = WeaponModel.max_damage(weapon)
	s.hp = float(weapon["seeker_hp"])
	s.short = String(weapon["short"])
	s.heading = Sectors.bearing_between(s.pos, at.pos)
	return s


func alive() -> bool:
	return hp > 0.0 and target != null and target.alive


## Fly one tick toward wherever the target is now. A seeker turns instantly:
## it is small and fast, and the interesting decision is whether to shoot it
## down or outrun it, not whether it can corner.
func step(dt: float) -> void:
	heading = Sectors.bearing_between(pos, target.pos)
	pos += Vector2(sin(deg_to_rad(heading)), cos(deg_to_rad(heading))) * speed * dt
	age += dt


func distance_to_target() -> float:
	return pos.distance_to(target.pos)
