// The shader every world in the tactical view is drawn with.
//
// This is Simple Spatial Planet by Nolkaloid
// (https://godotshaders.com/shader/simple-spatial-planet/, CC0) with two
// changes and nothing else. The unmodified original is beside it as
// simple_spatial_planet.gdshader so the difference stays one readable diff, and
// docs/14 records both.
//
// WHAT IT DOES, in one line: it ignores the mesh it is drawn on and ray traces
// a sphere instead. The mesh is only a volume to get fragments generated in.
// That is why the limb is a true circle at any zoom, why the surface compresses
// correctly toward the edge, and why the mesh needs no texture coordinates,
// which matters here because assets/meshes/sphere.obj has none.
//
// THE TWO CHANGES:
//
//   1. THE DEPTH WRITE IS OPENGL'S. The original writes
//      `DEPTH = clipPos.z/clipPos.w`, which is Vulkan's 0 to 1 convention.
//      This project runs gl_compatibility (project.godot), where the range is
//      -1 to 1, so every fragment was rejected and a planet rendered as
//      nothing at all. The line here is
//      `DEPTH = (clipPos.z/clipPos.w) * 0.5 + 0.5;`.
//
//   2. THE SURFACE COLOUR IS RAMPED. The original writes the raw whorley noise
//      vector straight to ALBEDO and has no colour input of any kind, so every
//      world it draws is the same red and cyan marble whatever it is meant to
//      be. Here the noise becomes a height and the height picks from a three
//      colour ramp, so a terran world and an ice world differ. The colours come
//      from data/palette.json through src/ui/planet_body.gd.
//
// Everything else, including the ray sphere intersection and the whorley
// function that gives the bands their shape, is the author's.

shader_type spatial;
render_mode cull_front;

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

uniform float radius = 256.0;
uniform float rimRetraction = 4.0;
uniform float rimBrightness = 1.0;
uniform vec3 rimColor : source_color = vec3(0.7,0.5,0.3);
uniform float animationSpeed = 0.25;
uniform float distortionStrength = 0.3;
// Added by change 2: the surface ramp, low ground to high ground, and where
// the low band ends. Every one of these is a data/palette.json entry.
uniform vec3 groundLow : source_color = vec3(0.10, 0.26, 0.46);
uniform vec3 groundMid : source_color = vec3(0.24, 0.45, 0.36);
uniform vec3 groundHigh : source_color = vec3(0.62, 0.66, 0.49);
uniform float groundSplit : hint_range(0.0, 1.0) = 0.46;
// How wide the bands are, and a per world offset into the noise so two worlds
// in one arena are not the same world twice. The offset enters where TIME does,
// which is free: it is the same field read at a different place.
uniform vec2 bandScale = vec2(20.0, 5.0);
uniform float worldSeed = 0.0;

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
		// CHANGE 1: mapped into OpenGL's -1 to 1 clip range.
		vec4 clipPos = PROJECTION_MATRIX * VIEW_MATRIX * vec4(worldPos, 1);
		DEPTH = (clipPos.z/clipPos.w) * 0.5 + 0.5;
		// The direction from the center is transformed back into view space to serve the normal
		NORMAL = transform( VIEW_MATRIX, dir );
		// Dir is then moved into local space to respect rotation of the node for texturing
		dir = transform( inverse(MODEL_MATRIX), dir );
		// CHANGE 2: the noise becomes a height, and the height picks a colour
		// from the ramp, rather than being painted as a colour itself.
		vec3 n = whorleyOnSphere( dir, worldSeed + TIME*animationSpeed, bandScale, vec2(distortionStrength) );
		float height = clamp( (n.x + n.y + n.z) / 3.0 * 0.5 + 0.5, 0.0, 1.0 );
		ALBEDO = height < groundSplit
			? mix(groundLow, groundMid, height / max(0.001, groundSplit))
			: mix(groundMid, groundHigh, (height - groundSplit) / max(0.001, 1.0 - groundSplit));
		EMISSION = fresnel(0.25,NORMAL,VIEW,rimRetraction)*rimColor*rimBrightness;
		ALPHA = 1.0;
	}
	else ALPHA = 0.0;
}
