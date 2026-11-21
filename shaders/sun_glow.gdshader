// Auringon valo kiekon ympärillä kameraan päin kääntyvänä tasona (additiivinen):
// - häikäisy (silmän ja lasin sironta): kirkas aureoli aivan kiekon reunalla ja leveä hehku, jonka koko ja kirkkaus
//   seuraavat valon määrää etäisyyden mukaan (Space.update: halo_frac ja energy)
// - tähtimäinen ydin, joka ei pienene muutamaa kuvapistettä pienemmäksi: kaukaa (Neptunus) Aurinko on häikäisevä
//   tähti, vaikka kiekko on alle kuvapisteen
// - korona: säteittäiset virtaukset (streamerit) 1–5 Auringon säteen päähän. Se on aina olemassa, mutta näkyy vasta,
//   kun kiekko pimentyy (visible → 0) planeetan tai kuun taakse: silloin häikäisy sammuu ja korona jää.
// Kappaleet peittävät tason syvyyden mukaan (space_depth Auringon etäisyydellä).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.92, 0.8, 1.0);
uniform float energy = 1.0; // häikäisyn kirkkaus (valon määrä etäisyyden mukaan)
uniform float disk_frac = 0.1; // kiekon säde tason puolikkaan osuutena
uniform float halo_frac = 0.3; // leveän hehkun säde tason puolikkaan osuutena
uniform float visible = 1.0; // näkyvä osuus kiekosta (pimennys)
uniform float corona = 1.0; // koronan voimakkuus
uniform float core_px = 3.0; // tähtimäisen ytimen säde kuvapisteinä
uniform float core_energy = 12.0; // ytimen kirkkaus (pysyy suurena kaukanakin)

varying float px_world;
varying float quad_size;
varying float stretch; // tason kasvatus vähimmäiskoon vuoksi

void vertex() {
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	quad_size = length(MODEL_MATRIX[0].xyz);
	float dist = length(center - CAMERA_POSITION_WORLD);
	px_world = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	// Taso vähintään 16 kuvapisteen kokoinen, jotta tähtimäinen ydin mahtuu.
	float size = max(quad_size, px_world * 16.0);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * size;
	stretch = size / max(quad_size, 1e-9);
	quad_size = size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

float hash(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

// Jaksollinen 1D-kohina kulmalle (period jaksoa kierroksella).
float anoise(float a, float period, float seed) {
	float x = a / 6.28318 * period;
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash(mod(i, period) + seed), hash(mod(i + 1.0, period) + seed), f);
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	vec2 q = UV * 2.0 - 1.0;
	float r_quad = length(q);
	vec2 p = q * stretch;
	float r = length(p); // alkuperäisen tason puolikkaan yksiköissä
	float disk = max(disk_frac, 1e-5);
	float rd = r / disk; // Auringon säteinä
	// Kuvapisteinä: tason koordinaatin muutos kuvapistettä kohden ruudun derivaatoista.
	float r_px = r_quad / max(length(fwidth(q)) * 0.7071, 1e-6);
	float outside = smoothstep(0.98, 1.02, rd);
	// Häikäisy: aureoli kiekon reunalla ja leveä hehku (Lorentz-tyyppinen pyrstö), molemmat pimennyksen mukaan.
	float aureole = exp(-max(rd - 1.0, 0.0) * 1.5) * outside;
	float h = r / max(halo_frac, 1e-4);
	float halo = 1.0 / pow(1.0 + h * h, 1.5);
	float edge = 1.0 - smoothstep(0.75, 1.0, r_quad); // tason reunalla nollaan
	vec3 glare = color.rgb * (aureole * 1.2 + halo * 0.18) * energy * visible;
	// Tähtimäinen ydin: muutaman kuvapisteen piste (näkyy, kun kiekko on pieni).
	float core = exp(-r_px / max(core_px, 0.5)) * core_energy * visible;
	// Korona: kirkkaus laskee jyrkästi (r^-2,2, ulkoreuna 3–6 säteellä) ja streamerit vaihtelevat kulman mukaan; napojen suunnassa heikompi.
	// atan(0, 0) on määrittelemätön (NaN), ja hehku levittäisi sen laajaksi läiskäksi.
	float ang = r > 1e-4 ? atan(p.y, p.x) : 0.0;
	float streak = 0.35 + 0.9 * pow(anoise(ang, 24.0, 3.0), 2.0) + 0.6 * pow(anoise(ang, 9.0, 11.0), 3.0);
	float equator = 0.55 + 0.45 * pow(abs(cos(ang)), 0.7);
	float cor = pow(max(rd, 1.0), -2.2) * streak * equator * outside * (1.0 - smoothstep(3.0, 6.0, rd));
	// Sisäkoronan helmiäinen valo ja kromosfäärin ohut punainen reuna (näkyy vain pimennyksessä).
	float rim = exp(-abs(rd - 1.01) * 60.0);
	float hidden = 1.0 - visible;
	vec3 cor_col = vec3(0.92, 0.95, 1.0) * cor * 5.0 + vec3(1.0, 0.25, 0.35) * rim * 2.0;
	vec3 col = glare + color.rgb * core + cor_col * corona * (0.02 + hidden * hidden);
	ALBEDO = col * edge;
	ALPHA = 1.0;
}
