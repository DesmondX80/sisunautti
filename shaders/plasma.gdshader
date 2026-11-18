// Ilmajarrutuksen plasmavana kuomun ulkopuolella: virtaava ja välkkyvä hehku (lisäävä sekoitus).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 color : source_color = vec3(1.0, 0.32, 0.06);
uniform float intensity = 0.0;

void fragment() {
	vec2 uv = UV;
	float flow = texture(noise, vec2(uv.x * 1.5, uv.y * 0.6 - TIME * 1.8)).r;
	float flow2 = texture(noise, vec2(uv.x * 3.0 + 0.3, uv.y * 1.4 - TIME * 3.1)).r;
	float streak = pow(flow * 0.6 + flow2 * 0.6, 3.0);
	float edge = smoothstep(0.0, 0.25, uv.x) * smoothstep(1.0, 0.75, uv.x) * smoothstep(0.0, 0.2, uv.y);
	float fl = 0.8 + 0.2 * sin(TIME * 37.0 + uv.y * 20.0);
	vec3 c = mix(color, vec3(1.0, 0.62, 0.25), streak * 0.4);
	ALBEDO = c * pow(streak, 1.5) * edge * intensity * fl * 4.0;
}
