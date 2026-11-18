// Maan pilvikerros: pilvikartta läpinäkyvyytenä, valaistus kuten pinnalla. Kerros pyörii hieman eri tahtia kuin pinta.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform sampler2D cloud_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sun_local = vec3(1.0, 0.0, 0.0);
uniform float sun_intensity = 1.0;
uniform float opacity = 0.95;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	vec3 n = normalize(local_pos);
	float ndl = dot(n, normalize(sun_local));
	float day = smoothstep(-0.08, 0.15, ndl) * max(ndl + 0.08, 0.0) / 1.08;
	float c = texture(cloud_tex, UV).r;
	vec3 sunset = mix(vec3(1.0, 0.6, 0.4), vec3(1.0), smoothstep(0.0, 0.25, ndl));
	ALBEDO = sunset * (day * sun_intensity + 0.01);
	ALPHA = smoothstep(0.08, 0.9, c) * opacity;
}
