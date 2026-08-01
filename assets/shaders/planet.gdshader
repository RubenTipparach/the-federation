// A world, painted on the unit sphere the terrain scenes instance.
//
// Everything is derived from position in OBJECT space, so the pattern is fixed
// to the planet and not to the camera or to the world: two worlds of the same
// kind at different places in the arena get the same treatment rather than
// swimming through one shared field.
//
// Three colours and a seed make three very different planets, which is the
// point: rock, ice and gas giant are the same shader with different uniforms in
// their materials, not three shaders to keep in step (CLAUDE.md 4.1).
//
// This is lit, unlike almost every other shader in the project. A world is a
// solid body and the terminator is most of what makes it read as one, so it
// takes the same directional light the hulls do. The atmosphere shell around it
// is a separate, unshaded mesh: see atmosphere.gdshader.
//
// Value noise rather than a texture: a committed texture would be an art asset
// under CLAUDE.md section 3 and would have to carry a palette, and at the size
// a planet is drawn here the noise is doing the job of a 2048 pixel map for
// nothing. Runs on gl_compatibility, which the Web target requires.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

uniform vec4 deep : source_color = vec4(0.20, 0.28, 0.38, 1.0);
uniform vec4 land : source_color = vec4(0.49, 0.66, 0.81, 1.0);
uniform vec4 high : source_color = vec4(0.89, 0.87, 0.82, 1.0);
// Which way the pattern runs. 1 gives a rock: blobby continents. 0 gives a gas
// giant: bands of latitude, because the noise is stretched to nothing around
// the equator and only the vertical coordinate survives.
uniform float blobbiness : hint_range(0.0, 1.0) = 1.0;
// How far the pale colour reaches down from the poles. 0 leaves none.
uniform float cap_extent : hint_range(0.0, 1.0) = 0.16;
uniform float roughness_amount : hint_range(0.0, 1.0) = 0.9;
uniform float noise_scale : hint_range(0.5, 12.0) = 3.0;
uniform float seed : hint_range(0.0, 64.0) = 0.0;

// Hash and value noise. Cheap, deterministic, and identical on every driver
// that can do fract(), which matters because the Web export has to look like
// the desktop one.
float hash13(vec3 p) {
	p = fract(p * 0.1031 + seed);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i + vec3(0.0, 0.0, 0.0));
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float total = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		total += value_noise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return total;
}

void fragment() {
	vec3 unit = normalize(NODE_POSITION_VIEW * 0.0 + VERTEX);
	// Squashing the horizontal axes toward zero turns blobs into bands, which
	// is the whole difference between a rocky world and a gas giant.
	vec3 sample_at = vec3(unit.x * blobbiness, unit.y, unit.z * blobbiness) * noise_scale;
	float n = fbm(sample_at);

	// Two steps rather than a smooth ramp: a hard coastline reads at the size a
	// planet is actually drawn, where a soft gradient reads as a smudge.
	vec3 col = mix(deep.rgb, land.rgb, smoothstep(0.42, 0.52, n));
	col = mix(col, high.rgb, smoothstep(0.63, 0.72, n));

	// Ice caps, by latitude, roughened by the same noise so the edge is not a
	// drawn circle.
	float lat = abs(unit.y);
	float cap = smoothstep(1.0 - cap_extent - n * 0.18, 1.0 - cap_extent * 0.4, lat);
	col = mix(col, high.rgb, cap * step(0.001, cap_extent));

	ALBEDO = col;
	ROUGHNESS = roughness_amount;
	METALLIC = 0.0;
}
