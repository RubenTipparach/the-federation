// A camera facing sprite for weapon effects: the photon torpedo's star and the
// puffs of a drone's exhaust plume.
//
// Geometry, not a texture. Everything in the tactical view except the painted
// hulls is untextured tinted geometry, and a committed star mesh is crisp at
// every zoom where a magnified pixel sprite is not. The sprite sheet this
// replaced also hit a sampling fault under the compatibility renderer that a
// flat tint sidesteps entirely.
//
// Billboarding is done here rather than with BaseMaterial3D's billboard flag
// because every other overlay in this game is a ShaderMaterial, and a second
// material system for two meshes would be the divergence CLAUDE.md 4.1
// forbids. The scale the node was given is kept, so the view sizes an effect
// in sim units the same way it sizes everything else.
//
// Additive, because both users are light: a photon core and burning exhaust.
//
// Runs on gl_compatibility, which the Web export requires.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Turn about the sprite's own axis, in radians. It has to happen here rather
// than as a node rotation, because billboarding throws the model's basis away
// and keeps only its scale, so a spin set on the node would never survive.
uniform float spin = 0.0;

void vertex() {
	float s = sin(spin);
	float c = cos(spin);
	VERTEX.xy = mat2(vec2(c, -s), vec2(s, c)) * VERTEX.xy;

	// Face the camera, keep the node's scale. INV_VIEW_MATRIX's basis is the
	// camera's orientation in world space, so borrowing its three axes and
	// keeping the model's translation is exactly "turn to face the viewer".
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mat4 keep_scale = mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * facing * keep_scale;
}

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
