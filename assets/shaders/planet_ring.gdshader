// A gas giant's ring.
//
// Ours, not vendored, though it reads the same 3D noise texture the planet
// does so that a world and its ring are built out of one field.
//
// A ring is not a flat disc of one colour. Three things make it read as a ring:
//
//   1. IT IS BANDED. The noise is sampled along ONE axis, the distance out from
//      the planet, so it comes out as concentric rings rather than as blotches.
//      That is the whole trick: a 3D field read on a line is a 1D profile.
//   2. IT HAS A DIVISION IN IT. One gap where the ice is swept clear. Without a
//      hard edge somewhere the eye reads the whole thing as haze.
//   3. THE PLANET SHADOWS IT. The half of the ring behind the world is dark,
//      which is the only cue that tells a player which way the star is when the
//      planet's own terminator is off screen.
//
// The mesh is assets/meshes/planet_ring.obj, an annulus from 0.74 to 1.0 with
// no texture coordinates, so the radial position is taken from the local
// vertex rather than from a UV.

shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform sampler3D noiseTexture : repeat_enable;
// Where the band starts, as a fraction of its outer edge. Must match the mesh
// that tools/gen_meshes.py writes.
uniform float innerEdge : hint_range(0.0, 0.99) = 0.74;
uniform vec3 ringColor : source_color = vec3(0.57, 0.42, 0.19);
uniform vec3 ringColorAlt : source_color = vec3(0.85, 0.72, 0.4);
uniform float ringDensity : hint_range(0.0, 1.0) = 0.55;
// Where the division falls across the band, and how wide it is.
uniform float ringGap : hint_range(0.0, 1.0) = 0.42;
uniform float ringGapWidth : hint_range(0.0, 0.5) = 0.07;
uniform float ringDetail = 9.0;
uniform float worldSeed = 0.0;
// The body that casts on it, in world units, and where the star is.
uniform float planetRadius = 50.0;
uniform vec3 sunDirection = vec3(0.0, 0.0, 1.0);
uniform float shadowDepth : hint_range(0.0, 1.0) = 0.82;

varying vec3 localPos;
varying vec3 worldPos;

void vertex() {
	localPos = VERTEX;
	worldPos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// How far out across the band this fragment sits, 0 at the inner edge.
	float r = length(localPos.xz);
	float across = clamp((r - innerEdge) / max(0.001, 1.0 - innerEdge), 0.0, 1.0);

	// Change 1: the field read along one axis, so the noise comes out as rings.
	float coarse = texture(noiseTexture, vec3(across * ringDetail + worldSeed, 0.31, 0.67)).r;
	float fine = texture(noiseTexture, vec3(across * ringDetail * 3.7 + worldSeed, 0.62, 0.19)).r;
	float band = clamp(coarse * 0.75 + fine * 0.35, 0.0, 1.0);

	// Change 2: the division, plus a fade at both edges so the ring does not end
	// on a hard rim.
	float gap = smoothstep(ringGapWidth, 0.0, abs(across - ringGap));
	float edges = smoothstep(0.0, 0.10, across) * smoothstep(1.0, 0.88, across);
	float cover = band * edges * (1.0 - gap) * ringDensity;

	// Change 3: the world's shadow. A point is in it when it lies behind the
	// planet along the sun's line and within its silhouette.
	vec3 fromCentre = worldPos - NODE_POSITION_WORLD;
	vec3 sun = normalize(sunDirection);
	float along = dot(fromCentre, sun);
	float offAxis = length(fromCentre - sun * along);
	float shadow = step(along, 0.0)
		* smoothstep(planetRadius, planetRadius * 0.82, offAxis);

	ALBEDO = mix(ringColor, ringColorAlt, band) * (1.0 - shadow * shadowDepth);
	ALPHA = cover;
}
