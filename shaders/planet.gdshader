// Planeetan tai kuun pinta (oma valaistus, valaisematon tila): pintakartta, pehmeä terminaattori, yöpuolen
// kaupunkien valot (Maa), Auringon heijastus meristä (Maa), ilmakehän reunahehku sekä renkaiden varjo (Saturnus).
// Kuu: kohokuvio korkeusmallista (normaalit ja varjot), Kuun heijastusmalli, maanvalo ja lähikuvan pienet kraatterit.
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
// Kohokuvio (Kuu): R, G = pinnan normaali kartan sarakkeiden (itä) ja rivien (etelä) suuntaan, B = paikallinen
// korkeus ±relief_height m. Varjot lasketaan kulkemalla korkeuskarttaa pitkin Aurinkoa kohti (shadow_steps askelta).
uniform sampler2D relief_tex : hint_default_black, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float relief = 0.0;
uniform float relief_height = 4000.0;
uniform float radius_m = 1737400.0;
uniform int shadow_steps = 0;
uniform float shadow_range_m = 90000.0;
// Lommel–Seeliger-heijastus (ilmaton, pölyinen pinta): täysikuu on reunoja myöten tasaisen kirkas. 0 = Lambert.
uniform float regolith = 0.0;
// Maanvalo yöpuolella: Maan suunta kappaleen koordinaatistossa ja kirkkaus (Maan vaihe huomioituna).
uniform vec3 earth_local = vec3(0.0, 0.0, 1.0);
uniform float earthshine = 0.0;
// Lähikuvan kraatterikenttä (karttapistettä pienemmät kraatterit, oikein valaistut). 0 = pois.
uniform float craters = 0.0;
// Pintakartan kirkkauden kontrasti (Kuun LROC-kartta on tasaisen harmaa), potenssikäyrä keskisävyn ympäri.
uniform float albedo_contrast = 1.0;

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

// Kraatterikenttä solukoordinaateissa q: jokaisessa solussa todennäköisyydellä kraatteri (malja, valli, heittely).
// Palauttaa korkeuden gradientin (xyz, mitattuna kraatterin säteinä, eli kaltevuus) ja kirkkausmuutoksen (w).
vec4 crater_field(vec3 q) {
	vec3 ip = floor(q);
	vec3 g = vec3(0.0);
	float bright = 0.0;
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 c = ip + vec3(float(x), float(y), float(z));
				if (hash3(c) > 0.6) {
					continue;
				}
				vec3 ctr = c + vec3(hash3(c + 11.1), hash3(c + 23.7), hash3(c + 37.3));
				float rc = mix(0.1, 0.55, pow(hash3(c + 5.3), 2.2));
				vec3 dv = q - ctr;
				float dl = length(dv);
				float r = dl / rc;
				if (r > 2.2) {
					continue;
				}
				vec3 dir = dv / max(dl, 1e-5);
				// Malja f = 0,4 (r² − 1), valli Gaussin kumpu r = 1:n kohdalla, ulospäin loiveneva heittelykerros.
				float df = r < 1.0 ? 0.8 * r : 0.0;
				float e = r - 1.05;
				df += 0.12 * exp(-e * e / 0.03) * (-2.0 * e / 0.03);
				g += dir * df;
				// Tuoreilla kraattereilla vaalea heittelykehä (näkyy korkeallakin Auringolla), vanhat tummuvat
				// avaruusrapautumisessa ja niiden pohja on hieman ympäristöä tummempi.
				float fresh = hash3(c + 71.9);
				bright += fresh > 0.8 ? 1.1 * (1.0 - smoothstep(0.5, 2.2, r)) : -0.1 * (1.0 - smoothstep(0.7, 1.1, r));
			}
		}
	}
	return vec4(g, clamp(bright, -0.3, 1.0));
}

// Kuutiollinen B-splini neljällä bilineaarisella haulla: suurennettu normaalikartta pysyy pehmeänä eikä karttapisteiden
// ruudukko näy porrastuksena (bilineaarisen suodatuksen kulmat rinteiden rajoilla).
vec4 texture_bicubic(sampler2D tex, vec2 uv) {
	vec2 ts = vec2(textureSize(tex, 0));
	vec2 p = uv * ts - 0.5;
	vec2 f = fract(p);
	vec2 i = p - f;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;
	vec2 w0 = (1.0 - 3.0 * f + 3.0 * f2 - f3) / 6.0;
	vec2 w1 = (4.0 - 6.0 * f2 + 3.0 * f3) / 6.0;
	vec2 w2 = (1.0 + 3.0 * f + 3.0 * f2 - 3.0 * f3) / 6.0;
	vec2 w3 = f3 / 6.0;
	vec2 g0 = w0 + w1;
	vec2 g1 = w2 + w3;
	vec2 h0 = (i - 0.5 + w1 / g0) / ts;
	vec2 h1 = (i + 1.5 + w3 / g1) / ts;
	return mix(mix(textureLod(tex, vec2(h1.x, h1.y), 0.0), textureLod(tex, vec2(h0.x, h1.y), 0.0), g0.x),
		mix(textureLod(tex, vec2(h1.x, h0.y), 0.0), textureLod(tex, vec2(h0.x, h0.y), 0.0), g0.x), g0.y);
}

float relief_h(vec2 uv, float lod) {
	return (textureLod(relief_tex, uv, lod).b - 0.5) * 2.0 * relief_height;
}

// Osuus Auringosta, joka näkyy pisteestä uv0: säde Aurinkoa kohti nousee kulmassa e (ja pallon kaarevuus laskee
// pintaa säteen alta, d²/2R). Puolivarjo kasvaa etäisyyden mukana (Auringon kulmasäde 0,27°).
float relief_shadow(vec2 uv0, vec3 n, vec3 l, vec3 t_u, vec3 t_v) {
	vec2 dir = vec2(dot(l, t_u), dot(l, t_v));
	float hl = length(dir);
	if (hl < 1e-4) {
		return 1.0;
	}
	dir /= hl;
	float tan_e = dot(n, l) / hl;
	float coslat = max(length(n.xz), 0.03);
	vec2 to_uv = dir * vec2(1.0 / (TAU * radius_m * coslat), 1.0 / (PI * radius_m));
	float texel = PI * radius_m / float(textureSize(relief_tex, 0).y);
	float h0 = (texture_bicubic(relief_tex, uv0).b - 0.5) * 2.0 * relief_height;
	float d = texel * 0.7;
	float growth = pow(shadow_range_m / d, 1.0 / float(max(shadow_steps, 1)));
	float s = 1.0;
	for (int i = 0; i < shadow_steps; i++) {
		float lod = max(0.0, log2(d * (growth - 1.0) / texel));
		float h = relief_h(uv0 + to_uv * d, lod);
		float ray = h0 + d * tan_e + d * d / (2.0 * radius_m);
		float pen = d * 0.0047 + 25.0;
		s = min(s, smoothstep(-pen, pen, ray - h));
		d *= growth;
	}
	return s;
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
		// Kohokuviollisella pinnalla (Kuu) yksityiskohdat jo, kun karttapiste on kuvapisteen kokoinen.
		zoom = (1.0 - (relief > 0.0 ? smoothstep(0.7, 2.2, texels) : smoothstep(0.35, 1.2, texels))) * surface_detail;
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
		vec3 sharp = albedo - blur;
		if (relief > 0.0) {
			// Kuussa terävöitys vain kirkkauteen: pakatun kartan värikohina ei voimistu.
			sharp = vec3(dot(sharp, vec3(0.299, 0.587, 0.114)));
		}
		albedo = max(albedo + sharp * 0.6 * zoom * (1.0 - water), 0.0);
		// Hieno vaihtelu maalla karttapistettä pienemmässä mittakaavassa (pellot, kivikko, kasvillisuus).
		vec3 q = n * ts.x / TAU * 3.0;
		float f = fbm(q, 4) - 0.5;
		float land = 1.0 - water;
		albedo *= 1.0 + f * (relief > 0.0 ? 0.2 : 0.55) * zoom * land;
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
	if (albedo_contrast != 1.0) {
		// Kontrasti kirkkauteen (lineaarinen keskisävy 0,18), värisävy säilyy eikä pakkauskohina värity.
		float lum = max(dot(albedo, vec3(0.299, 0.587, 0.114)), 1e-4);
		albedo = vec3(lum) * pow(lum / 0.18, albedo_contrast - 1.0) * mix(vec3(1.0), albedo / lum, saturation);
	}
	float ndl = dot(n, l);
	// Pehmeä terminaattori: valo hiipuu hieman yöpuolen puolelle (ilmakehä taittaa ja sirottaa).
	float day = smoothstep(-0.06, 0.12, ndl) * max(ndl + 0.06, 0.0) / 1.06;
	float limb = mix(1.0, pow(max(dot(n, v), 0.0), 0.35), limb_darkening);
	vec3 surf_n = n;
	if (relief > 0.0) {
		// Pinnan suunnat: kartan sarake (u, itään) ja rivi (v, etelään); SphereMesh: p = (sin 2πu, cos πv, cos 2πu).
		vec3 t_u = vec3(n.z, 0.0, -n.x);
		t_u = length(t_u) > 1e-4 ? normalize(t_u) : vec3(1.0, 0.0, 0.0);
		vec3 t_v = cross(t_u, n);
		// Suurennettuna (karttapiste kuvapistettä suurempi) kuutiollinen suodatus, muuten mipmapit.
		vec2 rts = vec2(textureSize(relief_tex, 0));
		float rtexels = fwidth(UV.y) * rts.y;
		vec4 rs = rtexels < 1.0 ? texture_bicubic(relief_tex, uv) : texture(relief_tex, uv);
		vec2 rn = (rs.rg - 0.5) * 2.0 * relief;
		surf_n = normalize(rn.x * t_u + rn.y * t_v + sqrt(max(1.0 - dot(rn, rn), 0.0)) * n);
		if (surface_detail > 0.0 && craters > 0.0) {
			// Kaksi kraatterikokoa korkeusmallin erottelukyvyn alapuolella: solut 3,5 km ja 1,1 km (kraatterien
			// halkaisija 0,2–4 km). Häivytetään, kun solu kutistuu kuvapisteen kokoiseksi (ei välkettä).
			float scale = radius_m / 3500.0;
			float k = surface_detail * craters;
			for (int o = 0; o < 2; o++) {
				vec3 q = n * scale + vec3(float(o) * 31.7);
				float fade = 1.0 - smoothstep(0.25, 0.8, length(fwidth(q)));
				if (fade > 0.0) {
					vec4 cf = crater_field(q);
					vec3 gt = cf.xyz - dot(cf.xyz, n) * n;
					surf_n = normalize(surf_n - gt * 0.75 * k * fade);
					albedo *= 1.0 + cf.w * k * fade;
				}
				scale *= 3.1;
			}
		}
		// Kuun pinta: ei ilmakehää, joten terminaattori on terävä ja vuorenhuiput valaistuvat sen takana.
		// Rinne, joka kääntyy juuri Auringosta poispäin, tummuu pehmeästi (pinnan karheus, Auringon kiekon koko).
		float mu0 = smoothstep(-0.04, 0.06, dot(surf_n, l)) * max(dot(surf_n, l) + 0.04, 0.0) / 1.04;
		float mu = max(dot(surf_n, v), 0.1);
		float lit = mix(mu0, min(2.0 * mu0 / (mu0 + mu), 1.4), regolith);
		float shadow = 1.0;
		if (shadow_steps > 0 && ndl > -0.05 && ndl < 0.55 && mu0 > 0.0) {
			shadow = relief_shadow(uv, n, l, t_u, t_v);
		}
		day = lit * shadow * smoothstep(-0.05, -0.01, ndl);
	}
	vec3 color = albedo * (day * sun_intensity * limb + ambient);
	if (earthshine > 0.0) {
		color += albedo * earthshine * max(dot(surf_n, normalize(earth_local)), 0.0) * vec3(0.8, 0.9, 1.1);
	}
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
