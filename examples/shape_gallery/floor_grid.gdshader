shader_type spatial;
// Original world-space metric grid on the existing box, not an extra surface.
uniform vec4 base_color : source_color = vec4(0.25, 0.28, 0.32, 1.0);
uniform vec4 line_color : source_color = vec4(0.34, 0.37, 0.41, 1.0);
uniform float spacing_m : hint_range(0.1, 10.0) = 1.0;
uniform float line_width_m : hint_range(0.001, 0.1) = 0.015;
varying vec3 world_position;
varying vec3 world_normal;
void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec2 distance_m = abs(fract(world_position.xz / spacing_m + 0.5) - 0.5) * spacing_m;
	vec2 aa = max(fwidth(world_position.xz), vec2(0.0001));
	vec2 coverage = 1.0 - smoothstep(vec2(line_width_m * 0.5) - aa, vec2(line_width_m * 0.5) + aa, distance_m);
	float line = max(coverage.x, coverage.y) * step(0.9, world_normal.y);
	ALBEDO = mix(base_color.rgb, line_color.rgb, line);
	ROUGHNESS = 0.85;
}
