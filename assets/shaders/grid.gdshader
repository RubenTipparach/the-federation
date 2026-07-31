// The battle plane. Grid lines drawn in the fragment shader on an authored
// unit quad (assets/meshes/quad.obj): the geometry is a committed file, the
// shader is presentation, so CLAUDE.md section 5.1 is respected.
// The perspective convergence of this grid is what sells the 3D view.
shader_type spatial;
// Transparent, so the starfield behind it shows through the whole plane and
// the grid reads as lines ruled across space rather than as a lid over it.
//
// This was opaque before, because writing ALPHA puts the quad in the
// transparent queue, where it sorts by origin distance and occluded any
// overlay whose origin was farther from the camera than the grid's center.
// Observed then: the player's shield ring vanished while the enemy's
// rendered. Painting an opaque base was a way around that, and it stopped
// being an option once there was a sky worth seeing.
//
// The real fix is render_priority, set to -1 on assets/materials/mat_grid.tres.
// Godot sorts transparent surfaces by priority BEFORE distance, so the grid is
// always drawn first no matter where the ships are, and every overlay blends
// on top of it. That is a structural guarantee rather than a lucky ordering.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform vec4 line_color : source_color = vec4(0.12, 0.20, 0.28, 0.55);
uniform float cell_size = 5.0;
uniform float line_width = 0.05;
uniform float fade_radius = 58.0;

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 g = abs(fract(wp.xz / cell_size - 0.5) - 0.5) * cell_size;
	float d = min(g.x, g.y);
	float aa = fwidth(d);
	float line = 1.0 - smoothstep(line_width, line_width + aa, d);
	float fade = 1.0 - smoothstep(fade_radius * 0.55, fade_radius, length(wp.xz));
	ALBEDO = line_color.rgb;
	ALPHA = line * line_color.a * fade;
}
