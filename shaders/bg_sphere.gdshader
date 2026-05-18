shader_type spatial;
render_mode unshaded, cull_disabled;

// ── Background Sphere Shader ──
// Wraps a sacred image around a giant sphere enveloping the scene.
// Standard spherical UV mapping — equirectangular from Godot's SphereMesh.

uniform sampler2D bg_tex : source_color;
uniform float brightness : hint_range(0.3, 3.0) = 1.0;
uniform float blend : hint_range(0.0, 1.0) = 1.0;
uniform float beat : hint_range(0.0, 2.0) = 0.0;

void fragment() {
	vec4 tex = texture(bg_tex, UV);
	vec3 color = tex.rgb * brightness * blend * (1.0 + beat * 0.18);
	ALBEDO = color;
	ALPHA = blend;
}
