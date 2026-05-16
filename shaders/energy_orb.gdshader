shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

// Energy orb — Fresnel rim glow, internal noise swirl, beat-reactive displacement
// No scene lighting: pure self-illuminated sacred light

uniform vec4 albedo : source_color = vec4(1.0, 0.5, 1.0, 1.0);
uniform float fresnel_power : hint_range(0.5, 5.0) = 2.2;
uniform float pulse_speed : hint_range(0.0, 10.0) = 4.0;
uniform float pulse_amp : hint_range(0.0, 0.5) = 0.12;
uniform float base_brightness : hint_range(0.5, 3.0) = 1.3;
uniform float beat : hint_range(0.0, 2.0) = 0.0;
uniform float swirl_speed : hint_range(0.0, 3.0) = 0.7;
uniform float noise_scale : hint_range(0.5, 5.0) = 2.2;

// Pseudo-noise hash
float hash3D(vec3 p) {
	float h = dot(p, vec3(127.1, 311.7, 74.7));
	return fract(sin(h) * 43758.5453);
}

// Smooth 3D value noise
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

// FBM (fractal brownian motion) for rich nebula texture
float fbm(vec3 p) {
	float val = 0.0;
	float amp = 0.6;
	float freq = 1.0;
	for (int i = 0; i < 3; i++) {
		val += amp * noise3D(p * freq);
		freq *= 2.2;
		amp *= 0.5;
	}
	return val;
}

void vertex() {
	// Beat-reactive vertex displacement
	float ripple = beat * 0.08 * (sin(VERTEX.x * 4.0 + TIME * 2.0) + cos(VERTEX.z * 4.0 + TIME * 2.0));
	VERTEX += NORMAL * ripple;
}

void fragment() {
	// Fresnel — edge glow
	vec3 view_dir = normalize(VIEW - MODEL_MATRIX[3].xyz);
	vec3 nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float fresnel = 1.0 - abs(dot(normalize(view_dir), nrm));
	fresnel = pow(fresnel, fresnel_power);

	// Internal noise swirl — nebula-like texture
	vec3 noise_pos = MODEL_MATRIX[3].xyz * noise_scale + TIME * swirl_speed * 0.5;
	float n = fbm(noise_pos + NORMAL * 0.8);

	// Swirling energy bands
	float swirl = sin(MODEL_MATRIX[3].y * 3.0 + TIME * swirl_speed + n * 2.0) * 0.5 + 0.5;
	float swirl2 = cos(MODEL_MATRIX[3].x * 2.5 + MODEL_MATRIX[3].z * 2.5 + TIME * 0.6 * swirl_speed) * 0.5 + 0.5;

	// Inner energy pulse
	float pulse = 1.0 + sin(TIME * pulse_speed + MODEL_MATRIX[3].x * 0.5 + MODEL_MATRIX[3].z * 0.3) * pulse_amp;

	// Blend noise, swirl, and base color
	vec3 nebula = mix(albedo.rgb, albedo.rgb * 1.6, n * 0.5 + 0.5);
	vec3 swirled = mix(nebula, albedo.rgb * 1.4, swirl * 0.4);
	swirled = mix(swirled, albedo.rgb * 1.3, swirl2 * 0.3);

	// Blend inner glow → edge glow with beat boost
	vec3 inner = swirled * 0.7;
	vec3 rim = albedo.rgb * 2.8 * (1.0 + beat * 0.5);
	vec3 color = mix(inner, rim, fresnel) * pulse * base_brightness;

	ALBEDO = color * (1.0 + beat * 0.3);
	EMISSION = color * 1.6;
	ALPHA = 0.85 + fresnel * 0.15;
}
