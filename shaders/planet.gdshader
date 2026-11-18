// Planeetan tai kuun pinta (oma valaistus, valaisematon tila): pintakartta, pehmeä terminaattori, yöpuolen
// kaupunkien valot (Maa), Auringon heijastus meristä (Maa), ilmakehän reunahehku sekä renkaiden varjo (Saturnus).
// Laskut kappaleen omassa koordinaatistossa: pallon säde 1, renkaiden taso y = 0.
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://shaders/space_depth.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D night_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D spec_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D ring_tex : source_color, filter_linear, repeat_disable;
uniform vec3 sun_local = vec3(1.0, 0.0, 0.0); // Auringon suunta kappaleen koordinaatistossa
uniform float sun_intensity = 1.0;
uniform float night_strength = 0.0;
uniform float spec_strength = 0.0;
uniform vec3 atmo_color = vec3(0.4, 0.6, 1.0);
uniform float atmo_strength = 0.0;
uniform float limb_darkening = 0.0; // kaasujättiläiset
uniform float ambient = 0.012;
uniform bool has_rings = false;
uniform float ring_inner = 1.24;
uniform float ring_outer = 2.27;
uniform float cloud_shadow = 0.0;
uniform sampler2D cloud_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float cloud_offset = 0.0;

varying vec3 local_pos;
varying vec3 cam_local;

void vertex() {
	local_pos = VERTEX;
	// VERTEX-kirjoitus pakottaa Forward+:n syvyysesikierroksen käyttämään tätä varjostinta (DEPTH) eikä yhteistä
	// oletusmateriaalia, joka kirjoittaisi oikean syvyyden: väripass hylkäisi silloin pinnan (musta pallo ilman SSAO:ta).
	VERTEX = local_pos;
	cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	vec3 n = normalize(local_pos);
	vec3 l = normalize(sun_local);
	vec3 v = normalize(cam_local - local_pos);
	vec3 albedo = texture(albedo_tex, UV).rgb;
	float ndl = dot(n, l);
	// Pehmeä terminaattori: valo hiipuu hieman yöpuolen puolelle (ilmakehä taittaa ja sirottaa).
	float day = smoothstep(-0.06, 0.12, ndl) * max(ndl + 0.06, 0.0) / 1.06;
	float limb = mix(1.0, pow(max(dot(n, v), 0.0), 0.35), limb_darkening);
	vec3 color = albedo * (day * sun_intensity * limb + ambient);
	// Renkaiden varjo planeetalla: säde Aurinkoa kohti leikkaa renkaiden tason.
	if (has_rings && abs(l.y) > 1e-4) {
		float t = -local_pos.y / l.y;
		if (t > 0.0) {
			vec3 h = local_pos + l * t;
			float r = length(h.xz);
			if (r > ring_inner && r < ring_outer) {
				float a = texture(ring_tex, vec2((r - ring_inner) / (ring_outer - ring_inner), 0.5)).a;
				color *= 1.0 - 0.85 * a;
			}
		}
	}
	// Pilvien varjo pinnalla (Maa): pilvikartta hieman Auringon suuntaan siirrettynä.
	if (cloud_shadow > 0.0) {
		float c = texture(cloud_tex, UV + vec2(cloud_offset, 0.0)).r;
		color *= 1.0 - cloud_shadow * c * day;
	}
	// Meret heijastavat Auringon (Blinn–Phong), vain päiväpuolella.
	if (spec_strength > 0.0) {
		float mask = texture(spec_tex, UV).r;
		vec3 hv = normalize(l + v);
		float s = pow(max(dot(n, hv), 0.0), 400.0) * 1.6 + pow(max(dot(n, hv), 0.0), 30.0) * 0.06;
		color += vec3(1.0, 0.92, 0.8) * s * mask * spec_strength * day * sun_intensity;
	}
	// Kaupunkien valot yöpuolella.
	if (night_strength > 0.0) {
		float dark = 1.0 - smoothstep(-0.12, 0.04, ndl);
		color += texture(night_tex, UV).rgb * vec3(1.0, 0.82, 0.55) * night_strength * dark;
	}
	// Ilmakehän reunahehku: sironnut valo näkyy ohuena kaarena ja terminaattorilla punertavana.
	if (atmo_strength > 0.0) {
		float fres = pow(1.0 - max(dot(n, v), 0.0), 3.0);
		float lit = smoothstep(-0.25, 0.35, ndl);
		vec3 sunset = mix(vec3(1.0, 0.45, 0.2), atmo_color, smoothstep(-0.05, 0.3, ndl));
		color = mix(color, sunset * sun_intensity, fres * atmo_strength * lit * 0.85);
		color += atmo_color * atmo_strength * 0.08 * lit * sun_intensity;
	}
	ALBEDO = color;
}
