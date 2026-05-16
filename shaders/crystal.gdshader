shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

// ── Diamond-Cut Crystal Orb Shader ──
// Faceted gem look with rainbow dispersion, internal fire, beat-reactive sparkle

uniform vec4 albedo : source_color = vec4(1.0, 0.6, 1.0, 1.0);
uniform float fresnel_power : hint_range(1.0, 5.0) = 2.8;
uniform float dispersion : hint_range(0.0, 1.0) = 0.45;
uniform float internal_fire : hint_range(0.0, 1.0) = 0.5;
uniform float sparkle : hint_range(0.0, 1.0) = 0.3;
uniform float brightness : hint_range(0.5, 4.0) = 1.8;
uniform float beat : hint_range(0.0, 2.0) = 0.0;
uniform float time_offset : hint_range(0.0, 6.28) = 0.0;

// Hash for sparkle
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float hash3D(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3D(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash3D(i), hash3D(i + vec3(1,0,0)), f.x),
			mix(hash3D(i + vec3(0,1,0)), hash3D(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3D(i + vec3(0,0,1)), hash3D(i + vec3(1,0,1)), f.x),
			mix(hash3D(i + vec3(0,1,1)), hash3D(i + vec3(1,1,1)), f.x), f.y),
		f.z
	);
}

void vertex() {
	// Beat-reactive faceted expansion
	float expand = beat * 0.04;
	VERTEX += NORMAL * expand * (0.5 + 0.5 * sin(VERTEX.x * 8.0 + TIME * 2.0));
}

void fragment() {
	vec3 world_pos = MODEL_MATRIX[3].xyz;
	vec3 view_dir = normalize(VIEW - world_pos);
	vec3 nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Base Fresnel
	float fresnel = 1.0 - abs(dot(normalize(view_dir), nrm));

	// Rainbow dispersion — RGB channels refract at different angles
	float f_r = pow(fresnel, fresnel_power * (1.0 - dispersion * 0.15));
	float f_g = pow(fresnel, fresnel_power);
	float f_b = pow(fresnel, fresnel_power * (1.0 + dispersion * 0.15));

	// Internal fire — noise-based inner glow
	float fire_n = noise3D(world_pos * 2.5 + TIME * 0.3) * internal_fire;
	float fire = 0.4 + fire_n * 0.6;

	// Sparkle — bright specks on facets
	float s1 = hash(fract(world_pos.xy * 12.0 + TIME * 0.1));
	float s2 = hash(fract(world_pos.yz * 12.0 - TIME * 0.07));
	float sp = smoothstep(0.85, 1.0, s1) * smoothstep(0.85, 1.0, s2) * sparkle;
	sp *= 1.0 + beat * 3.0;

	// Build color with dispersion
	vec3 inner = albedo.rgb * fire * 0.6;
	vec3 edge_r = vec3(1.0, 0.3, 0.3) * albedo.rgb * f_r * 1.8;
	vec3 edge_g = vec3(0.3, 1.0, 0.3) * albedo.rgb * f_g * 0.3;
	vec3 edge_b = vec3(0.3, 0.3, 1.0) * albedo.rgb * f_b * 1.2;
	vec3 rim = edge_r + edge_g + edge_b;

	vec3 color = mix(inner, rim, fresnel) * brightness;
	color += vec3(1.0, 0.95, 0.8) * sp * 2.0;  // white sparkle overlay

	// Beat boost
	color *= 1.0 + beat * 0.4;

	ALBEDO = color;
	EMISSION = color * 1.3;
	ALPHA = 1.0;
}
