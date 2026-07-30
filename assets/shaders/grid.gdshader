// The battle plane. Grid lines drawn in the fragment shader on an authored
// unit quad (assets/meshes/quad.obj): the geometry is a committed file, the
// shader is presentation, so CLAUDE.md section 5.1 is respected.
// The perspective convergence of this grid is what sells the 3D view.
shader_type spatial;
// Opaque on purpose: writing ALPHA would put this huge quad in the transparent
// queue, where it sorts by origin distance and occludes any overlay whose
// origin is farther from the camera than the grid's center. Observed: the
// player's shield ring vanished while the enemy's rendered. Opaque geometry
// depth tests correctly against the y lifted overlays instead.
render_mode unshaded, cull_disabled;

uniform vec4 line_color : source_color = vec4(0.12, 0.20, 0.28, 0.55);
uniform vec4 base_color : source_color = vec4(0.024, 0.04, 0.06, 1.0);
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
	ALBEDO = mix(base_color.rgb, line_color.rgb, line * line_color.a * fade);
}
