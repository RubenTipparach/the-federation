// A world's atmosphere.
//
// Adapted from the `atmosphereColor` function of "Procedural Blue Planet" by
// Julien Sulpis (https://github.com/jsulpis/realtime-planet-shader,
// https://www.shadertoy.com/view/Ds3XRl). Copyright (c) Julien Sulpis.
//
// This file is part of The Federation and is GPL-3.0 for that reason. See the
// LICENSE file at the root of this repository, and docs/14.
//
// WHAT IS THE AUTHOR'S: the shape of the thing. Four powers of the same limb
// term stacked on each other, a tight one for the bright line right on the
// edge and a broad one for the haze that reaches inward, biased toward the sun
// so the lit limb glows and the dark limb does not. That stack is why it reads
// as air rather than as a drawn outline.
//
// WHAT IS OURS: it is a pass rather than part of a full screen effect. The
// author owns his whole frame, so he can add the atmosphere to whatever the ray
// found, planet or space. We are in a scene with ships and a sky in it, so this
// runs on its own shell mesh, slightly larger than the world, drawn additively
// with no depth write. That way the haze reaches past the limb over the stars
// without this pass having to give up the body's depth, and a hull in front of
// a world is still in front of its atmosphere.

shader_type spatial;
render_mode blend_add, unshaded, cull_front, depth_draw_never;

uniform float radius = 50.0;
uniform vec3 sunDirection = vec3(0.0, 0.0, 1.0);
uniform float sunIntensity = 1.7;
uniform vec3 atmosphereColor : source_color = vec3(0.35, 0.55, 0.9);
uniform float atmosphereDensity : hint_range(0.0, 4.0) = 1.0;

vec3 transformDir(mat4 mtx, vec3 vec) {
	return (mtx * vec4(vec, 1.0)).rgb - mtx[3].rgb;
}

// https://iquilezles.org/articles/intersectors/
float sphIntersect(vec3 ro, vec3 rd, float rad) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - rad * rad;
	float h = b * b - c;
	if (h < 0.0) {
		return -1.0;
	}
	return -b - sqrt(h);
}

void fragment() {
	vec3 ro = CAMERA_POSITION_WORLD;
	vec3 rd = normalize(transformDir(INV_VIEW_MATRIX, -VIEW));
	// Unit planet space, so the author's falloffs keep their meaning whatever
	// radius the simulation gave this world.
	vec3 rou = (ro - NODE_POSITION_WORLD) / radius;

	// Where this ray passes the planet, and how far that is from the limb.
	float toTangent = max(0.0, sqrt(max(0.0, dot(rou, rou) - 1.0)));
	vec3 atLimb = rou + rd * toTangent;
	float distFromEdge = abs(length(atLimb) - 1.0);
	float planetEdge = max(1.0 - distFromEdge, 0.0);

	// Biased toward the sun: the lit limb has air on it, the dark one does not.
	float mask = pow(clamp((dot(normalize(sunDirection), atLimb) + 1.0) / 1.5, 0.0, 1.0), 5.0);
	mask *= atmosphereDensity * sunIntensity;

	// Is the solid body in the way of this ray? The broad inner haze belongs
	// over the disc and the bright line belongs just outside it.
	float onPlanet = step(0.0, sphIntersect(rou, rd, 1.0));

	float glow = pow(planetEdge, 120.0) * 0.5;
	glow += pow(planetEdge, 50.0) * 0.3 * (1.5 - onPlanet);
	glow += pow(planetEdge, 15.0) * 0.03;
	glow += pow(planetEdge, 5.0) * 0.04 * onPlanet;

	ALBEDO = atmosphereColor * glow * mask;
	ALPHA = 1.0;
}
