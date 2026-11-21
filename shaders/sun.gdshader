// Auringon kiekko (fotosfääri): HDR-kirkas pinta, jonka yksityiskohdat näkyvät kohdekameran aurinkosuotimella ja
// lähellä Aurinkoa.
// - Reunatummeneminen aallonpituuden mukaan: sininen tummenee reunalla eniten, joten reuna on oranssimpi
//   (lineaarinen laki I(μ) = 1 − u(1 − μ), u kanavittain).
// - Granulaatio: kirkkaat konvektiosolut tummine väleineen (3D-solukohina pallon pinnalla), hitaasti eläen, ja
//   suurempi supergranulaatio. Häivytetään, kun solu olisi kuvapistettä pienempi (ei välkettä).
// - Auringonpilkkuryhmät (johtava pilkku ja seuraaja, tumma umbra ja vaaleampi penumbra) aktiivisuusvyöhykkeillä
//   7°–35° molemmin puolin päiväntasaajaa, muutamia kerrallaan. Pinta pyörii simulaation ajassa (Carringtonin
//   keskimääräinen nopeus, 25,4 vrk), ja ryhmät kasvavat ja hiipuvat noin 60 vrk:n jaksoissa (kaksi limittäistä
//   jaksoa).
// - Soihtukentät (faculae): kirkkaat kentät pilkkujen ympärillä, näkyvät reunan lähellä.
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform float brightness = 40.0;
uniform float visible = 1.0;
uniform float sim_days = 0.0; // simulaation aika (vrk J2000:sta) pyörimistä ja pilkkujen elämää varten
uniform float detail = 1.0; // yksityiskohtien voimakkuus (laatutaso)

varying vec3 local_pos;
varying vec3 cam_local;

void vertex() {
	local_pos = VERTEX;
	// VERTEX-kirjoitus pakottaa Forward+:n syvyysesikierroksen käyttämään tätä varjostinta (DEPTH) eikä yhteistä
	// oletusmateriaalia, joka kirjoittaisi oikean syvyyden: väripass hylkäisi silloin pinnan (musta pallo ilman SSAO:ta).
	VERTEX = local_pos;
	cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

vec3 hash3(vec3 p) {
	p = vec3(dot(p, vec3(127.1, 311.7, 74.7)), dot(p, vec3(269.5, 183.3, 246.1)), dot(p, vec3(113.5, 271.9, 124.6)));
	return fract(sin(p) * 43758.5453123);
}

float hash1(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Solukohina: etäisyydet lähimpään ja toiseksi lähimpään soluun (F1, F2). Solujen keskipisteet liikkuvat hitaasti.
vec2 worley(vec3 p, float t) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 g = vec3(float(x), float(y), float(z));
				vec3 h = hash3(i + g);
				vec3 o = 0.5 + 0.38 * sin(t + 6.2831 * h);
				float d = length(g + o - f);
				if (d < f1) {
					f2 = f1;
					f1 = d;
				} else if (d < f2) {
					f2 = d;
				}
			}
		}
	}
	return vec2(f1, f2);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash1(i), hash1(i + vec3(1, 0, 0)), f.x), mix(hash1(i + vec3(0, 1, 0)), hash1(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash1(i + vec3(0, 0, 1)), hash1(i + vec3(1, 0, 1)), f.x), mix(hash1(i + vec3(0, 1, 1)), hash1(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03) * 0.3 + vnoise(p * 4.1) * 0.2;
}

// Pallon piste pyöritettynä y-akselin (Auringon akseli) ympäri kulmalla a.
vec3 spin_y(vec3 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
}

// Yksi pilkku: x tummuus (penumbra 0,6, umbra 1), y soihtukenttä. d etäisyys keskipisteestä, r säde.
vec2 one_spot(float d, float r, float edge) {
	float pen = smoothstep(r, r * 0.8, d + edge * r * 0.15);
	float umb = smoothstep(r * 0.45, r * 0.32, d);
	float fac = smoothstep(r * 4.0, r * 1.1, d);
	return vec2(pen * 0.6 + umb * 0.4, fac);
}

// Yhden pilkkujakson pilkkuryhmät: pallon pinta jaetaan soluihin (noin 10°), ja osassa aktiivisuusvyöhykkeiden
// soluista on ryhmä: johtava pilkku ja sen takana (idässä) pienempi seuraaja. Ryhmä kasvaa ja hiipuu jakson aikana
// (life 0–1). Ryhmä kiertää kokonaisena (magneettinen rakenne ei veny), pinta keskimääräisellä nopeudella.
// Palauttaa x tummuus, y soihtukenttä.
vec2 spot_field(vec3 q, float k, float life) {
	vec3 p = q * 6.0;
	vec3 i = floor(p);
	vec2 acc = vec2(0.0);
	float edge = vnoise(q * 160.0) - 0.5;
	for (int z = -1; z <= 1; z++) {
		for (int y = -1; y <= 1; y++) {
			for (int x = -1; x <= 1; x++) {
				vec3 cell = i + vec3(float(x), float(y), float(z));
				vec3 h = hash3(cell + k * 13.7);
				if (h.x > 0.035) continue;
				vec3 c = normalize(cell + 0.2 + 0.6 * h);
				float lat = abs(c.y);
				if (lat < 0.12 || lat > 0.58) continue;
				float r = (0.009 + 0.02 * h.y) * sqrt(life);
				// Seuraaja itään (pyörimissuuntaan nähden takana), hieman navan puolella (Joyn laki).
				vec3 c2 = normalize(spin_y(c, 0.05 + 0.05 * h.z) + vec3(0.0, sign(c.y) * 0.015, 0.0));
				vec2 a = one_spot(length(q - c), r, edge);
				vec2 b = one_spot(length(q - c2), r * (0.5 + 0.3 * h.z), edge);
				acc = vec2(max(acc.x, max(a.x, b.x)), max(acc.y, max(a.y, b.y)));
			}
		}
	}
	return acc;
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	vec3 n = normalize(local_pos);
	float mu = clamp(dot(n, normalize(cam_local - local_pos)), 0.0, 1.0);
	// Kuvapisteen koko pallon pinnalla (säteinä): yksityiskohdat häivytetään, kun ne olisivat pikseliä pienempiä.
	float px = length(fwidth(local_pos));
	vec3 rot = spin_y(n, -radians(14.18) * sim_days); // keskimääräinen pyöriminen (Carrington) tasaisena
	float t = TIME * 0.15;
	// Granulaatio (solun kirkas keskus, tummat välit) ja supergranulaatio.
	float g_scale = 70.0;
	vec2 w = worley(rot * g_scale, t);
	float gran = smoothstep(0.0, 0.35, w.y - w.x) * 0.9 + (1.0 - w.x) * 0.25;
	float g_fade = (1.0 - smoothstep(0.25, 0.9, px * g_scale)) * detail;
	vec2 sw = worley(rot * 18.0, t * 0.1);
	float super_g = smoothstep(0.0, 0.25, sw.y - sw.x);
	float s_fade = (1.0 - smoothstep(0.3, 1.0, px * 18.0)) * detail;
	float mottle = mix(1.0, 0.86 + 0.2 * gran, g_fade) * mix(1.0, 0.96 + 0.05 * super_g, s_fade);
	// Pilkut: kaksi limittäistä 60 vrk:n jaksoa, jotka häivytetään ristiin (painojen summa 1).
	const float PERIOD = 60.0;
	float spots = 0.0;
	float faculae = 0.0;
	for (int j = 0; j < 2; j++) {
		float ph = sim_days / PERIOD + float(j) * 0.5;
		float k = floor(ph) * 2.0 + float(j);
		float a = fract(ph);
		vec2 f = spot_field(rot, k, sin(3.14159 * a));
		spots = max(spots, f.x);
		faculae = max(faculae, f.y);
	}
	float spot_fade = (1.0 - smoothstep(0.01, 0.04, px)) * detail;
	spots *= spot_fade;
	// Reunatummeneminen kanavittain (punainen vähiten) ja soihtukentät reunan lähellä.
	vec3 u = vec3(0.52, 0.64, 0.78);
	vec3 limb = vec3(1.0) - u * (1.0 - mu);
	float fac = faculae * spot_fade * pow(1.0 - mu, 1.5) * 0.35;
	vec3 base = vec3(1.0, 0.95, 0.88);
	// Umbra on tumma ja punertava (viileämpi kaasu), penumbra ruskehtava.
	vec3 spot_col = mix(vec3(1.0), vec3(0.55, 0.42, 0.34), clamp(spots / 0.6, 0.0, 1.0));
	spot_col = mix(spot_col, vec3(0.1, 0.05, 0.03), clamp((spots - 0.6) / 0.4, 0.0, 1.0));
	ALBEDO = base * limb * mottle * spot_col * (1.0 + fac) * brightness * visible;
}
