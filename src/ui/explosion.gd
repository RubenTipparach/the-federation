extends Node3D

## A detonation: the two seconds between a ship being intact and a ship being
## debris.
##
## Presentation only (CLAUDE.md 5.2). The simulation has already decided what
## blew up; nothing here can change a battle, and a battle plays out identically
## whether or not any of it is drawn.
##
## Placement and tint only (CLAUDE.md 5.1). Every mesh is a committed .obj
## authored into scenes/explosion.tscn and every colour is a committed .tres
## naming its entry in data/palette.json. This script gives each piece a
## direction and a speed, then moves, scales and fades what the scene declares.
##
## FIVE LAYERS, because one is not an explosion:
##
##   Flash   the first instant. A cream star, born already wider than the hull
##           and gone in a fifth of a second, which is what makes the eye
##           arrive at the right place.
##   Core    the white hot middle of that flash, a disc inside the rays.
##   Shock   a ring racing out ahead of everything and gone before the fire is,
##           so the blast reads as having a front.
##   Ball    the fireball itself, the sphere the wreck used to own, expanding
##           and cooling from gold through red.
##   Fire    two dozen billows thrown outward and swelling as they go: hot in
##           the middle, red at the edges. This is the part that lasts.
##   Embers  twenty small fast sparks thrown much further, still lit after the
##           fire is out, which is what gives the explosion a tail.
##
## EVERYTHING IS A FUNCTION OF AGE, never an integration. A piece's position is
## its direction times a curve of its age, so seeking an explosion to any moment
## is one call and it lands in exactly the state it would have reached by
## playing. A replay scrub will need that, and it is also what let the renders
## this was tuned against be taken at chosen instants rather than at whatever
## moment a frame happened to land on.
##
## The scatter comes from a RandomNumberGenerator the caller seeds, never from
## randf(): a replay must show the same explosion as the battle that recorded
## it, and drawing must not be able to change what the simulation rolls next.

## THE SHAPE OF EACH CURVE, as exponents. What is in data/tuning.json is every
## size and every duration, because those are what a designer retunes and a
## bigger hull scales them; what is here is how a piece gets from one end of its
## own life to the other, which is the same for every explosion this will ever
## draw. This is the same split ordnance.gd makes for the torpedo star: numbers
## that describe how a file draws, kept in the file that draws them.
##
## An exponent above 1 on a rising quantity means it starts slow, and on
## (1 - k) it means it holds and then falls away. Everything here is one of
## those two: fast out and slowing for anything thrown, hold and drop for
## anything burning.
const THROW_EASE: float = 2.6
const EMBER_THROW_EASE: float = 2.0
const SHOCK_EASE: float = 2.2
const SHOCK_DECAY: float = 2.0
## Deliberately gentle. At 1.5 the fire was gone by the time the debris had
## cleared and the last second was a smooth brown sphere with nothing in it; a
## slower decay leaves enough billows alight to keep the tail lumpy.
const FIRE_DECAY: float = 1.1
const EMBER_DECAY: float = 1.1
## How many times its own life a piece takes to reach full brightness. High,
## because fire lights at once and then burns down: this is an attack of a few
## hundredths of a second against a decay of a second and a half.
const FIRE_ATTACK: float = 8.0
const EMBER_ATTACK: float = 20.0

## Seconds of battle time. Read once at burst() and kept, because the tuning
## file is the authority on how long fire burns (CLAUDE.md 5.4) and nothing
## here should be inventing a number.
var _life: float = 1.0
var _age: float = 0.0
var _radius: float = 1.0
var _running: bool = false

## Per piece, in the order the scene declares them.
var _fire_dir: Array[Vector3] = []
var _fire_reach: Array[float] = []
var _fire_size: Array[float] = []
## When each billow lights, and how long it burns. Both vary per piece, which
## is what keeps two dozen discs from pulsing in step.
var _fire_born: Array[float] = []
var _fire_life: Array[float] = []
var _ember_dir: Array[Vector3] = []
var _ember_reach: Array[float] = []

## The alpha each piece's authored material was written with. The material is
## duplicated per piece so the fade belongs to this explosion, and the authored
## value is remembered so a fade is always computed from the palette rather
## than from whatever the last frame left behind.
var _fire_alpha: Array[float] = []
var _ember_alpha: Array[float] = []
var _flash_alpha: float = 1.0
var _core_alpha: float = 1.0
var _shock_alpha: float = 1.0


func _ready() -> void:
	_own($Flash)
	_own($Core)
	_own($Shock)
	_own($Ball)
	_flash_alpha = _alpha_of($Flash)
	_core_alpha = _alpha_of($Core)
	_shock_alpha = _alpha_of($Shock)
	for piece in $Fire.get_children():
		_own(piece)
		_fire_alpha.append(_alpha_of(piece))
	for piece in $Embers.get_children():
		_own(piece)
		_ember_alpha.append(_alpha_of(piece))
	_hide_all()


## Set a detonation going.
##
## `radius` is how big the thing that blew up was, in sim units. Every size
## below is a multiple of it, so a battlecruiser makes a bigger explosion than
## a frigate without a second table of numbers, exactly as the wreck's plates
## already work.
##
## `seed_value` is the caller's, so the same battle always draws the same
## explosion.
func burst(radius: float, seed_value: int) -> void:
	var fx: Dictionary = Catalog.tuning()["explosion"]
	_radius = maxf(radius, 0.01)
	_life = float(fx["seconds"])
	_age = 0.0
	_running = true

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = seed_value

	# Billows are thrown on the plane with only a little lift, because the
	# ships fly on a plane and a fireball that fountained upward would read as
	# a different game (docs/01). The same reasoning the wreck's plates use.
	var rise: float = float(fx["fire_rise"])
	var fire: Node3D = $Fire
	var count: int = fire.get_child_count()
	_fire_dir = []
	_fire_reach = []
	_fire_size = []
	_fire_born = []
	_fire_life = []
	for i in range(count):
		# Spread around the circle rather than drawn at random, with the jitter
		# smaller than the spacing. Independent draws leave gaps and clumps
		# often enough to be noticed, and a gap in a fireball reads as a bug
		# rather than as chance.
		var span: float = TAU / float(count)
		var bearing: float = span * float(i) + rng.randf_range(-span * 0.4, span * 0.4)
		_fire_dir.append(Vector3(sin(bearing), rng.randf_range(-rise, rise),
			cos(bearing)).normalized())
		# The scene paints a low index hot and a high one red, so the throw has
		# to grow with the index for the cloud to be hot in the middle.
		var tier: float = float(i) / float(maxi(count - 1, 1))
		_fire_reach.append(_radius * float(fx["fire_throw_radii"])
			* lerpf(float(fx["fire_throw_near"]), 1.0, tier)
			* rng.randf_range(0.7, 1.25))
		# A billow thrown further is drawn BIGGER, which is both what expanding
		# gas does and what closes the gap the throw opens. Sized at random
		# instead, the far ones came out small and hung in the dark as separate
		# brown circles with nothing joining them to the fire.
		_fire_size.append(_radius * lerpf(float(fx["fire_size_min_radii"]),
			float(fx["fire_size_max_radii"]), tier) * rng.randf_range(0.8, 1.25))
		# EACH BILLOW HAS ITS OWN CLOCK, and this is the single change that
		# stopped the fire reading as a heap of circles. Lit together and put
		# out together, two dozen discs pulse as one shape and the eye finds
		# every edge in it. Started at staggered moments and given lives of
		# different lengths, the same two dozen are always at different
		# brightnesses, and what the eye finds instead is churn.
		_fire_born.append(rng.randf_range(0.0, float(fx["fire_stagger"])))
		_fire_life.append(float(fx["fire_seconds"]) * rng.randf_range(
			float(fx["fire_life_min"]), 1.0))

	var embers: Node3D = $Embers
	_ember_dir = []
	_ember_reach = []
	for i in range(embers.get_child_count()):
		var span2: float = TAU / float(embers.get_child_count())
		var bearing2: float = span2 * float(i) + rng.randf_range(-span2 * 0.4, span2 * 0.4)
		_ember_dir.append(Vector3(sin(bearing2),
			rng.randf_range(-float(fx["ember_rise"]), float(fx["ember_rise"])),
			cos(bearing2)).normalized())
		_ember_reach.append(_radius * float(fx["ember_throw_radii"])
			* rng.randf_range(0.5, 1.0))

	seek(0.0)


## Where the explosion has got to, from 0 at the detonation to 1 when it is out.
func progress() -> float:
	return clampf(_age / _life, 0.0, 1.0) if _life > 0.0 else 1.0


func burning() -> bool:
	return _running


## Advance by the caller's clock. The explosion does not choose which clock that
## is, deliberately: the wreck steps on frame time because a hull coming apart
## is an afterimage of a result the simulation has already recorded, while
## anything that has to agree with a paused battle should hand this sim time
## instead. combat_world.update_visuals is where the two numbers are separated.
func step(delta: float) -> void:
	if not _running:
		return
	_age += delta
	seek(_age)


## Put the explosion into the state it reaches at `age` seconds, whatever state
## it was in before. Every layer below is a closed form of the age, which is
## what makes this possible and what a replay scrub will need.
func seek(age: float) -> void:
	var fx: Dictionary = Catalog.tuning()["explosion"]
	_age = age
	var t: float = progress()
	if t >= 1.0:
		_running = false
		_hide_all()
		return

	_step_flash(fx, age)
	_step_shock(fx, age)
	_step_ball(fx, age)
	_step_fire(fx, age)
	_step_embers(fx, age)


## The first instant: rays and a core, both blooming out of nothing and gone
## before the fire has finished being thrown. Two layers rather than one so the
## middle can saturate while the rays are still readable as rays.
func _step_flash(fx: Dictionary, age: float) -> void:
	var span: float = float(fx["flash_seconds"])
	var k: float = clampf(age / span, 0.0, 1.0)
	var lit: bool = k < 1.0
	$Flash.visible = lit
	$Core.visible = lit
	if not lit:
		return
	# Out fast and slowing, which is what a shock lit gas front does.
	var grow: float = sqrt(k)
	# HOLDS AT FULL, then falls. An alpha that starts dropping at once never
	# gets near white: the palette's brightest entry added at half strength
	# over black is grey, and the first version of this drew a grey doughnut on
	# top of the ship instead of a flash. A flash is saturated for as long as it
	# lasts and then it is over.
	var fade: float = clampf((1.0 - k) / float(fx["flash_hold"]), 0.0, 1.0)
	_size($Flash, _radius * lerpf(float(fx["flash_start_radii"]),
		float(fx["flash_end_radii"]), grow))
	_size($Core, _radius * lerpf(float(fx["core_start_radii"]),
		float(fx["core_end_radii"]), grow))
	# The rays turn a little as they go, so the flash is not a decal that
	# happens to be growing.
	_set_alpha($Flash, _flash_alpha * fade)
	_set_alpha($Core, _core_alpha * fade)
	($Flash.material_override as ShaderMaterial).set_shader_parameter(
		"spin", age * float(fx["flash_spin"]))


## The front, out ahead of the fire and gone before it.
func _step_shock(fx: Dictionary, age: float) -> void:
	var span: float = float(fx["shock_seconds"])
	var k: float = clampf(age / span, 0.0, 1.0)
	$Shock.visible = k < 1.0
	if k >= 1.0:
		return
	# Decelerating hard: a front is quickest the instant it leaves.
	var grow: float = 1.0 - pow(1.0 - k, SHOCK_EASE)
	_size($Shock, _radius * lerpf(float(fx["shock_start_radii"]),
		float(fx["shock_end_radii"]), grow))
	# Held bright while it is small and thinned as it stretches, which is what
	# a front spreading its energy over a longer circumference does.
	_set_alpha($Shock, _shock_alpha * pow(1.0 - k, SHOCK_DECAY))


## The fireball the wreck used to own: one sphere, expanding, its own shader
## carrying it from white hot through the palette's alert orange to nothing.
##
## On its own clock, and a shorter one than the fire it sits behind. It is a
## smooth sphere, so for as long as it is lit it flattens whatever it covers;
## run to the full two seconds it outlived the billows and the last half second
## of an explosion was a featureless brown ball. Out before them, what is left
## at the end is fire and sparks, which is the right thing for the end to be.
func _step_ball(fx: Dictionary, age: float) -> void:
	var k: float = clampf(age / float(fx["ball_seconds"]), 0.0, 1.0)
	$Ball.visible = k < 1.0
	if k >= 1.0:
		return
	$Ball.scale = Vector3.ONE * _radius * lerpf(float(fx["ball_start_radii"]),
		float(fx["ball_end_radii"]), sqrt(k))
	var mat: ShaderMaterial = $Ball.material_override
	if mat != null:
		# The blast shader owns the colour and the envelope; it wants 0 at the
		# detonation and 1 when the ball is out.
		mat.set_shader_parameter("progress", k)


## The part that lasts: billows thrown outward, swelling as they go and cooling
## as they swell. Each on its own clock, so the cloud churns rather than
## breathing in one piece.
func _step_fire(fx: Dictionary, age: float) -> void:
	var fire: Node3D = $Fire
	for i in range(mini(fire.get_child_count(), _fire_dir.size())):
		var piece: MeshInstance3D = fire.get_child(i)
		var k: float = (age - _fire_born[i]) / _fire_life[i]
		if k < 0.0 or k >= 1.0:
			piece.visible = false
			continue
		piece.visible = true
		# Thrown hard and slowed by nothing but the curve: most of the distance
		# is covered in the first third, which is what separates an explosion
		# from a balloon inflating. A billow that lit late still starts at the
		# middle, so late fire keeps coming out of the wreck rather than
		# appearing already spread.
		var out: float = 1.0 - pow(1.0 - k, THROW_EASE)
		# Swells from a fraction of its size to all of it, so the cloud thickens
		# as it spreads instead of thinning into separate dots.
		var swell: float = lerpf(float(fx["fire_swell_from"]), 1.0, sqrt(k))
		# Lights at once, then burns down over the rest of its life.
		var fade: float = minf(1.0, k * FIRE_ATTACK) * pow(1.0 - k, FIRE_DECAY)
		piece.position = _fire_dir[i] * _fire_reach[i] * out
		_size(piece, _fire_size[i] * swell)
		_set_alpha(piece, _fire_alpha[i] * fade)


## Sparks. Thrown much further than the fire and much smaller, and still lit
## when it is out.
func _step_embers(fx: Dictionary, age: float) -> void:
	var span: float = float(fx["ember_seconds"])
	var k: float = clampf(age / span, 0.0, 1.0)
	var embers: Node3D = $Embers
	if k >= 1.0:
		for piece in embers.get_children():
			piece.visible = false
		return
	var out: float = 1.0 - pow(1.0 - k, EMBER_THROW_EASE)
	var fade: float = minf(1.0, k * EMBER_ATTACK) * pow(1.0 - k, EMBER_DECAY)
	var size: float = _radius * float(fx["ember_size_radii"])
	for i in range(mini(embers.get_child_count(), _ember_dir.size())):
		var piece: MeshInstance3D = embers.get_child(i)
		piece.visible = true
		piece.position = _ember_dir[i] * _ember_reach[i] * out
		# Embers burn down rather than swelling: the opposite of a billow.
		_size(piece, size * lerpf(1.0, float(fx["ember_burn_down"]), k))
		_set_alpha(piece, _ember_alpha[i] * fade)


## Give a piece its own copy of the material the scene put on it, so two
## explosions burning at once do not share one fade. The shield glow documents
## the same bug from the other direction.
func _own(piece: MeshInstance3D) -> void:
	if piece.material_override != null:
		piece.material_override = piece.material_override.duplicate()


func _alpha_of(piece: MeshInstance3D) -> float:
	var mat: ShaderMaterial = piece.material_override
	if mat == null:
		return 1.0
	return (mat.get_shader_parameter("tint") as Color).a


func _set_alpha(piece: MeshInstance3D, alpha: float) -> void:
	var mat: ShaderMaterial = piece.material_override
	if mat == null:
		return
	var tint: Color = mat.get_shader_parameter("tint")
	mat.set_shader_parameter("tint", Color(tint.r, tint.g, tint.b, alpha))


## Billboards are square in their own coordinates, so a size is one number.
func _size(piece: MeshInstance3D, size: float) -> void:
	piece.scale = Vector3(size, size, size)


func _hide_all() -> void:
	$Flash.visible = false
	$Core.visible = false
	$Shock.visible = false
	$Ball.visible = false
	for piece in $Fire.get_children():
		piece.visible = false
	for piece in $Embers.get_children():
		piece.visible = false
