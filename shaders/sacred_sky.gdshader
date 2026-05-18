shader_type sky;

// ── Sacred Sky Shader ──
// Wraps a sacred image around the celestial sphere as a sky background.
// Equirectangular projection with scale/rotate/beat controls.

uniform sampler2D bg_tex : source_color;
uniform float rotation : hint_range(0.0, 6.283) = 0.0;
uniform float blend : hint_range(0.0, 1.0) = 1.0;
uniform float brightness : hint_range(0.3, 3.0) = 1.0;
uniform float scale : hint_range(0.5, 4.0) = 1.0;
uniform float beat : hint_range(0.0, 2.0) = 0.0;

void sky() {
	vec3 dir = normalize(VIEW);

	// Equirectangular UV from view direction
	float u = atan(dir.z, dir.x) / (2.0 * PI) + 0.5 + rotation;
	float v = asin(clamp(dir.y, -1.0, 1.0)) / PI + 0.5;

	// Zoom from center
	u = (u - 0.5) * scale + 0.5;
	v = (v - 0.5) * scale + 0.5;

	// Soft fade at image edges
	float edge_x = 1.0 - smoothstep(0.0, 0.08, abs(u - 0.5) * 2.0 - (1.0 - 0.02));
	float edge_y = 1.0 - smoothstep(0.0, 0.08, abs(v - 0.5) * 2.0 - (1.0 - 0.02));
	float edge = edge_x * edge_y;

	u = clamp(u, 0.001, 0.999);
	v = clamp(v, 0.001, 0.999);

	vec4 tex = texture(bg_tex, vec2(u, v));

	COLOR = tex.rgb * brightness * blend * (1.0 + beat * 0.18) * max(edge, 0.04);
	ALPHA = blend;
}
