// Maan pilvikerros: pilvikartta läpinäkyvyytenä, valaistus kuten pinnalla. Kerros pyörii hieman eri tahtia kuin pinta.
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform sampler2D cloud_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 sun_local = vec3(1.0, 0.0, 0.0);
uniform float sun_intensity = 1.0;
uniform float opacity = 0.95;
// Lähikuva (kiertoradalta): pilvien reunat rikotaan kohinalla karttapistettä pienemmiksi ja pilvien pintaan
// tulee kumpuja, jotka valaistaan Auringon suunnasta. 0 = pois (laatutaso).
uniform float surface_detail = 0.0;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p, int octaves) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < octaves; i++) {
		sum += amp * vnoise(p);
		p = p * 2.03 + vec3(1.7, 9.2, 3.1);
		amp *= 0.5;
	}
	return sum;
}

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	vec3 n = normalize(local_pos);
	float ndl = dot(n, normalize(sun_local));
	float day = smoothstep(-0.08, 0.15, ndl) * max(ndl + 0.08, 0.0) / 1.08;
	vec2 uv = UV;
	float zoom = 0.0;
	vec3 q = vec3(0.0);
	vec2 ts = vec2(textureSize(cloud_tex, 0));
	if (surface_detail > 0.0) {
		float texels = fwidth(UV.y) * ts.y;
		zoom = (1.0 - smoothstep(0.35, 1.2, texels)) * surface_detail;
		q = n * ts.x / TAU;
		if (zoom > 0.0) {
			vec2 warp = vec2(fbm(q * 0.5, 3), fbm(q * 0.5 + vec3(4.1, 8.3, 1.2), 3)) - 0.5;
			uv += warp * 2.0 / ts * zoom;
		}
	}
	float c = texture(cloud_tex, uv).r;
	float shade = 1.0;
	if (zoom > 0.0) {
		// Reunat: kohina siirtää kynnystä eniten puolipeittävissä kohdissa (pilven reuna), ei paksun pilven keskellä.
		float f = fbm(q * 0.8, 4) - 0.5;
		c = clamp(c + f * 0.5 * zoom * c * (1.0 - c) * 4.0, 0.0, 1.0);
		// Kummut: kohinan kaltevuus Auringon suuntaan valaisee toisen puolen ja varjostaa toisen.
		vec3 l = normalize(sun_local);
		vec3 tang = normalize(l - n * ndl);
		float e = 0.35;
		float slope = fbm(q * 0.8 + tang * e, 3) - fbm(q * 0.8 - tang * e, 3);
		shade = clamp(1.0 + slope * 1.2 * zoom - (1.0 - c) * 0.12 * zoom, 0.7, 1.2);
	}
	vec3 sunset = mix(vec3(1.0, 0.6, 0.4), vec3(1.0), smoothstep(0.0, 0.25, ndl));
	ALBEDO = sunset * (day * sun_intensity * shade + 0.01);
	ALPHA = smoothstep(0.08, 0.9, c) * opacity;
}
