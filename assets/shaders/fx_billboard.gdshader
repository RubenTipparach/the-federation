// The one shader every soft effect in the world is painted with: a flame
// tongue, a smoke puff, a scorch mark on a hull plate, the photon torpedo's
// star, and every layer of a ship coming apart.
//
// It paints TINTED GEOMETRY, never a texture. That is not a stylistic
// preference: a spatial ShaderMaterial sampling a texture does not work on the
// gl_compatibility renderer the Web target needs (a constant UV returns the
// right pixel and a varying UV returns nothing), so every effect here is a
// committed unit mesh with its softness computed from its own model space
// radius. Nothing is generated at run time (CLAUDE.md 2 and 5.1).
//
// ONE SHADER, MANY JOBS, because they are all the same job with dials between
// them (CLAUDE.md 4.1). Three uniforms do the separating:
//
//   occlude     how much of what is behind the effect it blocks. 0 is fire,
//               glow and plasma: purely additive, lighting the starfield and
//               the hull and hiding neither. 1 is smoke, ash and a scorch
//               mark: a normal alpha blend, which covers.
//   softness    how much of the shape is falloff. 0 is a hard rimmed coin,
//               which is what the torpedo's star wants because it is a shaped
//               mesh already and a radial fade would only round its points
//               off. 1 fades from the bright line all the way out.
//   bright_at   WHERE the bright line is. 0 is the middle, which is what a
//               blob wants. A RING wants the middle of its own band, so the
//               shock front is brightest along the band and fades to both of
//               its edges.
//
// occlude is what blend_premul_alpha buys. The blend is src + dst*(1 - src.a),
// so a fragment with zero alpha is an add and a fragment with full alpha is a
// mix, and the colour is written already multiplied by its own coverage below.
// Two shaders would be two vertex stages to keep billboarding the same way.
//
// The vertex stage swings the mesh to face the camera while KEEPING THE NODE'S
// SCALE, so a caller sizes a puff by scaling its node like any other object
// and does not have to know a billboard is involved.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_draw_never;

// The rim colour, and how strong the whole shape is drawn (alpha).
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The colour along the bright line. TWO COLOURS RATHER THAN ONE, because that
// is what makes a blob read as a flame instead of as a lamp: fire is orange at
// its edge and white at its heart, and the first cut of this had one colour
// per layer and three layers, which simply added up to white.
uniform vec4 hot : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// How tightly the hot colour is held to that line. Higher is a smaller,
// sharper heart with more of the shape left in the rim colour.
uniform float hot_focus : hint_range(0.5, 8.0) = 3.0;
// Roll in the billboard plane, radians. Two tongues of the same flame at
// opposite spins stop the fire reading as a stack of circles.
uniform float spin = 0.0;
// 0 adds, 1 covers. See the note above.
uniform float occlude : hint_range(0.0, 1.0) = 0.0;
// How much of the reach is falloff. See the note above.
uniform float softness : hint_range(0.0, 1.0) = 0.7;
// How quickly the tint falls away from the bright line. Low keeps the shape
// flat most of the way out and then turns down, which is what a shock front
// wants. High collapses it to a small bright middle inside a wide faint halo,
// which is what fire wants: at 2 a billow reads as a bubble with a visible
// outline, and past 3 the outline is gone but so is every lump, and a cloud of
// them averages out into one smooth ball. This was worth a uniform rather than
// a constant because those three renders are the whole difference between an
// explosion, a heap of circles, and an orange balloon.
uniform float soft_power : hint_range(0.5, 6.0) = 2.4;
// HOW BIG THE MESH THIS IS PAINTED ON IS, in its own coordinates. Every
// distance below is a fraction of it, so one set of numbers describes a shape
// whatever mesh carries it. The sprite meshes are half a unit across and
// disc.obj, which the scorch mark borrows from the terrain fields, is a whole
// one. Getting this wrong is not subtle: a fade written for a unit mesh and
// applied to a half unit one never reaches its rim, so a soft billow comes out
// as a hard edged coin, which is the "heap of plates" an early fireball was.
uniform float mesh_radius = 0.5;
// Where the brightest line sits, as a fraction of mesh_radius. 0 is the
// centre.
uniform float bright_at : hint_range(0.0, 1.0) = 0.0;
// How far from that line the tint has fallen to nothing, in the same fraction.
// A blob wants 1: bright in the middle, gone at the rim. A RING WANTS ITS OWN
// HALF WIDTH, which is much less, and this exists because deriving the reach
// from bright_at instead got it badly wrong: for a band running from 0.90 to
// 1.00 the far rim is 0.05 from the bright line but 0.95 from the centre, so a
// derived falloff held the whole band at nearly full alpha and drew a solid
// grey tube around the explosion.
uniform float fade_over : hint_range(0.01, 1.0) = 1.0;
// Whether to face the camera. Off for something lying on a surface, such as a
// scorch mark on a hull, which has an orientation of its own that matters.
uniform bool billboard = true;

varying vec3 v_model;

void vertex() {
	vec3 v = VERTEX;
	if (billboard) {
		float c = cos(spin);
		float s = sin(spin);
		v = vec3(v.x * c - v.y * s, v.x * s + v.y * c, v.z);
		// Face the camera: take the camera's basis for the orientation and the
		// node's own translation for the position.
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2],
			MODEL_MATRIX[3]);
		// Then put the node's scale back, which the basis above threw away.
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(
			vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
		VERTEX = v;
	}
	// Model space, like the shield glow's, so the falloff is the same wherever
	// the instance has been placed or spun to. The spin is a rotation about the
	// shape's own centre, so it leaves the radius alone.
	v_model = v;
}

void fragment() {
	float r = clamp(length(v_model) / max(mesh_radius, 0.001), 0.0, 1.0);
	// Distance from the bright line, normalised so 1 is where the tint has run
	// out. For a blob that line is the centre and the tint runs out at the rim;
	// for a ring it is the middle of the band, and both edges of the band are
	// equally far from it, so the front fades on both sides.
	float away = clamp(abs(r - bright_at) / max(fade_over, 0.001), 0.0, 1.0);
	float near = 1.0 - away;
	// Solid along the line, soft on the way out. A softness of 0 keeps the full
	// tint right out to the mesh edge, which is a flat coin.
	float cover = tint.a * mix(1.0, pow(near, soft_power), softness);
	vec3 rgb = mix(tint.rgb, hot.rgb, pow(near, hot_focus));
	// Premultiplied: the colour carries its own coverage, and ALPHA says only
	// how much of the background this fragment takes away.
	ALBEDO = rgb * cover;
	ALPHA = cover * occlude;
}
