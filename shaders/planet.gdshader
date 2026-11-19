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
uniform float detail_strength = 0.0; // kaasujättiläisten pilvipyörteet lähikuvassa
uniform float saturation = 1.0;
uniform vec3 detail_tint = vec3(1.0); // lähikuvan sävy (karttapiste suurempi kuin kuvapiste)
// Kiinteän pinnan lähikuva (kiertoradalta): kun karttapiste on kuvapistettä suurempi, rajat (rannikot, laaksot)
// rikotaan kohinalla karttapistettä pienemmiksi, paikallista kontrastia terävöitetään ja pintaan lisätään hienoa
// vaihtelua. Merillä vain aallokon välke Auringon heijastuksessa. 0 = pois (laatutaso).
uniform float surface_detail = 0.0;

varying vec3 local_pos;
varying vec3 cam_local;

// Arvokohina pallon pinnalla (3D), ei toistu eikä pikselöidy suurennettaessa.
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
	vec2 uv = UV;
	float water = spec_strength > 0.0 ? texture(spec_tex, UV).r : 0.0;
	vec3 wave_n = n;
	float zoom = 0.0; // 0 kaukana, 1 kun karttapiste on selvästi kuvapistettä suurempi
	if (surface_detail > 0.0) {
		vec2 ts = vec2(textureSize(albedo_tex, 0));
		float texels = fwidth(UV.y) * ts.y;
		zoom = (1.0 - smoothstep(0.35, 1.2, texels)) * surface_detail;
		if (zoom > 0.0) {
			// Kohinan solu noin kaksi karttapistettä: kulma karttapisteinä = n · leveys / 2π.
			vec3 q = n * ts.x / TAU * 0.5;
			vec2 warp = vec2(fbm(q, 3), fbm(q + vec3(7.3, 2.1, 5.9), 3)) - 0.5;
			uv += warp * 1.6 / ts * zoom;
		}
	}
	vec3 albedo = texture(albedo_tex, uv).rgb;
	if (zoom > 0.0) {
		vec2 ts = vec2(textureSize(albedo_tex, 0));
		// Terävöitys: ero sumeampaan tasoon (mipmap-siirto) korostaa paikallisia rajoja.
		vec3 blur = texture(albedo_tex, uv, 2.0).rgb;
		albedo = max(albedo + (albedo - blur) * 0.6 * zoom * (1.0 - water), 0.0);
		// Hieno vaihtelu maalla karttapistettä pienemmässä mittakaavassa (pellot, kivikko, kasvillisuus).
		vec3 q = n * ts.x / TAU * 3.0;
		float f = fbm(q, 4) - 0.5;
		float land = 1.0 - water;
		albedo *= 1.0 + f * 0.55 * zoom * land;
		// Merellä aallokko kallistaa pinnan normaalia hieman (Auringon välke hajoaa).
		vec3 w = vec3(fbm(q * 2.0, 3), fbm(q * 2.0 + 3.7, 3), fbm(q * 2.0 + 8.1, 3)) - 0.5;
		wave_n = normalize(n + w * 0.06 * zoom * water);
	}
	// Kaasujättiläisten lähikuva: pintakartta on suurennettuna tasainen, joten siihen lisätään sävy, kontrasti ja
	// pilvipyörteet. Kauempaa (karttapiste kuvapisteen kokoinen tai pienempi) kartta näkyy sellaisenaan.
	if (detail_strength > 0.0) {
		// Lähikuva: montako karttapistettä kuvapisteelle osuu; alle yhden kartta on suurennettu ja näyttäisi tasaiselta.
		float texels = fwidth(UV.y) * float(textureSize(albedo_tex, 0).y);
		float close = 1.0 - smoothstep(0.25, 1.0, texels);
		float lum = dot(albedo, vec3(0.299, 0.587, 0.114));
		albedo = mix(albedo, max(mix(vec3(lum), albedo, 1.6) * detail_tint, 0.0), close);
		// Kaksinkertainen vääristys (domain warping) tekee kohinasta kiemurtelevia pyörteitä; leveyssuunnassa
		// tiheämpi kohina venyttää pyörteet vyöhykkeiden suuntaisiksi. Lasketaan vain lähikuvassa.
		float swirl = 0.0;
		if (close > 0.0) {
			vec3 p = normalize(local_pos) * vec3(28.0, 70.0, 28.0);
			vec3 q = vec3(fbm(p, 3), fbm(p + vec3(5.2, 1.3, 2.8), 3), fbm(p + vec3(1.7, 9.2, 4.1), 3));
			swirl = clamp((fbm(p + q * 3.0, 5) - 0.5) * 2.2 * close, -0.5, 0.5);
		}
		float d = detail_strength;
		albedo *= 1.0 + swirl * 2.4 * d;
		// Tummat kohdat ruskeiksi, vaaleat pilvet valkoisemmiksi.
		albedo = mix(albedo, albedo * vec3(0.8, 0.6, 0.42), clamp(-swirl * 3.0, 0.0, 1.0) * d);
		albedo = mix(albedo, vec3(0.97, 0.95, 0.9) * max(lum, 0.6), clamp(swirl * 3.0, 0.0, 1.0) * d * 0.7);
	}
	albedo = max(mix(vec3(dot(albedo, vec3(0.299, 0.587, 0.114))), albedo, saturation), 0.0);
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
		float mask = water;
		vec3 hv = normalize(l + v);
		float s = pow(max(dot(wave_n, hv), 0.0), 400.0) * 1.6 + pow(max(dot(wave_n, hv), 0.0), 30.0) * 0.06;
		color += vec3(1.0, 0.92, 0.8) * s * mask * spec_strength * day * sun_intensity;
	}
	// Kaupunkien valot yöpuolella.
	if (night_strength > 0.0) {
		float dark = 1.0 - smoothstep(-0.12, 0.04, ndl);
		vec3 lights = texture(night_tex, uv).rgb;
		if (zoom > 0.0) {
			// Lähikuvassa karttapiste on monen kuvapisteen kokoinen: valo jaetaan pieniksi pisteiksi ja juoviksi
			// (kadut, taajamat), joiden väliin jää pimeää; keskimääräinen kirkkaus säilyy suunnilleen.
			vec3 q = n * float(textureSize(night_tex, 0).x) / TAU * 4.0;
			float sp = fbm(q, 3);
			float mask = smoothstep(0.42, 0.62, sp);
			lights *= mix(vec3(1.0), vec3(mask * 2.2), zoom);
		}
		lights = pow(lights, vec3(1.25));
		// Natriumvalojen oranssi, kirkkaimmat keskustat valkoisemmiksi.
		vec3 tint = mix(vec3(1.0, 0.58, 0.24), vec3(1.0, 0.82, 0.6), clamp(lights.r * 1.2 - 0.3, 0.0, 1.0));
		color += lights * tint * night_strength * dark;
	}
	// Ilmakehän reunahehku: sironnut valo näkyy ohuena kaarena ja terminaattorilla punertavana.
	// Lähellä (kiertoradalla) ilmakehän kuori hoitaa usvan ja reunan; reunahehku on kaukonäkymää varten.
	float far = smoothstep(0.03, 0.6, length(cam_local) - 1.0);
	if (atmo_strength > 0.0 && far > 0.0) {
		float fres = pow(1.0 - max(dot(n, v), 0.0), 3.0);
		float lit = smoothstep(-0.25, 0.35, ndl);
		vec3 sunset = mix(vec3(1.0, 0.45, 0.2), atmo_color, smoothstep(-0.05, 0.3, ndl));
		color = mix(color, sunset * sun_intensity, fres * atmo_strength * lit * 0.85 * far);
		color += atmo_color * atmo_strength * 0.08 * lit * sun_intensity * far;
	}
	ALBEDO = color;
}
