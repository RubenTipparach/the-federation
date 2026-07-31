// The starfield behind the battle: a voronoi star field over an fbm nebula.
//
// Nothing here is authored geometry, so CLAUDE.md section 5.1 is not in play:
// this is a material on the scene's authored Environment, the same shape as
// the grid shader next to it. Presentation only, no gameplay state.
//
// On color (CLAUDE.md section 3.1). A sky shader that mixed its own colors
// would put thousands of invented shades on screen. This one never blends:
// every branch SELECTS a step from assets/textures/sky_ramps.png, baked from
// data/palette.json by tools/gen_ramps.py and sampled with nearest filtering.
// So the sky is drawn from exactly the palette the ships are painted in, and
// it bands the way hand painted pixel art does instead of dissolving into a
// gradient. mix() appears once, with a step() weight, which is a select and
// not an interpolation.
//
// What COLOR emits is therefore always a palette entry. What lands in the
// framebuffer is that entry after the engine's sRGB encode, which measures a
// few 8 bit levels off (black reads 5,12,19 rather than 11,16,22). The ship
// textures move by the same amount through the same pipeline, so the sky and
// the hulls stay consistent with each other; the discipline is on what we
// author, not on what the swap chain hands back.
//
// The stars are true voronoi: space is diced into cells, most cells are empty
// (a per cell hash gates on density), and a surviving cell holds one feature
// point placed by hash. Brightness is distance to that point, so stars keep
// their own spacing instead of clumping the way independent random dots do.
// Two layers give parallax depth: sparse near stars with a visible faint
// step around them, dense far ones that read as dust.
shader_type sky;

uniform sampler2D ramps : source_color, filter_nearest, repeat_disable;

// The sky is drawn in chunky texels to match the ships rather than in smooth
// per pixel detail. Raising this makes the sky finer grained.
uniform float quantize = 420.0;

// Nebula. floor discards everything below it so most of the sky stays empty,
// and contrast pushes what survives toward the ramp's dark end. warp is the
// domain warp strength: without it the cloud reads as smooth islands, with it
// the bands tear into filaments, which is what makes it look like gas.
uniform float nebula_scale = 6.5;
uniform float nebula_floor = 0.40;
uniform float nebula_contrast = 1.6;
uniform float nebula_warp = 0.7;
// Which of the two clouds a region of sky belongs to, chosen by a much
// coarser noise field. Keep this low: it should change over a whole sky, not
// within one view, or the two clouds interleave into plaid.
uniform float nebula_mix_scale = 1.7;
uniform float nebula_warm_bias = 0.5;

// Star layers, in cells per unit direction. density is the fraction of cells
// holding a star; radius is the star's size in cell widths.
uniform float near_scale = 95.0;
uniform float near_density = 0.08;
uniform float near_radius = 0.26;
uniform float far_scale = 210.0;
uniform float far_density = 0.1;
uniform float far_radius = 0.3;

// Brightness at which a cell's point becomes a lit star, and the lower one at
// which it becomes that star's faint outer step.
uniform float star_cut = 0.3;
uniform float star_dim_cut = 0.06;

const float ROW_NEBULA_COOL = 0.0;
const float ROW_NEBULA_WARM = 1.0;
const float ROW_STAR_DIM = 2.0;
const float ROW_STAR = 3.0;

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

vec3 hash33(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.xxy + p.yxx) * p.zyx);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
			mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		sum += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

// Domain warp: look the cloud up at a position that has itself been pushed
// around by noise. Cheap, and it is the difference between banded blobs and
// something that looks like it is drifting.
float nebula_density(vec3 p) {
	vec3 warp = vec3(vnoise(p + 3.17), vnoise(p + 7.71), vnoise(p + 13.31));
	return fbm(p + (warp - 0.5) * nebula_warp);
}

// One voronoi star layer. Returns the brightest star covering this point and
// writes the ramp index of the cell that produced it, so a star's faint step
// is a darker shade of its own color.
float star_layer(vec3 p, float density, float radius, out float tint) {
	vec3 base = floor(p);
	float best = 0.0;
	tint = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 cell = base + vec3(float(x), float(y), float(z));
				float seed = hash13(cell);
				if (seed > density) {
					continue;
				}
				vec3 point = cell + hash33(cell + 19.19);
				float b = clamp(1.0 - length(p - point) / radius, 0.0, 1.0);
				b *= b;
				if (b > best) {
					best = b;
					tint = fract(seed * 97.13);
				}
			}
		}
	}
	return best;
}

// Pick a step from a ramp row. Never interpolates: the texture is sampled
// nearest, so what comes back is one palette entry.
vec3 ramp(float row, float t) {
	vec2 size = vec2(textureSize(ramps, 0));
	float u = (floor(clamp(t, 0.0, 0.9999) * size.x) + 0.5) / size.x;
	return texture(ramps, vec2(u, (row + 0.5) / size.y)).rgb;
}

void sky() {
	// Snap the view direction to a grid so the sky is drawn in blocks that
	// sit still against the stars, rather than in screen pixels that would
	// swim as the camera turns.
	vec3 dir = (floor(EYEDIR * quantize) + 0.5) / quantize;

	// Nebula: density chooses the step, a second much larger noise field
	// chooses which of the two clouds this part of the sky belongs to.
	float density = nebula_density(dir * nebula_scale + vec3(11.3, 5.7, 23.1));
	density = clamp((density - nebula_floor) / max(0.001, 1.0 - nebula_floor),
			0.0, 1.0);
	density = pow(density, nebula_contrast);
	float warm = step(nebula_warm_bias,
			vnoise(dir * nebula_mix_scale + vec3(41.0)));
	vec3 col = mix(ramp(ROW_NEBULA_COOL, density),
			ramp(ROW_NEBULA_WARM, density), warm);

	float near_tint;
	float far_tint;
	float near = star_layer(dir * near_scale, near_density, near_radius,
			near_tint);
	float far = star_layer(dir * far_scale, far_density, far_radius, far_tint);
	float bright = max(near, far);
	float tint = near >= far ? near_tint : far_tint;

	if (bright > star_cut) {
		col = ramp(ROW_STAR, tint);
	} else if (bright > star_dim_cut) {
		col = ramp(ROW_STAR_DIM, tint);
	}
	COLOR = col;
}
