// Linssiheijastus ja häikäisy koko näkymän päällä: säteet ja heijasteet Auringon kuvapaikasta keskipisteen kautta.
// Ohjaamon rakenteet peittävät Auringon: syvyyspuskurista luetaan, onko Auringon kohdalla jotain lähellä (alle
// 50 m). Avaruuden kappaleiden peitto (pimennys) tulee kertoimesta intensity.
shader_type spatial;
render_mode unshaded, blend_add, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform vec2 sun_uv = vec2(0.5);
uniform float intensity = 0.0;
uniform float glare = 0.0;
uniform float aspect = 1.7778;

void vertex() {
	POSITION = vec4(VERTEX.xy, 0.0, 1.0);
}

float open_at(vec2 uv, mat4 inv_proj) {
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return 1.0;
	float depth = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	float dist = -v.z / v.w;
	return dist > 50.0 || depth <= 0.0 ? 1.0 : 0.0;
}

float ring(vec2 p, vec2 c, float r, float w) {
	return smoothstep(w, 0.0, abs(length(p - c) - r));
}

void fragment() {
	// Auringon näkyvä osuus: keskikohta ja sen ympäriltä kahdeksan näytettä.
	float vis = 0.0;
	vec2 px = 3.0 / VIEWPORT_SIZE;
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			vis += open_at(sun_uv + vec2(float(i), float(j)) * px, INV_PROJECTION_MATRIX);
		}
	}
	vis /= 9.0;
	vec2 uv = SCREEN_UV;
	vec2 p = vec2(uv.x * aspect, uv.y);
	vec2 s = vec2(sun_uv.x * aspect, sun_uv.y);
	vec2 center = vec2(0.5 * aspect, 0.5);
	vec2 axis = center - s;
	float d = length(p - s);
	float ang = atan(p.y - s.y, p.x - s.x);
	float rays = pow(abs(cos(ang * 3.0)), 60.0) * 0.6 + pow(abs(cos(ang * 2.0 + 0.4)), 120.0) * 0.4;
	vec3 col = vec3(1.0, 0.92, 0.8) * (rays * smoothstep(0.4, 0.0, d) * 0.5 + smoothstep(0.2, 0.0, d) * 0.2);
	col += vec3(0.4, 0.8, 1.0) * smoothstep(0.035, 0.0, length(p - (s + axis * 0.6))) * 0.2;
	col += vec3(1.0, 0.6, 0.3) * smoothstep(0.06, 0.0, length(p - (s + axis * 1.25))) * 0.14;
	col += vec3(0.5, 1.0, 0.6) * smoothstep(0.02, 0.0, length(p - (s + axis * 1.7))) * 0.25;
	col += vec3(0.7, 0.7, 1.0) * ring(p, s + axis * 2.0, 0.12, 0.012) * 0.1;
	col += vec3(1.0, 0.95, 0.88) * glare * 0.2;
	ALBEDO = col * intensity * vis;
}
