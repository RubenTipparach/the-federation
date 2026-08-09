// The shader every world in the tactical view is drawn with.
//
// The sphere tracing half of this is Simple Spatial Planet by Nolkaloid
// (https://godotshaders.com/shader/simple-spatial-planet/, CC0). The surface
// half is ours. The unmodified original is committed beside it as
// simple_spatial_planet.gdshader, and docs/14 records what came from where.
//
// WHAT IS THE AUTHOR'S: the ray sphere intersection, the depth write, the
// fresnel rim, and the whorley band function. It ignores the mesh it is drawn
// on and traces a sphere in the fragment stage, which is why the limb is a true
// circle at any zoom, why the surface compresses correctly toward the edge, and
// why the mesh needs no texture coordinates. That last one matters here:
// assets/meshes/sphere.obj has none.
//
// WHAT IS OURS, and why:
//
//   1. AN OPENGL DEPTH WRITE. The original writes `DEPTH = clipPos.z/clipPos.w`,
//      which is Vulkan's 0 to 1 convention. This project runs gl_compatibility,
//      where clip depth is -1 to 1, so every fragment was rejected and a planet
//      rendered as nothing at all.
//
//   2. A GROUND HEIGHT FIELD, which is the important one. The author's whorley
//      function is a flow field: it makes horizontal belts, so every world it
//      draws is a gas giant whatever colours it is given. Ours is a fractal
//      gradient noise evaluated in the world's local space with a domain warp,
//      which makes CONTINENTS. `bands` mixes between the two, so a gas giant
//      asks for the author's function and a rocky world asks for ours.
//
//   3. A SEA, WITH A COASTLINE. Height below `seaLevel` is water and above it is
//      ground, and the boundary is sharp rather than a gradient, because a
//      shoreline is the single feature that tells a player a world has oceans.
//
//   4. POLAR CAPS. Ice is a function of latitude rather than of height, with the
//      ground noise roughening its edge so it is not a drawn-on circle.
//
//   5. A LAVA GLOW. Where `glowColor` is not black, the lowest ground emits, so
//      a volcanic world lights its own fissures on the night side.
//
//   6. RELIEF. The height field is differentiated on the fly and the result
//      bends the sphere normal, which is a normal map generated from a height
//      map with no map in the middle: there is no texture to bake, because the
//      height IS a function and its slope can simply be measured. Only ground
//      above the waterline is bent, so a sea stays flat and catches the sun.
//
//   7. A SPECULAR SURFACE. Water is smooth, ground is rough, ice is in between,
//      and each world says which. That is what makes an ocean read as an ocean
//      rather than as blue ground: it is the only part of a world that throws a
//      highlight back at the star.
//
// Every colour named below comes from data/palette.json through
// src/ui/planet_body.gd, and every number from data/tuning.json. Nothing here
// is written in the shader.

shader_type spatial;
render_mode cull_front;

// ---- the author's sphere ----------------------------------------------------

bool solveQuadratic( float a, float b, float c, inout float x0, inout float x1 )
{ //https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-sphere-intersection.html
	float discr = b * b - 4.0 * a * c;

	if( discr < 0.0 ) return false;
	else if( abs(discr) < 0.0001 ) x0 = x1 = -0.5 * b / a;
	else
	{
		float q = (abs(b) > 0.0001) ? -0.5 * (b + sqrt(discr)) : -0.5 * (b - sqrt(discr));
		x0 = q / a;
		x1 = c / q;
	}
	if( x0 > x1 )
	{
		float _x1 = x1;
		x1 = x0;
		x0 = _x1;
	}
	return true;
}

float raySphereIntersect( vec3 origin, vec3 normal, vec3 center, float radius )
{ //https://www.scratchapixel.com/lessons/3d-basic-rendering/minimal-ray-tracer-rendering-simple-shapes/ray-sphere-intersection.html
	float t0, t1; // Solution for t if the ray intersects the sphere
	vec3 L = origin - center;
	float a = dot(normal,normal);
	float b = 2.0 * dot(normal,L);
	float c = dot(L,L) - radius * radius;
	if( !solveQuadratic(a, b, c, t0, t1 ) ) return -1.0;
	if( t0 < 0.0 )
	{
		if( t1 < 0.0 ) return -1.0;
		t0 = t1;
	}
	return t0;
}

vec3 whorley( vec2 uv, float time, vec2 distortion )
{ // https://www.shadertoy.com/view/XsVBWG
	for(float i=1.0; i<10.0; i+=1.0)
	{
		uv.x+=distortion.x*sin(i*uv.y+time);
		uv.y+=distortion.y*cos(i*uv.x+time*.2);
	}
	vec3 n = vec3( cos(uv.x+uv.y+2.),
		sin(uv.x+uv.y+2.2),
		(sin(uv.x+uv.y+1.)+cos(uv.x+uv.y+1.5)) );
	return n;
}

vec2 uvOnSphere( vec3 dir )
{
	float uvX = (atan( dir.y, length( vec2(dir.x,dir.z) ) )/PI)+0.5;
	float uvY = ((atan(dir.x,dir.z)+PI)/TAU);
	return vec2 ( uvX, uvY );
}

vec3 whorleyOnSphere( vec3 dir, float time, vec2 scale, vec2 distortion )
{
	float delta = (dot( -normalize(dir*vec3(1,0,1)), vec3(0,0,1) )+1.0)/2.0;
	vec3 wosA = whorley(uvOnSphere(dir)*scale, time, distortion );
	vec3 wosB = whorley(uvOnSphere(-dir)*scale, time, distortion );
	vec3 mixed = wosA+((wosB-wosA)*delta);
	return normalize(mixed);
}

vec3 transform( mat4 mtx, vec3 vec ){	return (mtx*vec4(vec,1.0)).rgb - mtx[3].rgb;}

float fresnel( float val, vec3 normal, vec3 view, float str ){ return clamp( mix( val, 0.0, dot(normal,view)*str ), 0.0, 1.0 );}

// ---- our ground -------------------------------------------------------------

// The usual fract-multiply hash. No sine, because the sine version bands
// visibly on some drivers and this runs over most of the screen.
vec3 hash33( vec3 p )
{
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx) * 2.0 - 1.0;
}

// Gradient noise, which is what gives blobs rather than the streaks a flow
// field gives. Roughly -0.7 to 0.7.
float gnoise( vec3 p )
{
	vec3 i = floor(p);
	vec3 f = fract(p);
	vec3 u = f * f * (3.0 - 2.0 * f);
	float n000 = dot(hash33(i + vec3(0,0,0)), f - vec3(0,0,0));
	float n100 = dot(hash33(i + vec3(1,0,0)), f - vec3(1,0,0));
	float n010 = dot(hash33(i + vec3(0,1,0)), f - vec3(0,1,0));
	float n110 = dot(hash33(i + vec3(1,1,0)), f - vec3(1,1,0));
	float n001 = dot(hash33(i + vec3(0,0,1)), f - vec3(0,0,1));
	float n101 = dot(hash33(i + vec3(1,0,1)), f - vec3(1,0,1));
	float n011 = dot(hash33(i + vec3(0,1,1)), f - vec3(0,1,1));
	float n111 = dot(hash33(i + vec3(1,1,1)), f - vec3(1,1,1));
	return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
		mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

// Four octaves. Five is visibly better on a still image and costs a fifth more
// per fragment over a body that can fill a quarter of the screen, which is the
// wrong trade for a game that has to run in a browser.
float fbm( vec3 p )
{
	float sum = 0.0;
	float amp = 0.5;
	for( int i = 0; i < 4; i++ )
	{
		sum += gnoise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

// ---- what a world is, as data -----------------------------------------------

uniform float radius = 50.0;
uniform float rimRetraction = 4.0;
uniform float rimBrightness = 1.0;
uniform vec3 rimColor : source_color = vec3(0.7,0.5,0.3);
uniform float animationSpeed = 0.004;
uniform float distortionStrength = 0.3;
uniform vec2 bandScale = vec2(20.0, 5.0);
uniform float worldSeed = 0.0;

// 0 draws continents, 1 draws the author's belts, and a gas giant is the only
// thing that wants 1.
uniform float bands : hint_range(0.0, 1.0) = 0.0;
// How large the continents are, and how far the noise is dragged sideways
// before it is read. Warp is what turns round blobs into coastlines.
uniform float groundScale = 2.4;
uniform float groundWarp = 0.6;

// The five colours of the ground, deepest to highest.
uniform vec3 abyssColor : source_color = vec3(0.06, 0.13, 0.22);
uniform vec3 seaColor : source_color = vec3(0.14, 0.32, 0.45);
uniform vec3 shoreColor : source_color = vec3(0.37, 0.49, 0.55);
uniform vec3 landColor : source_color = vec3(0.37, 0.48, 0.33);
uniform vec3 peakColor : source_color = vec3(0.64, 0.62, 0.49);
// Where the water stops, how hard the shoreline is, and how much of the ramp
// above it is lowland before the peaks start.
uniform float seaLevel : hint_range(0.0, 1.0) = 0.5;
uniform float coast : hint_range(0.001, 0.3) = 0.02;
uniform float landBand : hint_range(0.05, 1.0) = 0.4;

// Ice by latitude. capStart 1.0 or above means no cap at all.
uniform vec3 capColor : source_color = vec3(0.89, 0.87, 0.82);
uniform float capStart : hint_range(0.0, 2.0) = 2.0;
uniform float capFuzz : hint_range(0.01, 0.5) = 0.09;

// How hard the ground's own slope bends the normal, and how far apart the two
// samples that measure that slope are taken. Zero switches the whole thing off,
// which also skips two evaluations of the height field per fragment: the gas
// giant does not want relief and should not pay for it.
uniform float relief : hint_range(0.0, 0.5) = 0.0;
uniform float reliefStep : hint_range(0.002, 0.1) = 0.012;

// How smooth each kind of ground is. Water low, rock high. This is the whole
// reason an ocean reads as water rather than as blue ground.
uniform float seaRough : hint_range(0.0, 1.0) = 0.12;
uniform float landRough : hint_range(0.0, 1.0) = 0.90;
uniform float capRough : hint_range(0.0, 1.0) = 0.35;
uniform float specularAmount : hint_range(0.0, 1.0) = 0.5;

// Emissive ground below glowLevel. Black means none, which is every world but
// the volcanic one.
uniform vec3 glowColor : source_color = vec3(0.0, 0.0, 0.0);
uniform float glowLevel : hint_range(0.0, 1.0) = 0.25;

// The height field. One function, because the colour, the slope and the
// roughness all have to agree about where the ground is (CLAUDE.md 4.1).
float groundHeight( vec3 d, float seed )
{
	vec3 p = d * groundScale + vec3(seed);
	vec3 warp = vec3(
		gnoise(p + vec3(3.7, 1.3, 8.2)),
		gnoise(p + vec3(9.1, 6.4, 2.8)),
		gnoise(p + vec3(5.3, 7.9, 4.1)));
	return fbm(p + warp * groundWarp) * 1.35 + 0.5;
}


vec3 groundRamp( float h )
{
	float shelf = seaLevel * 0.55;
	if( h < shelf ) return mix(abyssColor, seaColor, smoothstep(0.0, shelf, h));
	// The coastline: a narrow band rather than a gradient, so a world with a sea
	// reads as having one.
	if( h < seaLevel + coast )
		return mix(seaColor, shoreColor,
			smoothstep(seaLevel - coast, seaLevel + coast, h));
	float top = seaLevel + coast + landBand;
	if( h < top ) return mix(shoreColor, landColor,
		smoothstep(seaLevel + coast, top, h));
	return mix(landColor, peakColor, smoothstep(top, 1.0, h));
}

void fragment()
{
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	// First get the ray direction in world space
	vec3 rayDir = normalize(transform(INV_VIEW_MATRIX,-VIEW));
	// t is the distance along that ray at which intersection occurs (or -1 if there was none)
	float t = raySphereIntersect( CAMERA_POSITION_WORLD-NODE_POSITION_WORLD, rayDir, vec3(0), radius );

	if( t > 0.0 )
	{ // t is greater than 0, therefore an intersection has occured along the ray
		vec3 worldPos = CAMERA_POSITION_WORLD+(rayDir*t);
		vec3 dir = normalize(worldPos-NODE_POSITION_WORLD);
		// Depth is calculated using the world position of the intersection.
		// OURS: mapped into OpenGL's -1 to 1 clip range.
		vec4 clipPos = PROJECTION_MATRIX * VIEW_MATRIX * vec4(worldPos, 1);
		DEPTH = (clipPos.z/clipPos.w) * 0.5 + 0.5;
		// The direction from the center is transformed back into view space to serve the normal
		NORMAL = transform( VIEW_MATRIX, dir );
		// Dir is then moved into local space to respect rotation of the node for texturing.
		// NORMALIZED, which the original did not need to be: it fed this only to
		// uvOnSphere, which is two atans and so does not care about length. The
		// inverse model matrix undoes the mesh's SCALE as well as its rotation,
		// and that mesh is scaled to the world's radius, so what comes back here
		// is about a sixtieth of a unit long. Read a noise field at that and
		// every fragment lands in the same cell, which draws a plain ball.
		dir = normalize( transform( inverse(MODEL_MATRIX), dir ) );

		float spin = worldSeed + TIME * animationSpeed;

		// OURS: the ground. A warped fractal read on the sphere's own
		// direction vector, so it wraps with no seam and no pole pinch.
		float land = groundHeight(dir, worldSeed);

		// The author's belts, for the one world that wants them.
		vec3 belt = whorleyOnSphere( dir, spin, bandScale, vec2(distortionStrength) );
		float banded = clamp((belt.x + belt.y + belt.z) / 3.0 * 0.5 + 0.5, 0.0, 1.0);

		float height = clamp(mix(land, banded, bands), 0.0, 1.0);
		vec3 albedo = groundRamp(height);

		// OURS: how wet this fragment is, which decides both its roughness and
		// whether its slope is allowed to bend the normal. Water is flat.
		float dry = smoothstep(seaLevel - coast, seaLevel + coast, height);

		// OURS: relief. Two more reads of the height field, one step along each
		// tangent, give its slope; the slope bends the normal. This is a normal
		// map generated from a height map, with no map in between: the height is
		// a function, so its gradient can be measured rather than baked.
		if( relief > 0.0 )
		{
			vec3 pole = abs(dir.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
			vec3 tanU = normalize(cross(pole, dir));
			vec3 tanV = cross(dir, tanU);
			float du = (groundHeight(normalize(dir + tanU * reliefStep), worldSeed) - land) / reliefStep;
			float dv = (groundHeight(normalize(dir + tanV * reliefStep), worldSeed) - land) / reliefStep;
			vec3 bent = normalize(dir - (tanU * du + tanV * dv) * relief * dry);
			NORMAL = transform( VIEW_MATRIX, normalize(transform(MODEL_MATRIX, bent)) );
		}

		// OURS: the polar cap, roughened by the same noise so its edge is
		// ragged rather than drawn on with a compass.
		float lat = abs(dir.y) + (height - 0.5) * 0.22;
		float ice = smoothstep(capStart - capFuzz, capStart + capFuzz, lat);
		albedo = mix(albedo, capColor, ice);

		ALBEDO = albedo;
		// OURS: water is smooth, ground is rough, ice is between them.
		ROUGHNESS = mix(mix(seaRough, landRough, dry), capRough, ice);
		SPECULAR = specularAmount;

		// OURS: fissures. Only where a world was given a glow colour.
		vec3 glow = glowColor * smoothstep(glowLevel, 0.0, height);
		EMISSION = fresnel(0.25,NORMAL,VIEW,rimRetraction)*rimColor*rimBrightness + glow;
		ALPHA = 1.0;
	}
	else ALPHA = 0.0;
}


// The light pass is ours too, and it has to be.
//
// Godot's own specular is physically right and visually invisible here: a
// dielectric sea reflects about four percent, which at the tactical camera's
// distance measured four pixels across on a 360 pixel world. Leaning the water
// toward metal was tried and is worse, because the ambient here is a flat
// colour with no sky in it to reflect, so a metallic ocean simply loses its
// diffuse and goes black.
//
// So the highlight is Blinn-Phong with its exponent driven by the same
// ROUGHNESS the ground writes, and its strength by SPECULAR. Both of those are
// still per world data, and the sea, the ice and the rock still differ by
// exactly the numbers data/tuning.json gives them; what changes is that the
// difference is now large enough to see. Ambient is untouched: writing light()
// replaces the per light term only.
void light()
{
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ATTENUATION * ndl;

	vec3 half_vector = normalize(LIGHT + VIEW);
	float ndh = max(dot(NORMAL, half_vector), 0.0);
	float gloss = 1.0 - ROUGHNESS;
	// 4 is a broad sheen on rock, 160 is a tight glint off water.
	float power = mix(4.0, 160.0, gloss);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION
		* pow(ndh, power) * gloss * specularAmount * ndl;
}
