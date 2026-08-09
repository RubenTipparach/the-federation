// 3D Pixelated Planet Shader by Max Beier (CC0), with the five changes this
// project's rules force. The unmodified original is beside it as
// pixel_planet_3d.gdshader so the difference stays one readable diff.
//
//   1. THE COLOUR IS LOOKED UP, NEVER MULTIPLIED. The original does
//      `terrain_color.rgb * light`, and a palette entry multiplied by 0.7 is
//      not a palette entry (CLAUDE.md 3.1). Here the terrain value and the
//      light band index a table whose every slot is a Waldgeist entry, so
//      shading picks a different palette colour rather than dimming one. The
//      table is a uniform array rather than a texture for the same reason
//      Deep-Fold's shaders take one: a colour handed over as a uniform arrives
//      exactly as it was written, with no sampler or colour space in the way.
//   2. THE LIMB IS A HARD PIXEL EDGE. The original antialiases the disc with
//      fwidth and smoothstep, which blends the rim against the void and invents
//      colours there. The disc test uses the pixelated coordinate and the alpha
//      is a step, so the edge is made of whole art pixels.
//   3. THE LIGHT IS BANDED EXPLICITLY. The original's `min(0.5, floor(light *
//      30.0) / 10.0) * sun_strength` is a quantise chosen to look right when
//      multiplied. Bands are what index the table here, so the count is a
//      uniform and each band is a row of authored colour.
//   4. THE BAND EDGE IS DITHERED. Four flat bands on a sphere read as four
//      stripes. A 4x4 ordered dither at ART pixel resolution picks between the
//      two neighbouring bands along the boundary, which is what Deep-Fold's
//      shaders do and what makes this look like the rest of the game's art. It
//      chooses between two palette entries, so it cannot invent a third.
//   5. THE SUN IS FIXED IN SCREEN SPACE. The original lights the surface from
//      the point AFTER the viewer's rotation is applied, so turning the globe
//      turns the terminator with it. Here the lit fraction comes from the raw
//      sphere normal, which is the screen facing one, so the sun stays up and
//      to the left while the terrain rotates past it. That is the convention
//      src/ui/pixel_planet.gd already uses and the reason it gives: a
//      terminator that swings with the camera draws the eye to the camera
//      rather than to the fight.
shader_type canvas_item;

// The table is STEPS terrain values wide and BANDS light levels deep. Both are
// compile time here because GLSL wants a fixed array size; the script fills
// what it uses and leaves the rest.
const int STEPS = 8;
const int BANDS = 4;

uniform float pixelation : hint_range(0.0, 250.0, 0.001) = 100.0;
uniform float radius : hint_range(0.0, 0.5, 0.001) = 0.5;
uniform float rotate_x : hint_range(0.0, 180.0, 0.01) = 90.0;
uniform float rotate_y : hint_range(0.0, 360.0, 0.01) = 30.0;
uniform float rotation_speed : hint_range(0.0, 1.0, 0.001) = 0.0;
uniform vec3 sun_direction = vec3(1.0, 0.15, 0.0);
uniform sampler3D terrain_map;
// Row major: band * STEPS + step. Row 0 is full sun, the last row is night.
uniform vec4 table[STEPS * BANDS];
// The lit fraction is a straight remap of the sun dot product: at or below
// light_min the ground is night, at or above light_max it is full sun. Two
// ends of a range rather than a centre and a width, because what a person
// tuning this wants to say is "the shadow starts here".
uniform float light_min : hint_range(-1.0, 1.0, 0.01) = -0.25;
uniform float light_max : hint_range(-1.0, 1.0, 0.01) = 0.8;

// A 4x4 ordered dither, as the fraction of a cell that should take the darker
// of two bands. Written as a lookup rather than a matrix because GLSL ES has no
// constant array indexing guarantees worth relying on here.
float bayer(vec2 cell) {
	vec2 c = mod(cell, 4.0);
	int i = int(c.x) + int(c.y) * 4;
	float v = 0.0;
	if (i == 0) { v = 0.0; } else if (i == 1) { v = 8.0; }
	else if (i == 2) { v = 2.0; } else if (i == 3) { v = 10.0; }
	else if (i == 4) { v = 12.0; } else if (i == 5) { v = 4.0; }
	else if (i == 6) { v = 14.0; } else if (i == 7) { v = 6.0; }
	else if (i == 8) { v = 3.0; } else if (i == 9) { v = 11.0; }
	else if (i == 10) { v = 1.0; } else if (i == 11) { v = 9.0; }
	else if (i == 12) { v = 15.0; } else if (i == 13) { v = 7.0; }
	else if (i == 14) { v = 13.0; } else { v = 5.0; }
	return v / 16.0;
}

mat3 rotateX(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat3(vec3(1, 0, 0), vec3(0, c, -s), vec3(0, s, c));
}

mat3 rotateY(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat3(vec3(c, 0, s), vec3(0, 1, 0), vec3(-s, 0, c));
}

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	vec2 cell = floor(centered_uv * pixelation);
	if (pixelation > 0.0) {
		centered_uv = (cell + 0.5) / pixelation;
	}
	// Change 2: the disc is tested on the pixelated coordinate, so the limb is
	// whole art pixels rather than a smooth curve with a soft fringe.
	if (length(centered_uv) > radius) {
		COLOR = vec4(0.0);
	} else {
		vec2 normalized_uv = centered_uv / radius;
		vec3 sphere_point = vec3(
			normalized_uv.x,
			sqrt(max(0.0, 1.0 - dot(normalized_uv, normalized_uv))),
			normalized_uv.y);

		float rot_x_r = radians(rotate_x);
		float rot_y_r = radians(rotate_y + 360.0 * TIME * rotation_speed);
		vec3 rotated_point = rotateY(rot_y_r) * rotateX(rot_x_r) * sphere_point;

		// Changes 3 and 5: the lit fraction comes from the screen facing normal,
		// then a band index.
		float light = dot(sphere_point, normalize(sun_direction));
		float lit = clamp((light - light_min) / max(0.001, light_max - light_min),
			0.0, 1.0);
		// Change 4: the boundary between two bands is dithered at art pixel
		// resolution rather than falling on one hard line.
		float level = (1.0 - lit) * float(BANDS);
		float stepped = floor(level) + step(bayer(cell), fract(level));
		int band = int(clamp(stepped, 0.0, float(BANDS - 1)));

		vec3 sample_point = rotated_point * 0.5 + 0.5;
		float terrain_value = clamp(texture(terrain_map, sample_point).r, 0.0, 0.999);
		int step_index = int(terrain_value * float(STEPS));

		// Change 1: the shaded colour is looked up, not computed.
		COLOR = vec4(table[band * STEPS + step_index].rgb, 1.0);
	}
}
