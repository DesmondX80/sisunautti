// Ohjaamon näyttö: SubViewportin kuva hehkuvana (emissive), hienovarainen juovitus ja pikseliverkko sekä
// heijastus näytön lasissa (kiiltävä pinta heijastaa ohjaamon valoja).
shader_type spatial;
render_mode specular_schlick_ggx;

uniform sampler2D screen_tex : source_color, filter_linear_mipmap;
uniform float brightness = 1.6;
uniform float lines = 288.0;
uniform float flicker = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, UV).rgb;
	float scan = 0.82 + 0.18 * sin(UV.y * lines * PI * 2.0);
	float grid = 0.92 + 0.08 * sin(UV.x * lines * 1.78 * PI * 2.0);
	float vignette = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x) * smoothstep(0.0, 0.1, UV.y) * smoothstep(1.0, 0.9, UV.y);
	float f = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 90.0));
	ALBEDO = vec3(0.01);
	ROUGHNESS = 0.22;
	METALLIC = 0.0;
	SPECULAR = 0.3;
	EMISSION = (c * scan * grid + vec3(0.004, 0.012, 0.018)) * brightness * mix(0.75, 1.0, vignette) * f;
}
