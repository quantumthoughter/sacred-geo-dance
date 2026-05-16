shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

// Energy orb — Fresnel rim glow + internal pulse
// No scene lighting: pure self-illuminated sacred light

uniform vec4 albedo : source_color = vec4(1.0, 0.5, 1.0, 1.0);
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.2;
uniform float pulse_speed : hint_range(0.0, 10.0) = 4.0;
uniform float pulse_amp : hint_range(0.0, 0.5) = 0.12;
uniform float base_brightness : hint_range(0.5, 3.0) = 1.3;

void fragment() {
	// Fresnel — edge glow
	vec3 view_dir = normalize(VIEW - MODEL_MATRIX[3].xyz);
	vec3 nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fresnel = 1.0 - abs(dot(normalize(view_dir), nrm));
	fresnel = pow(fresnel, fresnel_power);

	// Inner energy pulse
	float pulse = 1.0 + sin(TIME * pulse_speed + MODEL_MATRIX[3].x * 0.5 + MODEL_MATRIX[3].z * 0.3) * pulse_amp;

	// Blend inner glow → edge glow
	vec3 inner = albedo.rgb * 0.7;
	vec3 rim = albedo.rgb * 2.5;
	vec3 color = mix(inner, rim, fresnel) * pulse * base_brightness;

	ALBEDO = color;
	EMISSION = color * 1.5;
	ALPHA = 0.85 + fresnel * 0.15;
}
