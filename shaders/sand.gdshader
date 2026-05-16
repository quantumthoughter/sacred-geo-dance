shader_type spatial;
render_mode blend_add, cull_disabled, unshaded;

// ── Micronized Sand Particle Shader ──
// Tiny glowing grains with soft falloff and energy response

uniform vec4 albedo : source_color = vec4(1.0, 0.7, 0.3, 1.0);
uniform float energy : hint_range(0.0, 3.0) = 1.0;
uniform float grain_size : hint_range(0.3, 1.5) = 0.7;

void fragment() {
	float d = length(UV - 0.5) * 2.0 / grain_size;
	float core = exp(-d * d * 12.0) * 0.5;
	float glow = exp(-d * d * 3.0) * 0.4;
	float alpha = (core + glow) * (0.6 + energy * 0.4);
	vec3 color = albedo.rgb * (0.8 + energy * 0.7);
	ALBEDO = color;
	EMISSION = color * 2.5 * energy;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
