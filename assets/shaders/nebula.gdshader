// A cloud bank, drawn as a sphere that gets thinner toward its own rim.
//
// The simulation's nebula is a circle on the combat plane and the rule that
// hides a ship is a path length through it (docs/13 section 2.1). This shader
// only has to LOOK like the thing that rule describes: densest through the
// middle, nothing at all at the edge, so a captain can see where the cost of
// crossing starts to bite instead of seeing a hard boundary.
//
// dot(NORMAL, VIEW) is 1 where the sphere faces the camera squarely, which is
// the middle of the disc it presents, and 0 at the silhouette. Raising it to a
// power controls how quickly the cloud falls off. That is the whole effect: no
// noise texture, no volumetric pass, nothing the gl_compatibility renderer the
// Web target needs cannot do.
//
// Additive rather than mixed, because a cloud lit from within adds light to
// what is behind it. depth_draw_never keeps it from occluding the ships that
// are inside it, and cull_disabled means the far wall contributes too, so a
// ship flying into the cloud is progressively washed out rather than popping.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 core : source_color = vec4(0.44, 0.70, 0.64, 1.0);
uniform vec4 rim : source_color = vec4(0.29, 0.42, 0.27, 1.0);
uniform float density : hint_range(0.0, 1.0) = 0.30;
uniform float falloff : hint_range(0.5, 6.0) = 2.2;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float depth = pow(facing, falloff);
	ALBEDO = mix(rim.rgb, core.rgb, depth);
	ALPHA = depth * density;
}
