shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

// ── KALEIDOSCOPE + DISSOLVE + ORGANIC BORDERS ──
// Image Magic Shader — mirror symmetry, audio-driven dissolve, lotus vignette

uniform sampler2D image_tex : source_color;
uniform float mirror_segments : hint_range(2, 24) = 8;
uniform float rotation : hint_range(0, 6.28) = 0.0;
uniform float zoom : hint_range(0.2, 3.0) = 1.0;
uniform float dissolve : hint_range(0.0, 1.0) = 1.0;
uniform float edge_softness : hint_range(0.01, 1.0) = 0.3;
uniform float beat : hint_range(0.0, 2.0) = 0.0;
uniform float sparkle : hint_range(0.0, 1.0) = 0.0;

// Pseudo-noise for dissolve
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
	           mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// Center UV
	vec2 uv = UV - 0.5;

	// Zoom
	uv /= zoom;

	// Kaleidoscope — mirror radial segments
	float angle = atan(uv.y, uv.x) + rotation;
	float segment_angle = TAU / mirror_segments;
	float folded_angle = mod(angle, segment_angle * 2.0);
	if (folded_angle > segment_angle) {
		folded_angle = segment_angle * 2.0 - folded_angle;
	}
	float radius = length(uv);
	vec2 kaleido_uv = vec2(cos(folded_angle), sin(folded_angle)) * radius;

	// Map back to 0..1 for texture lookup, with repetition
	kaleido_uv = fract(kaleido_uv + 0.5);

	// Sample texture
	vec4 tex_color = texture(image_tex, kaleido_uv);

	// ── Organic lotus border (vignette) ──
	// Distance from center creates a soft lotus-like shape
	float d = length(uv) * 2.0;
	// Petal-like modulation around the edge
	float petal = 1.0 + sin(angle * mirror_segments) * 0.15;
	float border_dist = d * petal;
	// Soft falloff at edges
	float border = 1.0 - smoothstep(0.6, 0.95, border_dist);
	border = pow(border, edge_softness * 5.0);

	// ── Audio-reactive dissolve ──
	// Noise-based dissolve pattern
	float n = noise(kaleido_uv * 8.0 + TIME * 0.2) * 0.6;
	n += noise(kaleido_uv * 4.0 - TIME * 0.15) * 0.4;
	float dissolve_threshold = 1.0 - dissolve;
	float dissolve_mask = smoothstep(dissolve_threshold - 0.15, dissolve_threshold + 0.15, n);

	// ── Sparkle on beat ──
	float spark = 0.0;
	if (sparkle > 0.0) {
		float s = hash(fract(kaleido_uv * 20.0 + TIME * 0.5));
		spark = smoothstep(0.92, 1.0, s) * sparkle * 3.0 * beat;
	}

	// Combine
	float alpha = tex_color.a * border * dissolve_mask;
	vec3 color = tex_color.rgb * (1.0 + beat * 0.3) + vec3(1.0, 0.9, 0.7) * spark;

	ALBEDO = color;
	EMISSION = color * (0.5 + beat * 1.0);
	ALPHA = alpha;
}
