shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Unreinforced concrete block wall: block grid, mortar, X-cracks from corners, branching
uniform vec3 base_color : source_color = vec3(0.7, 0.7, 0.7);
uniform vec3 crack_color : source_color = vec3(0.05, 0.05, 0.05);
uniform vec3 mortar_color : source_color = vec3(0.5, 0.48, 0.45);

uniform float crack_level : hint_range(0.0, 1.0) = 0.0;
uniform vec2 block_count = vec2(12.0, 8.0);  // blocks along UV
uniform float mortar_width : hint_range(0.01, 0.2) = 0.08;
uniform float crack_width : hint_range(0.002, 0.05) = 0.018;
uniform float seed = 0.0;

uniform vec3 impact_pos = vec3(0.0, 0.0, 0.0);
uniform float impact_falloff : hint_range(0.01, 2.0) = 0.12;

// Distance from point p to line through a and b (2D)
float dist_to_line(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float t = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * t);
}

// X-pattern: two diagonals (0,0)-(1,1) and (1,0)-(0,1)
float x_crack_lines(vec2 uv) {
	float d1 = dist_to_line(uv, vec2(0.0, 0.0), vec2(1.0, 1.0));
	float d2 = dist_to_line(uv, vec2(1.0, 0.0), vec2(0.0, 1.0));
	float d = min(d1, d2);
	// Add noise so crack isn't perfectly straight (through-block variation)
	float n = fract(sin(dot(uv * 80.0 + vec2(seed * 10.0, seed * 7.0), vec2(12.9898, 78.233))) * 43758.5453);
	d += (n - 0.5) * 0.015;
	return 1.0 - smoothstep(0.0, crack_width, d);
}

// Stair-step: crack prefers mortar joints (stronger along grid)
float mortar_mask(vec2 uv) {
	vec2 cell = floor(uv * block_count);
	vec2 in_cell = fract(uv * block_count);
	float near_edge_x = min(in_cell.x, 1.0 - in_cell.x);
	float near_edge_y = min(in_cell.y, 1.0 - in_cell.y);
	float mortar = 1.0 - smoothstep(mortar_width * 0.5, mortar_width, min(near_edge_x, near_edge_y));
	return mortar;
}

// Branching: secondary cracks that only show near main X-cracks
float hash12(vec2 p) {
	// Deterministic pseudo-random in [0,1)
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float branch_cracks(vec2 uv, float main_crack) {
	// Spider-web variation without relying on `noise()` overloads.
	vec2 p = uv * 25.0 + vec2(seed * 3.0, seed * 2.0);
	float n = hash12(p);
	float n2 = hash12(p + vec2(11.3, 7.1) + vec2(seed * 0.5, seed * 1.7));
	float branch = step(0.72, n) * step(0.65, n2);
	// Only branch where main crack is present (within crack_width)
	return branch * main_crack;
}

void fragment() {
	vec2 uv = UV;
	vec2 cell = floor(uv * block_count);
	vec2 in_cell = fract(uv * block_count);

	// Mortar lines (darker at block boundaries)
	float near_x = min(in_cell.x, 1.0 - in_cell.x);
	float near_y = min(in_cell.y, 1.0 - in_cell.y);
	float mortar = 1.0 - smoothstep(mortar_width * 0.5, mortar_width, min(near_x, near_y));

	// X-pattern cracks from corners toward center (with procedural wobble)
	float x_crack = x_crack_lines(uv);
	float mortar_prefer = mortar_mask(uv);
	// Cracks are stronger along mortar (stair-step effect)
	float main_crack = x_crack * (0.35 + 0.65 * mortar_prefer);
	main_crack = min(1.0, main_crack);

	// Branching / spider-web
	float branch = branch_cracks(uv, min(1.0, main_crack * 2.0));
	float crack_combined = min(1.0, main_crack + branch * 0.7);

	// Impact falloff: more damage near impact
	float dist = distance(NODE_POSITION_WORLD, impact_pos);
	float impact = exp(-dist * impact_falloff);
	float mask = crack_combined * (0.35 + 0.65 * impact);

	// Progressive reveal by crack_level
	float crack_opacity = smoothstep(0.02, 0.35, mask * crack_level * 1.5);

	// Base: mortar shows as darker first, then cracks
	vec3 base = mix(base_color, mortar_color, mortar * 0.5);
	ALBEDO = mix(base, crack_color, crack_opacity);
	ROUGHNESS = 0.95;
	SPECULAR = 0.06;
}
