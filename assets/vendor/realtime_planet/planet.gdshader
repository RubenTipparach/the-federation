// A world's surface.
//
// Adapted from "Procedural Blue Planet" by Julien Sulpis, the shader behind
// https://github.com/jsulpis/realtime-planet-shader (and
// https://www.shadertoy.com/view/Ds3XRl). Copyright (c) Julien Sulpis.
//
// This file is part of The Federation, which is free software: you can
// redistribute it and/or modify it under the terms of the GNU General Public
// License as published by the Free Software Foundation, either version 3 of the
// License, or (at your option) any later version. See the LICENSE file at the
// root of this repository. The whole game is GPL-3.0 BECAUSE of this file: that
// was a deliberate choice, and docs/14 records it.
//
// The author's original is committed beside this one, unmodified, as
// procedural.fragment.glsl. It is a WebGL full screen effect; this is a Godot
// spatial shader on a mesh in a scene, so the port is not line for line and the
// list below says what moved.
//
// WHAT IS THE AUTHOR'S, and it is most of what you see:
//   - the noise displaced ray sphere intersection, which is what gives a world
//     a silhouette with mountains on it rather than a perfect circle
//   - the normal taken by differencing that intersection, so the terrain is lit
//     by its own slope
//   - the fbm and the domain warped fbm, and the idea of flattening the noise
//     under the oceans so a sea bed is not corrugated
//   - the altitude ramp with its levels and transitions
//   - the domain warped cloud layer, thinned over high ground
//   - specular on water only, and the softened terminator
//
// WHAT IS OURS:
//   1. IT IS A SPATIAL SHADER. The author renders one planet over the whole
//      frame from a fixed camera. This runs on a mesh, at a real position, at a
//      real radius, with our camera, so it takes the ray from the scene and
//      writes DEPTH from the hit. Ships in front of a world occlude it and
//      ships behind it are occluded.
//   2. IT WORKS IN UNIT PLANET SPACE. Every one of the author's levels is
//      written for a radius of about 1 and our worlds are 40 to 55 arena units
//      across, so the ray is divided into the planet's own radius before the
//      intersection and multiplied back after. That is what lets his numbers
//      stay his numbers.
//   3. THE COLOURS ARE PALETTE ROLES. His five hardcoded surface colours, his
//      cloud white and his ice are uniforms fed from data/palette.json.
//   4. THE GAS GIANT KEEPS ITS BELTS. Our whorley band field is still here and
//      `bands` mixes to it, because a gas giant has no coastline to draw and
//      the author's terrain has no belts.
//   5. NO STARS, NO MOON, NO TONE MAPPING, NO VIGNETTE. We have a sky shader,
//      the simulation places real moons, and tone mapping the planet alone
//      would leave it in a different colour space from the rest of the frame.
//   6. THE ATMOSPHERE IS A SEPARATE PASS. His is computed in the same fragment
//      because he owns the whole frame. Ours is on its own slightly larger
//      sphere, atmosphere.gdshader beside this file, so it can blend over the
//      sky and over the ships at the limb without this pass giving up its depth
//      write.
//   7. A NIGHT SIDE. Where a world's palette names a `glow`, the unlit half
//      keeps it, which is a volcanic world's fissures and, later, city lights.

shader_type spatial;
render_mode cull_front, unshaded;

// ---- what the scene tells us ------------------------------------------------

uniform float radius = 50.0;
// Toward the sun, in world space, set by src/ui/planet_body.gd from the scene's
// own light so that a world and a hull are lit from the same place.
uniform vec3 sunDirection = vec3(0.0, 0.0, 1.0);
uniform float sunIntensity = 1.7;
uniform float ambientLight : hint_range(0.0, 1.0) = 0.07;
// The author samples a 3D noise texture rather than computing noise, which is
// the single biggest reason his runs on a phone. Ours is a NoiseTexture3D
// authored in scenes/terrain/planet.tscn.
uniform sampler3D noiseTexture : repeat_enable;

// ---- what the world is ------------------------------------------------------

uniform float terrainScale = 1.0;
uniform float noiseStrength = 0.06;
uniform float waterLevel = 0.0;
uniform float sandLevel = 0.028;
uniform float treeLevel = 0.03;
uniform float rockLevel = 0.1;
uniform float iceLevel = 0.15;
uniform float transitionWidth = 0.02;

uniform float cloudsDensity : hint_range(0.0, 1.0) = 0.0;
uniform float cloudsScale = 3.0;
uniform float cloudsSpeed = 1.0;

uniform vec3 abyssColor : source_color = vec3(0.01, 0.05, 0.15);
uniform vec3 seaColor : source_color = vec3(0.02, 0.12, 0.27);
uniform vec3 shoreColor : source_color = vec3(1.0, 1.0, 0.85);
uniform vec3 landColor : source_color = vec3(0.02, 0.1, 0.06);
uniform vec3 peakColor : source_color = vec3(0.15, 0.12, 0.12);
uniform vec3 capColor : source_color = vec3(0.8, 0.9, 0.9);
uniform vec3 cloudColor : source_color = vec3(1.0, 1.0, 1.0);
uniform vec3 glowColor : source_color = vec3(0.0, 0.0, 0.0);
uniform float glowLevel : hint_range(0.0, 1.0) = 0.25;

// Ours: the gas giant's belts, kept from the shader this replaced.
uniform float bands : hint_range(0.0, 1.0) = 0.0;
uniform vec2 bandScale = vec2(16.0, 4.0);
uniform float distortionStrength = 0.4;

uniform float spin = 0.0;
uniform float worldSeed = 0.0;
// How hard the terrain's own slope bends the normal. The height is in units of
// the planet's radius, so this is large: a mountain a hundredth of a radius
// tall across a tenth of a radius is a gentle slope in absolute terms and has
// to be exaggerated to read at all at this distance.
uniform float reliefStrength = 6.0;

// ---- the author's helpers ---------------------------------------------------

float inverseLerp(float v, float minValue, float maxValue) {
	return (v - minValue) / (maxValue - minValue);
}

float remap(float v, float inMin, float inMax, float outMin, float outMax) {
	return mix(outMin, outMax, inverseLerp(v, inMin, inMax));
}

float noise(vec3 p) {
	return texture(noiseTexture, p * 0.05).r;
}

// https://iquilezles.org/articles/intersectors/
float sphIntersect(vec3 ro, vec3 rd, vec3 centre, float rad) {
	vec3 oc = ro - centre;
	float b = dot(oc, rd);
	float c = dot(oc, oc) - rad * rad;
	float h = b * b - c;
	if (h < 0.0) {
		return -1.0;
	}
	return -b - sqrt(h);
}

float fbm(vec3 p, int octaves, float persistence, float lacunarity, float exponentiation) {
	float amplitude = 0.5;
	float frequency = 3.0;
	float total = 0.0;
	float normalization = 0.0;
	for (int i = 0; i < octaves; i++) {
		total += noise(p * frequency) * amplitude;
		normalization += amplitude;
		amplitude *= persistence;
		frequency *= lacunarity;
	}
	total /= normalization;
	total = total * 0.8 + 0.1;
	return pow(total, exponentiation);
}

float domainWarpingFBM(vec3 p, int octaves, float persistence, float lacunarity, float exponentiation) {
	vec3 offset = vec3(
		fbm(p, octaves, persistence, lacunarity, exponentiation),
		fbm(p + vec3(43.235, 23.112, 0.0), octaves, persistence, lacunarity, exponentiation),
		0.0);
	return fbm(p + offset, 2, persistence, lacunarity, exponentiation);
}

mat3 rotateY(float angle) {
	float c = cos(angle);
	float s = sin(angle);
	return mat3(vec3(c, 0, s), vec3(0, 1, 0), vec3(-s, 0, c));
}

// ---- ours: the gas giant's belts --------------------------------------------

vec3 whorley(vec2 uv, float time, vec2 distortion) {
	for (float i = 1.0; i < 10.0; i += 1.0) {
		uv.x += distortion.x * sin(i * uv.y + time);
		uv.y += distortion.y * cos(i * uv.x + time * 0.2);
	}
	return vec3(cos(uv.x + uv.y + 2.0),
		sin(uv.x + uv.y + 2.2),
		sin(uv.x + uv.y + 1.0) + cos(uv.x + uv.y + 1.5));
}

float beltHeight(vec3 dir, float time) {
	float uvX = (atan(dir.y, length(vec2(dir.x, dir.z))) / PI) + 0.5;
	float uvY = (atan(dir.x, dir.z) + PI) / TAU;
	vec3 belt = normalize(whorley(vec2(uvX, uvY) * bandScale, time, vec2(distortionStrength)));
	return clamp((belt.x + belt.y + belt.z) / 3.0 * 0.5 + 0.5, 0.0, 1.0);
}

// ---- the surface ------------------------------------------------------------

// The author's, including the flattening under the oceans: without it a sea bed
// is as corrugated as a mountain range and the water reads as rough ground.
float planetNoise(vec3 p) {
	float height = fbm(p * terrainScale, 6, 0.5, 2.0, 5.0) * noiseStrength;
	return mix(
		height / 3.0 + noiseStrength / 50.0,
		height,
		smoothstep(sandLevel, sandLevel + transitionWidth / 2.0, height * 5.0));
}

// The author's: a ray sphere intersection with the noise added to the radius.
// Everything here is in UNIT PLANET SPACE, so the centre is the origin and the
// surface is at 1.
float planetDist(vec3 ro, vec3 rd, float turn) {
	float smoothHit = sphIntersect(ro, rd, vec3(0.0), 1.0);
	vec3 at = rotateY(turn) * (ro + smoothHit * rd);
	return sphIntersect(ro, rd, vec3(0.0), 1.0 + planetNoise(at));
}

// The author's idea, our arithmetic (change 8). He gets the normal by
// differencing the ray sphere intersection itself, three more traces around the
// hit. That is elegant and it is written for his coordinate convention: ported
// into unit planet space it comes out INVERTED, which lights every world from
// behind and draws a black disc. It cost a render to find and a measurement to
// confirm, so it is written down here.
//
// What this does instead is the same thing one step earlier: it differences the
// HEIGHT rather than the distance, along two tangents, and bends the sphere
// normal by that slope. Same terrain, same mountains catching the same light,
// and the direction cannot be wrong because it starts from the outward normal.
vec3 planetNormal(vec3 p, float turn) {
	vec3 outward = normalize(p);
	vec3 pole = abs(outward.y) > 0.99 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 tanU = normalize(cross(pole, outward));
	vec3 tanV = cross(outward, tanU);
	mat3 turned = rotateY(turn);
	float e = 0.02;
	float here = planetNoise(turned * outward);
	float du = (planetNoise(turned * normalize(outward + tanU * e)) - here) / e;
	float dv = (planetNoise(turned * normalize(outward + tanV * e)) - here) / e;
	return normalize(outward - (tanU * du + tanV * dv) * reliefStrength);
}

vec3 transformDir(mat4 mtx, vec3 vec) {
	return (mtx * vec4(vec, 1.0)).rgb - mtx[3].rgb;
}

void fragment() {
	// A SCISSOR, not a blend. Writing ALPHA at all puts a Godot material in the
	// transparent queue, where it does not write depth and is sorted against
	// other transparents by object origin. A world and its own atmosphere shell
	// share an origin, so that sort is a coin toss, and the world lost it: its
	// body vanished in a battle while its ring and its air stayed. With a
	// scissor threshold the material is opaque again, it writes depth, and it is
	// drawn before anything transparent in the scene.
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(transformDir(INV_VIEW_MATRIX, -VIEW));
	vec3 centre = NODE_POSITION_WORLD;

	// Change 2: into the planet's own radius, where the author's numbers live.
	vec3 rou = (ro - centre) / radius;
	float turn = worldSeed + TIME * spin;
	float t = planetDist(rou, rd, turn);

	if (t < 0.0) {
		ALPHA = 0.0;
	} else {
		vec3 hit = rou + rd * t;
		vec3 world = centre + hit * radius;

		// Change 1: this is a thing in a scene, so it owns a depth value.
		vec4 clipPos = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
		DEPTH = (clipPos.z / clipPos.w) * 0.5 + 0.5;

		vec3 turned = rotateY(turn) * hit;
		float altitude = 5.0 * planetNoise(turned);

		// Change 4: a gas giant has no coastline, so its height is the belts.
		altitude = mix(altitude, beltHeight(normalize(turned), turn) * iceLevel * 1.6, bands);

		// The author's ramp, with change 3: every colour is a palette role.
		float half_transition = transitionWidth / 2.0;
		vec3 albedo = mix(abyssColor, seaColor,
			smoothstep(waterLevel, waterLevel + transitionWidth, altitude));
		albedo = mix(albedo, shoreColor,
			smoothstep(sandLevel, sandLevel + half_transition, altitude));
		albedo = mix(albedo, landColor,
			smoothstep(treeLevel, treeLevel + transitionWidth, altitude));
		albedo = mix(albedo, peakColor,
			smoothstep(rockLevel, rockLevel + transitionWidth, altitude));
		albedo = mix(albedo, capColor,
			smoothstep(iceLevel, iceLevel + transitionWidth, altitude));

		// The author's clouds: a domain warped field, thresholded, and thinned
		// out over high ground so a mountain range is not buried.
		if (cloudsDensity > 0.0) {
			vec3 cloudsCoord = (turned + vec3(TIME * 0.008 * cloudsSpeed)) * cloudsScale;
			float density = remap(
				domainWarpingFBM(cloudsCoord, 3, 0.3, 5.0, cloudsScale), -1.0, 1.0, 0.0, 1.0);
			float threshold = 1.0 - cloudsDensity * 0.5;
			density *= smoothstep(threshold, threshold + 0.1, density);
			density *= smoothstep(rockLevel, (rockLevel + treeLevel) / 2.0, altitude);
			albedo = mix(albedo, cloudColor, density);
		}

		vec3 normal = planetNormal(hit, turn);
		float lit = dot(normal, normalize(sunDirection));
		// The author's softened terminator: the power is not physical and it
		// reads better than the straight lambert it replaces.
		float day = pow(clamp(lit, 0.0, 1.0), 2.0) * sunIntensity;

		// The author's: only water is smooth enough to throw the sun back.
		float wet = smoothstep(sandLevel + transitionWidth, sandLevel, altitude);
		vec3 reflected = normalize(reflect(-normalize(sunDirection), normal));
		float phong = pow(max(0.0, dot(rd, reflected)), 10.0) * 0.2 * sunIntensity;

		// Change 7: what a world keeps on its dark side.
		vec3 night = glowColor * smoothstep(glowLevel, 0.0, altitude)
			* (1.0 - clamp(lit, 0.0, 1.0));

		ALBEDO = albedo * (ambientLight + day) + vec3(wet * phong) + night;
		ALPHA = 1.0;
	}
}
