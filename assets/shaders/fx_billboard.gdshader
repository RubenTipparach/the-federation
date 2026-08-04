// The one shader every soft effect in the world is painted with: a flame
// tongue, a smoke puff, a scorch mark on a hull plate.
//
// It paints TINTED GEOMETRY, never a texture. That is not a stylistic
// preference: a spatial ShaderMaterial sampling a texture does not work on the
// gl_compatibility renderer the Web target needs (a constant UV returns the
// right pixel and a varying UV returns nothing), so every effect here is a
// committed unit mesh with its softness computed from its own model space
// radius. assets/meshes/sprite_disc.obj is that mesh, and nothing is generated
// at run time (CLAUDE.md 2 and 5.1).
//
// ONE SHADER, TWO JOBS, because they are the same job with a dial between them
// (CLAUDE.md 4.1). `occlude` says how much of what is behind the effect it
// blocks:
//
//   occlude 0   fire, glow, plasma. Purely additive: it lights the starfield
//               and the hull behind it and hides neither.
//   occlude 1   smoke, ash, a scorch mark. A normal alpha blend: it covers.
//
// That is what blend_premul_alpha buys. The blend is src + dst*(1 - src.a), so
// a fragment with zero alpha is an add and a fragment with full alpha is a
// mix, and the colour is written already multiplied by its own coverage below.
// Two shaders would be two vertex stages to keep billboarding the same way.
//
// The vertex stage swings the mesh to face the camera while KEEPING THE NODE'S
// SCALE, so a caller sizes a puff by scaling its node like any other object
// and does not have to know a billboard is involved.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_draw_never;

// The rim colour, and how strong the whole blob is drawn (alpha).
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// The colour through the middle. TWO COLOURS RATHER THAN ONE, because that is
// what makes a blob read as a flame instead of as a lamp: fire is orange at
// its edge and white at its heart, and the first cut of this had one colour
// per layer and three layers, which simply added up to white. The wreck
// fireball already burns through a core and an edge for the same reason.
uniform vec4 hot : source_color = vec4(1.0, 1.0, 1.0, 1.0);
// How tightly the hot colour is held to the middle. Higher is a smaller,
// sharper heart with more of the blob left in the rim colour.
uniform float hot_focus : hint_range(0.5, 8.0) = 3.0;
// Roll in the billboard plane, radians. Two tongues of the same flame at
// opposite spins stop the fire reading as a stack of circles.
uniform float spin = 0.0;
// 0 adds, 1 covers. See the note above.
uniform float occlude : hint_range(0.0, 1.0) = 0.0;
// How much of the radius is falloff. 1 is a blob with no edge at all, 0 is a
// hard rimmed coin, which is what the photon torpedo's star wants: it is a
// shaped mesh already and a radial fade would only round its points off.
uniform float softness : hint_range(0.0, 1.0) = 0.7;
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
	// disc's own centre, so it leaves the radius alone.
	v_model = v;
}

void fragment() {
	float r = clamp(length(v_model), 0.0, 1.0);
	// Soft at the rim, solid through the middle. The edge is held just short of
	// 1 because smoothstep divides by (edge1 - edge0), so a softness of exactly
	// zero would divide by zero rather than give the hard rim it asks for.
	float cover = (1.0 - smoothstep(1.0 - max(softness, 0.001), 1.0, r))
		* tint.a;
	vec3 rgb = mix(tint.rgb, hot.rgb, pow(clamp(1.0 - r, 0.0, 1.0), hot_focus));
	// Premultiplied: the colour carries its own coverage, and ALPHA says only
	// how much of the background this fragment takes away.
	ALBEDO = rgb * cover;
	ALPHA = cover * occlude;
}
