// Flat tint for tactical overlays (wedges, shield segments, rings, beams).
// Unshaded and double sided: overlays are information, not lit surfaces.
// Runs on the gl_compatibility renderer, which the Web target requires.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
