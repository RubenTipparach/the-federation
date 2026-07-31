// The flare behind a shield facing that has just been hit.
//
// One authored unit mesh (assets/meshes/arc_glow.obj), instanced six times per
// ship and rotated into its facing by src/ui/ship_rig.gd. Geometry is a
// committed file and this shader only paints it, so CLAUDE.md section 5.1 is
// respected the same way the grid and sky shaders are.
//
// Additive on purpose. The mesh spans 88 degrees where a facing owns 60, so
// neighbouring flares overlap by 14 degrees on each side; adding them means
// two facings hit at once read as one bright lobe across the shared edge
// instead of two panels meeting at a seam. Additive also means the flare
// never darkens the starfield behind it, only lights it.
//
// The falloff is what sells the blend. Angularly the flare is brightest at the
// centre of its facing and reaches zero exactly at the ends of the mesh, so an
// overlapping pair crosses over smoothly. Radially it fades at both edges so
// the band has no hard rim.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never;

uniform vec4 flare_color : source_color = vec4(0.55, 0.93, 1.0, 1.0);
// How much of the mesh's half width the flare fills before it has faded out.
uniform float arc_half_deg = 44.0;
// Higher concentrates the flare on the struck facing; lower spreads it wider
// into its neighbours.
uniform float arc_falloff = 1.6;
uniform float inner_radius = 0.66;
uniform float outer_radius = 1.12;
uniform float edge_soft = 0.13;
// Driven per instance by the rig: 1 at the moment of impact, decaying to 0.
uniform float glow = 0.0;

varying vec3 v_model;

void vertex() {
	// VERTEX is model space here, which is what the falloff needs: the mesh is
	// authored centred on +Z, so the angle off +Z is the angle along the arc
	// regardless of how the instance has been rotated into its facing.
	v_model = VERTEX;
}

void fragment() {
	float ang = degrees(atan(v_model.x, v_model.z));
	float across = clamp(1.0 - abs(ang) / arc_half_deg, 0.0, 1.0);
	across = pow(across, arc_falloff);

	float r = length(v_model.xz);
	float radial = smoothstep(inner_radius, inner_radius + edge_soft, r)
			* (1.0 - smoothstep(outer_radius - edge_soft, outer_radius, r));

	ALBEDO = flare_color.rgb;
	ALPHA = glow * across * radial * flare_color.a;
}
