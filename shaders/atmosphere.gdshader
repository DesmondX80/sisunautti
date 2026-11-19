// Ilmakehän sironta: kuorikerros planeetan ympärillä (säde atmo_radius planeetan säteinä). Näkösäteen matka
// ilmakehässä (planeetan ohi tai sen pintaan) lasketaan analyyttisesti, ja sironnut valo ja vaimennus kerätään
// näytteistä (samples, laatutason mukaan). Tiheys laskee eksponentiaalisesti ja hiipuu kuoren ylärajalla nollaan,
// joten ilmakehän reunassa ei ole viivaa: avaruudesta katsottuna horisontin yllä on ohut kirkas kaari, joka häipyy
// pehmeästi mustaan. Auringonvalo punertuu, kun sen matka ilmakehän läpi pitenee (terminaattori).
// Sekoitus on esikerrottu alfa: väri lisätään ja taakse jäävä (pinta, pilvet, tähdet) himmenee vaimennuksen
// mukaan, joten kaukainen pinta häipyy horisonttia kohti usvaan. Takapinnat piirretään, joten kuori toimii myös
// ilmakehän sisältä (laukaisu).
shader_type spatial;
render_mode unshaded, cull_front, blend_premul_alpha, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform vec3 sun_local = vec3(1.0, 0.0, 0.0);
uniform float sun_intensity = 1.0;
uniform vec3 atmo_color = vec3(0.35, 0.6, 1.0);
uniform float atmo_radius = 1.025;
uniform float density = 1.0;
uniform int samples = 8;
// Pölyn osuus sironnasta (Mars): Henyey–Greenstein-vaihefunktio, joka sirottaa enimmäkseen eteenpäin (mie_g),
// joten Aurinko selän takana ei sumenna pintaa ja vastavalossa ilmakehä hehkuu. 0 = kaasun Rayleigh-sironta.
uniform float mie = 0.0;
uniform float mie_g = 0.65;

// Tiheyden putoamisnopeus kuoren paksuuden suhteen (skaalakorkeus = paksuus / FALLOFF).
const float FALLOFF = 6.0;

varying vec3 local_pos;
varying vec3 cam_local;

void vertex() {
	local_pos = VERTEX * atmo_radius;
	VERTEX = local_pos;
	cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

vec2 sphere(vec3 o, vec3 d, float r) {
	float b = dot(o, d);
	float c = dot(o, o) - r * r;
	float h = b * b - c;
	if (h < 0.0) return vec2(1e9, -1e9);
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

// Suhteellinen tiheys korkeudella alt (0 pinta, 1 kuoren yläraja): eksponentiaalinen, ylärajalla nolla.
float rho(float alt) {
	float top = exp(-FALLOFF);
	return max(exp(-alt * FALLOFF) - top, 0.0) / (1.0 - top);
}

void fragment() {
	vec3 o = cam_local;
	vec3 d = normalize(local_pos - cam_local);
	vec2 a = sphere(o, d, atmo_radius);
	vec2 p = sphere(o, d, 1.0);
	float t0 = max(a.x, 0.0);
	float t1 = a.y;
	if (p.x > 0.0 && p.x < t1) t1 = p.x; // planeetan pinta katkaisee säteen
	if (t1 <= t0) discard;
	// Syvyys säteen tulokohdasta (ei takapinnasta), jotta kuori piirtyy planeetan pinnan päälle.
	DEPTH = space_depth(VERTEX * max(t0, 1e-4) / max(length(local_pos - cam_local), 1e-6));
	vec3 l = normalize(sun_local);
	float h = atmo_radius - 1.0;
	float scale_h = h / FALLOFF;
	// Sirontakerroin (planeetan säteen yksikköä kohti): pystysuora optinen syvyys sinisellä noin 0,16·density
	// (Maan Rayleigh-sironta), punaisella ja vihreällä vähemmän.
	vec3 beta = atmo_color / max(atmo_color.b, 1e-3) * vec3(0.3, 0.55, 1.0) * 0.16 * density / scale_h;
	float mu = dot(d, l);
	float phase = 0.75 * (1.0 + mu * mu) + 0.5 * pow(max(mu, 0.0), 8.0);
	if (mie > 0.0) {
		float g2 = mie_g * mie_g;
		float hg = (1.0 - g2) / pow(max(1.0 + g2 - 2.0 * mie_g * mu, 1e-4), 1.5);
		phase = mix(phase, hg, mie);
	}
	// Näytteiden paikka hieman satunnaistettu kuvapisteittäin: vähän näytteitä ei näy raitoina.
	float jitter = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	float step = (t1 - t0) / float(samples);
	vec3 trans = vec3(1.0);
	vec3 light = vec3(0.0);
	for (int i = 0; i < samples; i++) {
		vec3 x = o + d * (t0 + step * (float(i) + jitter));
		float r = length(x);
		float dens = rho(clamp((r - 1.0) / h, 0.0, 1.0));
		vec3 up = x / r;
		float cos_s = dot(up, l);
		// Planeetan varjo: korkeudella z (planeetan säteinä) Aurinko näkyy vielä, kun cos_s > −√(2z), joten
		// ylempi ilma valaistuu pidempään terminaattorin takana kuin pinnan lähellä oleva tiheä kerros.
		float edge = -sqrt(2.0 * max(r - 1.0, 0.0));
		float lit = smoothstep(edge - 0.06, edge + 0.05, cos_s);
		// Auringonvalon vaimennus matkalla tähän pisteeseen: pystysuora pylväs yläpuolella × ilmamassa.
		float column = dens * scale_h;
		float airmass = 1.0 / (max(cos_s, 0.0) + 0.03);
		vec3 sun_t = exp(-beta * column * min(airmass, 40.0));
		vec3 ext = beta * dens * step;
		light += trans * ext * sun_t * lit;
		trans *= exp(-ext);
	}
	vec3 col = light * phase * sun_intensity * 0.55;
	// Kirkkaimmat kohdat (pitkä matka reunalla) pehmeästi kyllästyen.
	col = col / (1.0 + col * 0.35);
	ALBEDO = col;
	ALPHA = clamp(1.0 - dot(trans, vec3(0.3, 0.45, 0.25)), 0.0, 1.0);
}
