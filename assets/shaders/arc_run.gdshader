// One CONTIGUOUS RUN of the firing envelope: a wire outline at the weapon's
// true reach over a very transparent fill.
//
// The mesh (assets/meshes/arc_run.obj) is a full unit disc and this masks it
// down to the run, exactly as turn_arc.gdshader masks its circle. A run is
// anything from 30 to 360 degrees, so the alternative was a family of twelve
// fixed wedges or geometry built at runtime, which CLAUDE.md 5.1 forbids.
//
// The node is a child of the ship rig, already rotated to the ship's heading,
// and the rig then rotates this node to the run's FIRST sector. So model space
// +Z is the start of the run and it always sweeps from 0 to span_deg
// clockwise: nothing here has to be told the heading or the bearing.
//
// The node is scaled to the run's reach in sim units, so r = 1.0 IS the reach.
// The mesh carries 6 percent of margin past that for the outer stroke, which
// straddles the rim, and nothing is painted beyond it.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

// White, and never used: the rig sets this from a palette role every time it
// binds a ship, so no colour is written down here (CLAUDE.md 3.1).
uniform vec4 line_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// How far round from +Z the run reaches: 30 degrees per sector it covers.
uniform float span_deg = 30.0;
// The three states, set by the rig from data/tuning.json: a fitted run is an
// outline you can see past, a run that can fire right now is lit, and the run
// the player is pointing at in the ship display is bolder still.
uniform float fill_alpha = 0.05;
uniform float line_alpha = 0.35;
// What the fill is worth at the rim compared to at the ship. The reach is
// carried by the outline, so the wash under it does not have to reach as well,
// and a fill that thins with distance is the difference between a sector that
// reads as a shape from inside it and a slab a third of the arena wide. It
// also fades in off the bubble, so the inner edge is a soft start rather than
// a second ring around the hull.
uniform float fill_edge = 0.3;
// The 30 degree sector divisions INSIDE a run, as short ticks hanging in from
// the rim rather than full spokes. The grid stays readable and the run still
// reads as one shape. The alpha is a FRACTION of this run's line alpha, so the
// divisions come up with the run rather than staying at one weight while the
// outline around them lights.
uniform float tick_frac = 0.5;
uniform float tick_len = 0.09;
// Stroke weights in PIXELS, not in sim units, so an outline is the same
// weight at every zoom. A 288 unit run and a 160 unit one are drawn with the
// same pen.
uniform float line_px = 1.6;
uniform float tick_px = 1.0;
// A radial edge shared with a neighbouring run that reaches exactly as far is
// a SEAM, not a boundary of the envelope: the guns change there, the distance
// does not. Set to 1 it is drawn at tick weight, so the two runs read as one
// shape with a division in it rather than as two separate blocks.
uniform float start_seam = 0.0;
uniform float end_seam = 0.0;
// Where the run begins, as a fraction of its reach: the ship's own bubble, so
// six runs do not converge into a knot of lines over the hull and its shield
// ring. In sim units it is the same radius for every run, which is why it
// arrives as a fraction rather than as a constant here.
uniform float inner_r = 0.05;

varying vec3 v_model;

void vertex() {
	v_model = VERTEX;
}

// One antialiased stroke centred on the zero of a signed distance field
// measured in the mesh's own units. fwidth converts that field into pixels,
// which is what keeps the pen the same weight however far the camera is and
// however foreshortened the plane: each feature gets its own derivative, so a
// radial edge seen nearly edge on is corrected by its own gradient rather
// than by a shared guess.
float stroke(float d, float px) {
	float aa = max(fwidth(d), 1e-7);
	float half_w = max(px, 0.0) * 0.5 * aa;
	return 1.0 - smoothstep(half_w, half_w + aa, abs(d));
}

void fragment() {
	vec2 p = vec2(v_model.x, v_model.z);
	float r = length(p);
	// Bearing off the start of the run, clockwise, matching the sim's
	// atan(x, z) convention.
	float rel = mod(degrees(atan(p.x, p.y)), 360.0);
	// Nothing outside the run is drawn. The angular slack is what the start
	// and end strokes need, since each straddles its own edge.
	if (r > 1.04 || r < inner_r) {
		discard;
	}
	if (rel > span_deg + 6.0 && rel < 354.0) {
		discard;
	}

	// Inside the run's angle, at any radius. The rim stroke stops here rather
	// than running on into the slack, so it meets the end stroke in a corner
	// instead of overshooting it.
	float ang_in = step(rel, span_deg);
	float inside = ang_in * step(r, 1.0);

	// The rim: the outer arc, at the true reach.
	float line = stroke(r - 1.0, line_px) * ang_in;
	float faint = 0.0;

	// The two radial edges. Distance to a ray is the perpendicular component,
	// which stays continuous across the whole disc, so fwidth never sees the
	// jump that a wrapped angle would give it. The step() picks the correct
	// half of the line the ray lies on, and a seam is drawn with the tick pen
	// instead of the outline pen.
	float inner = step(r, 1.0);
	float head = step(0.0, p.y) * inner;
	line = max(line, stroke(p.x, line_px) * head * (1.0 - start_seam));
	faint = max(faint, stroke(p.x, tick_px) * head * start_seam);
	float s = radians(span_deg);
	vec2 dir = vec2(sin(s), cos(s));
	vec2 perp = vec2(cos(s), -sin(s));
	float tail = step(0.0, dot(p, dir)) * inner;
	line = max(line, stroke(dot(p, perp), line_px) * tail * (1.0 - end_seam));
	faint = max(faint, stroke(dot(p, perp), tick_px) * tail * end_seam);

	// Interior sector ticks. The offset is wrapped to the nearest division so
	// it is continuous where the tick is drawn and only jumps at the middle of
	// a sector, where nothing is drawn anyway.
	float k = rel / 30.0;
	float off = k - floor(k + 0.5);
	faint = max(faint, stroke(r * sin(radians(off * 30.0)), tick_px)
		* step(1.0 - tick_len, r) * inside);

	float t = clamp((r - inner_r) / max(1.0 - inner_r, 1e-4), 0.0, 1.0);
	float a = fill_alpha * inside * mix(1.0, fill_edge, t) * smoothstep(0.0, 0.08, t);
	a = max(a, line_alpha * tick_frac * faint);
	a = max(a, line_alpha * line);
	if (a <= 0.002) {
		discard;
	}
	ALBEDO = line_color.rgb;
	ALPHA = a * line_color.a;
}
