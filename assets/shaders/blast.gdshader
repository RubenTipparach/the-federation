// The fireball a ship leaves behind.
//
// One sphere, scaled up and faded out by the wreck script. The shader does two
// things the scale cannot: it keeps the ball brightest through its middle, so
// it reads as a volume of burning gas rather than a painted balloon, and it
// shifts colour as it dies, from a white hot core through the palette's alert
// orange to nothing.
//
// Additive and depth_draw_never, so it lights up whatever is behind it instead
// of cutting a hole in the scene, and cull_disabled so the far wall of the ball
// contributes as it expands past the camera.
//
// Everything here runs on gl_compatibility, which the Web target requires.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 core : source_color = vec4(0.85, 0.72, 0.40, 1.0);
uniform vec4 edge : source_color = vec4(0.92, 0.42, 0.33, 1.0);
// 0 at the moment of the kill, 1 when the fire is out. The wreck drives it.
uniform float progress : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float depth = pow(facing, 2.4);
	// White hot at the start, angry at the end, and the rim always cooler than
	// the middle.
	ALBEDO = mix(mix(core.rgb, edge.rgb, progress), edge.rgb, 1.0 - depth);
	// Flashes to full almost instantly, then falls away over the rest of the
	// life: an explosion is a sharp attack and a long decay.
	float envelope = min(1.0, progress * 14.0) * pow(1.0 - progress, 1.7);
	ALPHA = depth * envelope;
}
