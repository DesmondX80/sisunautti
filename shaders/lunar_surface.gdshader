// Kuun lähipinta laskeutuessa ja pinnalla (#45): säteittäinen verkko aluksen alta horisonttiin. Verkon pisteet
// ovat kaaren pituuden (UV.x, logaritminen) ja suuntakulman (UV.y) mukaan; paikka lasketaan kappaleen keskipisteen
// suhteen tarkasti pienillä kulmilla (R·sin a ja −2R·sin²(a/2)), ja kauas ulottuvat pisteet puristetaan kuten
// avaruuden kappaleet (Space.compress), jotta ne mahtuvat kaukotason sisään suunnan muuttumatta.
// Korkeus: LOLA-korkeusmallin paikallinen korkeus (kohokuviokartan B) ja kraatterikentät viidessä koossa
// (1,2 km … 5 m), kiinni kuun pinnassa (kappaleen koordinaatit). Varjot lasketaan pisteittäin kulkemalla
// korkeuskenttää pitkin Aurinkoa kohti, joten matala Aurinko luo pitkiä varjoja. Pikseleittäin lisätään pienet
// kraatterit ja regoliitin rakeisuus (normaalit), ja heijastus on Lommel–Seeliger-tyyppinen (pölyinen pinta)
// vastakkaisuuskirkastumineen. Aluksen varjo on pehmeä ellipsi siinä kohdassa, johon Auringon säde aluksesta osuu.
shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D relief_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float relief_height = 4000.0;
uniform vec3 up_w = vec3(0.0, 1.0, 0.0); // pinnan normaali aluksen alla (scene)
uniform vec3 east_w = vec3(1.0, 0.0, 0.0);
uniform vec3 north_w = vec3(0.0, 0.0, -1.0);
uniform mat3 world_to_body = mat3(1.0); // scene → kappaleen koordinaatit (y napa, −z pituusaste 0)
uniform float radius_m = 1737400.0;
uniform float alt_m = 100.0; // silmän korkeus perussäteen yläpuolella
uniform float s0 = 1.0; // ensimmäisen renkaan mittakaava (m)
uniform float s_ratio = 1e5; // uloimman renkaan etäisyys / s0
uniform vec3 sun_w = vec3(1.0, 0.0, 0.0); // suunta Aurinkoon (scene)
uniform float sun_intensity = 1.5;
uniform vec3 earth_w = vec3(0.0, 1.0, 0.0);
uniform float earthshine = 0.0;
uniform float detail = 1.0; // pikselitason yksityiskohdat ja varjojen askeleet (laatutaso)
uniform int shadow_steps = 14;
uniform vec3 ship_shadow = vec3(0.0); // aluksen varjon keskipiste (scene, uncompressed)
uniform float ship_shadow_r = 9.0; // varjon säde (m)
uniform float ship_shadow_k = 0.0; // voimakkuus (0 = ei varjoa)
uniform float albedo_contrast = 1.35;
uniform float saturation = 0.6;
uniform float blast = 0.0; // moottorin puhaltama pöly (tummentaa ja silottaa pinnan aluksen alla)
uniform float datum_k = 1.0; // paikallisen nollatason korjaus 0–1 (matalalla ja pinnalla 1)
uniform int datum_oct = 1; // nollatasoon otettavat kraatterikoot (lähellä pintaa kaikki, korkealla vain sileät)

varying vec3 world_pos; // aluksen suhteen (m), puristamaton
varying vec3 body_dir;
varying vec3 geo_n; // verkon normaali (scene)
varying float v_shadow;
varying float v_dist;

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float hash1(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash1(i), hash1(i + vec3(1, 0, 0)), f.x), mix(hash1(i + vec3(0, 1, 0)), hash1(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash1(i + vec3(0, 0, 1)), hash1(i + vec3(1, 0, 1)), f.x), mix(hash1(i + vec3(0, 1, 1)), hash1(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Kraatterin poikkileikkaus säteen yksiköissä: kuppi (syvyys noin viidesosa halkaisijasta) ja reunavalli.
float crater_profile(float d) {
	return d < 1.0 ? (d * d - 1.0) * 0.42 + 0.1 : 0.1 * exp(-pow((d - 1.0) / 0.32, 2.0));
}

// Kraatterikenttä solukoolla c (m): osassa soluista kraatteri, säde 0,12–0,42 solua.
float crater_oct(vec3 q, float c, float density) {
	vec3 p = q / c;
	vec3 i = floor(p);
	float h = 0.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 cell = i + vec3(float(x), float(y), float(z));
				vec3 r = hash3(cell + c * 0.013);
				if (r.x > density) continue;
				vec3 center = cell + 0.15 + 0.7 * hash3(cell + 17.31);
				float rad = 0.12 + 0.3 * r.y * r.y;
				float d = length(p - center) / rad;
				if (d < 2.2) {
					h += crater_profile(d) * rad * c;
				}
			}
		}
	}
	return h;
}

vec2 body_uv(vec3 d) {
	float lon = atan(-d.x, -d.z);
	return vec2(0.5 + lon / 6.2831853, acos(clamp(d.y, -1.0, 1.0)) / 3.14159265);
}

// Korkeus (m) kappaleen suunnassa d: korkeusmalli ja kraatterit. octaves: montako kraatterikokoa (suurimmasta).
float height(vec3 d, int octaves) {
	float h = (textureLod(relief_tex, body_uv(d), 0.0).b - 0.5) * 2.0 * relief_height;
	vec3 q = d * radius_m;
	float c = 1200.0;
	for (int o = 0; o < octaves; o++) {
		h += crater_oct(q + vec3(float(o) * 91.7), c, 0.55);
		c *= 0.25;
	}
	return h;
}

float compress_d(float d) {
	return d <= 20000.0 ? d : 20000.0 + 4000.0 * log(d / 20000.0);
}

// Pinnan piste kaaren pituudella s suuntaan t (scene) ja korkeudella h: paikka aluksen suhteen.
vec3 surface_point(float s, vec3 t, float h, out vec3 dir_w) {
	float a = s / radius_m;
	dir_w = cos(a) * up_w + sin(a) * t;
	float sh = sin(a * 0.5);
	return radius_m * sin(a) * t + (-2.0 * radius_m * sh * sh - alt_m) * up_w + h * dir_w;
}

void vertex() {
	float u = UV.x;
	float th = UV.y * 6.2831853;
	float s = s0 * (pow(s_ratio + 1.0, u) - 1.0);
	vec3 t = cos(th) * east_w + sin(th) * north_w;
	vec3 side = cos(th + 1.5707963) * east_w + sin(th + 1.5707963) * north_w;
	vec3 dir_w;
	// Kaukana vähemmän kraatterikokoja: pienimmät eivät näy verkon tiheydellä.
	float ds = max(s0 * pow(s_ratio + 1.0, u) * log(s_ratio + 1.0) / 160.0, 0.3);
	int oct = ds < 4.0 ? 5 : (ds < 15.0 ? 4 : (ds < 60.0 ? 3 : (ds < 250.0 ? 2 : 1)));
	vec3 dir0 = cos(s / radius_m) * up_w + sin(s / radius_m) * t;
	// Paikallinen nollataso: koko maastoa siirretään niin, että aluksen alla pinta on perussäteellä (ratamekaniikka
	// laskee korkeuden pallon pinnasta). Siirto on sama kaikkialla, joten maaston muodot säilyvät.
	float datum = datum_k * height(world_to_body * up_w, datum_oct);
	float h = height(world_to_body * dir0, oct) - datum;
	vec3 p = surface_point(s, t, h, dir_w);
	// Normaali erotusosamääristä verkon tiheydellä.
	float e = max(ds, 0.5);
	vec3 d1;
	vec3 d2;
	vec3 dir1 = cos((s + e) / radius_m) * up_w + sin((s + e) / radius_m) * t;
	float h1 = height(world_to_body * dir1, oct) - datum;
	vec3 p1 = surface_point(s + e, t, h1, d1);
	float a = s / radius_m;
	vec3 dir2 = normalize(dir0 + side * (e / radius_m));
	float h2 = height(world_to_body * dir2, oct) - datum;
	vec3 p2 = (radius_m + h2) * dir2 - (radius_m + alt_m) * up_w;
	vec3 p_alt = (radius_m + h) * dir0 - (radius_m + alt_m) * up_w;
	vec3 n = normalize(cross(p2 - p_alt, p1 - p));
	if (dot(n, dir_w) < 0.0) n = -n;
	if (s < 0.01) n = up_w;
	geo_n = n;
	world_pos = p;
	body_dir = world_to_body * dir_w;
	v_dist = length(p);
	// Varjo: kuljetaan kohti Aurinkoa ja verrataan säteen korkeutta maastoon (pallon kaarevuus mukana).
	float shadow = 1.0;
	float sun_up = dot(sun_w, dir_w);
	if (sun_up < 0.6 && shadow_steps > 0) {
		vec3 sun_t = normalize(sun_w - sun_up * dir_w);
		float tan_e = sun_up / max(sqrt(1.0 - sun_up * sun_up), 1e-4);
		float step_m = max(ds * 1.5, 3.0);
		float x = step_m;
		float occl = 0.0;
		for (int k = 0; k < 24; k++) {
			if (k >= shadow_steps) break;
			vec3 dk = normalize(dir_w + sun_t * (x / radius_m));
			float hk = height(world_to_body * dk, max(oct - 1, 1)) - datum;
			float ray = h + x * tan_e - x * x / (2.0 * radius_m);
			occl = max(occl, (hk - ray) / (x * 0.04 + 1.0));
			x *= 1.45;
		}
		shadow = 1.0 - smoothstep(0.0, 1.0, occl);
	}
	v_shadow = shadow;
	float L = max(length(p), 1e-3);
	VERTEX = p / L * compress_d(L);
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	vec3 n = normalize(geo_n);
	vec3 dir = normalize(world_pos + (radius_m + alt_m) * up_w);
	vec3 v = normalize(-world_pos);
	vec3 l = normalize(sun_w);
	// Pikselitason yksityiskohdat: pienet kraatterit ja regoliitin rakeisuus normaalina, häivytys etäisyyden mukaan.
	vec3 q = body_dir * radius_m;
	float px = length(fwidth(world_pos)); // kuvapisteen koko pinnalla (m)
	if (detail > 0.0) {
		vec3 tx = normalize(cross(n, vec3(0.0, 0.0, 1.0) + vec3(0.31, 0.0, 0.0)));
		vec3 ty = cross(n, tx);
		float e = max(px, 0.05);
		for (int o = 0; o < 2; o++) {
			float c = o == 0 ? 2.0 : 0.6;
			float fade = (1.0 - smoothstep(c * 0.15, c * 0.6, px)) * detail;
			if (fade > 0.0) {
				float eps = c * 0.08;
				float h0 = crater_oct(q, c, 0.5);
				vec3 qx = world_to_body * tx;
				vec3 qy = world_to_body * ty;
				float hx = crater_oct(q + qx * eps, c, 0.5);
				float hy = crater_oct(q + qy * eps, c, 0.5);
				n = normalize(n - (tx * (hx - h0) + ty * (hy - h0)) / eps * fade);
			}
		}
		// Regoliitti: kivensirpaleet ja paakut (arvokohina kahdella taajuudella) normaalina.
		float gf = (1.0 - smoothstep(0.02, 0.15, px)) * detail;
		if (gf > 0.0) {
			vec3 qx = world_to_body * tx;
			vec3 qy = world_to_body * ty;
			float g0 = vnoise(q * 9.0) * 0.6 + vnoise(q * 23.0) * 0.4;
			float gx = vnoise((q + qx * 0.03) * 9.0) * 0.6 + vnoise((q + qx * 0.03) * 23.0) * 0.4;
			float gy = vnoise((q + qy * 0.03) * 9.0) * 0.6 + vnoise((q + qy * 0.03) * 23.0) * 0.4;
			n = normalize(n - (tx * (gx - g0) + ty * (gy - g0)) / 0.03 * 0.05 * gf);
		}
	}
	// Värikartta (LROC) kontrastilla ja sävyllä kuten pallolla, lisäksi hienoa vaihtelua lähellä.
	vec3 albedo = texture(albedo_tex, body_uv(body_dir)).rgb;
	float lum = max(dot(albedo, vec3(0.299, 0.587, 0.114)), 1e-4);
	albedo = vec3(lum) * pow(lum / 0.18, albedo_contrast - 1.0) * mix(vec3(1.0), albedo / lum, saturation);
	float var_n = vnoise(q * 0.02) * 0.5 + vnoise(q * 0.11) * 0.3 + vnoise(q * 0.7) * 0.2;
	albedo *= 0.85 + 0.3 * var_n;
	// Tuoreiden pienten kraatterien vaaleat heittelekentät ja kivet (tummat täplät) lähellä.
	float near_k = (1.0 - smoothstep(0.4, 2.5, px)) * detail;
	float rocks = smoothstep(0.78, 0.9, vnoise(q * 1.7)) * near_k;
	if (rocks > 0.0) {
		// Kivet kohoumina: valaistu ja varjon puoli normaalista.
		vec3 tx2 = normalize(cross(n, vec3(0.0, 0.0, 1.0) + vec3(0.31, 0.0, 0.0)));
		vec3 ty2 = cross(n, tx2);
		float r0 = vnoise(q * 1.7);
		float rx = vnoise((q + (world_to_body * tx2) * 0.05) * 1.7);
		float ry = vnoise((q + (world_to_body * ty2) * 0.05) * 1.7);
		n = normalize(n - (tx2 * (rx - r0) + ty2 * (ry - r0)) / 0.05 * 0.9 * near_k * smoothstep(0.74, 0.86, r0));
	}
	albedo *= 1.0 - 0.25 * rocks;
	// Moottorin puhaltama alue: pöly lentää pois, alla tummempi ja sileämpi pinta.
	float blast_d = length(world_pos - dot(world_pos, up_w) * up_w);
	albedo *= 1.0 - blast * 0.25 * (1.0 - smoothstep(4.0, 25.0, blast_d));
	// Heijastus: Lommel–Seeliger (pölyinen pinta), terävä terminaattori, vastakkaisuuskirkastuminen.
	float mu0 = dot(n, l);
	float lit_geo = smoothstep(-0.02, 0.03, dot(dir, l)); // aurinko horisontin yllä tässä kohdassa
	mu0 = max(mu0, 0.0);
	float mu = max(dot(n, v), 0.05);
	float ls = min(2.0 * mu0 / (mu0 + mu), 1.4);
	float lit = mix(mu0, ls, 0.4) * 0.75;
	float phase = acos(clamp(dot(v, l), -1.0, 1.0));
	lit *= 1.0 + 0.35 * exp(-phase / 0.06);
	float shadow = v_shadow;
	// Aluksen varjo: pehmeä ellipsi pinnalla.
	if (ship_shadow_k > 0.0) {
		vec3 rel = world_pos - ship_shadow;
		vec3 along = normalize(l - dot(l, up_w) * up_w);
		float e_k = max(dot(l, up_w), 0.15);
		float da = dot(rel, along) * e_k;
		float dc = length(rel - dot(rel, along) * along - dot(rel, up_w) * up_w);
		float r = length(vec2(da, dc)) / ship_shadow_r;
		shadow *= 1.0 - ship_shadow_k * 0.9 * (1.0 - smoothstep(0.75, 1.15, r));
	}
	vec3 color = albedo * lit * shadow * lit_geo * sun_intensity;
	// Maanvalo ja hyvin heikko ympäristövalo (varjot eivät ole täysin mustia).
	color += albedo * (earthshine * max(dot(n, normalize(earth_w)), 0.0) * vec3(0.8, 0.9, 1.1) + vec3(0.004));
	ALBEDO = color;
}
