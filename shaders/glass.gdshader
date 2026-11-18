// Kuomun lasi: lähes läpinäkyvä, heijastaa ohjaamon valoja himmeästi (Fresnel), pinnassa lievää likaa ja
// naarmuja, jotka Aurinko sytyttää häikäisyksi, kun se paistaa lasin läpi.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, specular_schlick_ggx;

uniform sampler2D dirt : filter_linear_mipmap, repeat_enable;
uniform sampler2D scratch_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 sun_dir_view = vec3(0.0, 0.0, -1.0); // Auringon suunta näkymäkoordinaateissa
uniform float sun_visible = 1.0;
uniform float glare_strength = 1.0;
uniform float tint = 0.03;

varying vec3 obj_pos;

void vertex() {
	obj_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = obj_pos.xy + obj_pos.z * 0.7;
	float d = texture(dirt, p * 0.6).r;
	float smudge = smoothstep(0.55, 0.85, d) * 0.6 + smoothstep(0.7, 1.0, texture(dirt, p * 3.0 + 0.3).r) * 0.4;
	float s = texture(scratch_noise, vec2(p.x * 0.4, p.y * 12.0)).r;
	float scratch = smoothstep(0.985, 0.998, 1.0 - abs(s * 2.0 - 1.0)) * smoothstep(0.6, 0.8, texture(dirt, p * 0.3 + 0.2).r);
	vec3 view = normalize(-VERTEX);
	float fres = pow(1.0 - abs(dot(NORMAL, view)), 4.0);
	// Häikäisy: lika ja naarmut sirottavat auringonvaloa, kun katse on lähellä Auringon suuntaa.
	float toward = max(dot(-view, normalize(sun_dir_view)), 0.0);
	float glare = (pow(toward, 400.0) * 2.0 + pow(toward, 40.0) * 0.12) * (0.3 + smudge * 1.2 + scratch * 4.0) * sun_visible * glare_strength;
	ALBEDO = vec3(0.6, 0.7, 0.75) * tint + smudge * 0.02;
	ROUGHNESS = 0.04 + smudge * 0.3;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	EMISSION = vec3(1.0, 0.95, 0.85) * glare;
	ALPHA = clamp(0.03 + fres * 0.3 + smudge * 0.04 + scratch * 0.08, 0.0, 1.0);
}
