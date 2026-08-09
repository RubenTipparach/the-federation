// 3D Pixelated Planet Shader, by Max Beier.
// https://godotshaders.com/shader/3d-pixelated-planet/
// CC0. Vendored unmodified for a trial (see LICENSE.md in this directory).
//
// It is canvas_item, like the Deep-Fold set we already ship, but it maps a real
// 3D volume onto the disc rather than scrolling a 2D field, so the terrain
// turns with the globe and compresses at the limb.
shader_type canvas_item;

uniform float pixelation : hint_range(0.0, 250.0, 0.001) = 150;
uniform float radius : hint_range(0.0, 0.5, 0.001) = 0.5;
uniform float rotate_x : hint_range(0.0, 180.0, 0.01) = 90.0;
uniform float rotate_y : hint_range(0.0, 360.0, 0.01) = 30;
uniform float rotation_speed: hint_range(0.0, 1.0, 0.001) = 0.01;
uniform vec3 sun_direction = vec3(1.0, 0.15, 0.0);
uniform float sun_strength= 2.7;
uniform sampler3D terrain_map;
uniform sampler2D terrain_colors;

mat3 rotateX(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat3(
		vec3(1, 0, 0),
		vec3(0, c, -s),
		vec3(0, s, c)
	);
}

mat3 rotateY(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat3(
		vec3(c, 0, s),
		vec3(0, 1, 0),
		vec3(-s, 0, c)
	);
}

void fragment() {
	vec2 original_uv = UV - vec2(0.5);
	vec2 centered_uv = original_uv;
	float original_dist = length(original_uv);

	// Apply pixelation to the entire UV space
	if (pixelation > 0.0) {
		centered_uv = floor(centered_uv * pixelation) / pixelation;
	}

	if (original_dist <= radius) {
		// Normalize UV coordinates
		vec2 normalized_uv = centered_uv / radius;

		// Convert UV to 3D point on sphere
		vec3 sphere_point = vec3(
			normalized_uv.x,
			sqrt(max(0.0, 1.0 - dot(normalized_uv, normalized_uv))),
			normalized_uv.y
		);

		// Apply X and Y axis rotations
		float rot_x_r = radians(rotate_x);
		float rot_y_r = radians(rotate_y + 360.0 * TIME * rotation_speed);
		mat3 rot_matrix_x = rotateX(rot_x_r);
		mat3 rot_matrix_y = rotateY(rot_y_r);
		vec3 rotated_point = rot_matrix_y * rot_matrix_x * sphere_point;

		vec3 sphere_point_rotated_by_player = rotateY(radians(rotate_y)) * rot_matrix_x * sphere_point;
		float light = dot(normalize(sphere_point_rotated_by_player / length(sphere_point_rotated_by_player)), normalize(sun_direction));
		// Dithering
		light = min(0.5, floor(light * 30.0) / 10.0) * sun_strength;

		// Sample terrain and color
		vec3 sample_point = rotated_point * 0.5 + 0.5;
		float terrain_value = texture(terrain_map, sample_point).r;
		vec4 terrain_color = texture(terrain_colors, vec2(terrain_value, 0.0));

		float edge_smoothness = fwidth(original_dist) * 2.0;
		float alpha = 1.0 - smoothstep(radius - edge_smoothness, radius, original_dist);

		COLOR = vec4(terrain_color.rgb * light, alpha);
	} else {
		COLOR = vec4(0.0);
	}
}
