// The air around a world: a shell slightly larger than the planet, glowing
// only where you are looking through it edge on.
//
// This is the trick that makes a shaded ball read as a planet rather than as a
// ball. dot(NORMAL, VIEW) is near 1 through the middle of the disc, where you
// are looking down through the thinnest column of air, and near 0 at the rim,
// where the line of sight runs the long way through it. Inverting that and
// raising it to a power gives a bright band hugging the silhouette.
//
// cull_front is what keeps it honest: only the FAR wall of the shell is drawn,
// so the glow sits behind the planet's own surface and rings it instead of
// veiling it. Additive and depth_draw_never for the same reason.
//
// Runs on gl_compatibility, which the Web target requires.
shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never;

uniform vec4 tint : source_color = vec4(0.49, 0.66, 0.81, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.75;
// Higher means a tighter band right on the silhouette; lower spreads the haze
// further across the disc.
uniform float falloff : hint_range(0.5, 8.0) = 3.0;

void fragment() {
	// The normal points inward on a front culled shell, so it is flipped back
	// before the rim is measured.
	float facing = clamp(dot(normalize(-NORMAL), normalize(VIEW)), 0.0, 1.0);
	float rim = pow(1.0 - facing, falloff);
	ALBEDO = tint.rgb;
	ALPHA = rim * strength;
}
