shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

// Glow edge — thin luminous line, no lighting

uniform vec4 albedo : source_color = vec4(0.4, 0.5, 1.0, 1.0);
uniform float brightness : hint_range(0.5, 3.0) = 1.5;

void fragment() {
	vec3 color = albedo.rgb * brightness;
	ALBEDO = color;
	EMISSION = color * 1.4;
	ALPHA = 0.7;
}
