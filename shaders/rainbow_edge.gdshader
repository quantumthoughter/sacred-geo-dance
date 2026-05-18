shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

// ── Rainbow Edge Shader ──
// Scrolling hue waves along cylinder length, Fresnel rim glow, beat-reactive flash
// Three parallax aurora layers for rich flowing rainbow effect

uniform float time_offset : hint_range(0.0, 6.28) = 0.0;
uniform float scroll_speed : hint_range(0.0, 5.0) = 1.2;
uniform float brightness : hint_range(0.5, 5.0) = 1.8;
uniform float beat : hint_range(0.0, 2.0) = 0.0;
uniform float hue_offset : hint_range(0.0, 1.0) = 0.0;

vec3 hsv2rgb(vec3 c) {
	vec4 K = vec4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
	vec3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
	return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

void fragment() {
	float t = TIME + time_offset;

	// Layer 1 — Fast aurora ripple
	float h1 = fract(UV.y * 2.5 + t * scroll_speed * 1.8 + hue_offset);
	// Layer 2 — Medium flowing wave
	float h2 = fract(UV.y * 1.2 - t * scroll_speed * 0.7 + hue_offset * 0.6);
	// Layer 3 — Slow deep base hue shift
	float h3 = fract(UV.y * 0.4 + t * scroll_speed * 0.2 + hue_offset * 0.3);

	float hue = h1 * 0.35 + h2 * 0.4 + h3 * 0.25;
	float sat = 0.82 + beat * 0.14;
	float val = 0.72 + beat * 0.28;

	vec3 rgb = hsv2rgb(vec3(hue, sat, val));

	// Fresnel rim glow — edges of the cylinder shine brighter
	vec3 view_dir = normalize(VIEW - MODEL_MATRIX[3].xyz);
	vec3 nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float rim = 1.0 - abs(dot(normalize(view_dir), nrm));
	rim = pow(rim, 3.0);

	vec3 color = mix(rgb * 0.75, rgb * 2.6, rim) * brightness;
	color *= 1.0 + beat * 0.6;

	ALBEDO = color;
	EMISSION = color * 1.4;
	ALPHA = 0.6 + rim * 0.35 + beat * 0.08;
}
