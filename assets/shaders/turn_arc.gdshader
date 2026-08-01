// The helm's turn arc: how far the ship still has to come round.
//
// The mesh (assets/meshes/turn_arc.obj) is a full circle and this masks it
// down to the sweep actually ordered. A turn is any angle up to a half circle
// in either direction, and a mesh cannot change its angular span, so the
// alternative was either a family of fixed wedges or geometry built at
// runtime, which CLAUDE.md 5.1 forbids. One committed circle plus an angle
// test is the version that keeps the rule.
//
// The node is a child of the ship rig, which is already rotated to the ship's
// heading, so model space +Z IS the bow and the arc simply runs from 0 to the
// signed turn delta. Nothing has to be told what the current heading is.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 arc_color : source_color = vec4(0.37, 0.83, 0.91, 1.0);
// Signed degrees still to turn: positive is to starboard.
uniform float sweep_deg = 0.0;
// Below this the ship is on its ordered heading and the arc is not drawn, so
// a settled helm shows nothing rather than a permanent sliver.
uniform float dead_zone_deg = 1.5;
// Alpha at the bow end and at the ordered heading end. The bright end is the
// one the ship is turning toward, so the arc reads as an arrow without
// needing an arrow.
uniform float alpha_near = 0.10;
uniform float alpha_far = 0.85;
// A hard bright tick at the ordered heading, so the arc has an unambiguous
// end rather than trailing off into the background.
uniform float tick_deg = 4.0;

varying vec3 v_model;

void vertex() {
	v_model = VERTEX;
}

void fragment() {
	float sweep = sweep_deg;
	if (abs(sweep) < dead_zone_deg) {
		discard;
	}
	// Angle off the bow, negative to port, in the same sense as the sim's
	// bearings (clockwise seen from above).
	float ang = degrees(atan(v_model.x, v_model.z));
	float t;
	if (sweep > 0.0) {
		if (ang < 0.0 || ang > sweep) {
			discard;
		}
		t = ang / sweep;
	} else {
		if (ang > 0.0 || ang < sweep) {
			discard;
		}
		t = ang / sweep;
	}
	ALBEDO = arc_color.rgb;
	if (abs(abs(sweep) - abs(ang)) < tick_deg) {
		ALPHA = arc_color.a;
	} else {
		ALPHA = mix(alpha_near, alpha_far, t) * arc_color.a;
	}
}
