// Takakameran kuva kohdekameranäytöllä: hieman tynnyrimäinen linssi, värivirhe reunoilla, juovat, kohina ja
// reunojen tummennus, jotta kuva näyttää kameran syötteeltä eikä ikkunalta.
shader_type canvas_item;

uniform float aspect = 1.7778; // kuvan leveys / korkeus
uniform float grain = 1.0; // juovien ja kohinan voimakkuus (kohdekameran kaukoputki 0,3)
uniform float solar = 0.0; // aurinkosuodin (kohdekamera Aurinkoon): kirkkaus oranssiksi asteikoksi ja granulaatio


float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 c = UV - 0.5;
	vec2 cc = c * vec2(aspect, 1.0);
	vec2 uv = 0.5 + c * (1.0 - 0.05 * dot(cc, cc));
	float ca = 0.0025 * length(cc);
	vec3 col = vec3(texture(TEXTURE, uv + vec2(ca, 0.0)).r, texture(TEXTURE, uv).g, texture(TEXTURE, uv - vec2(ca, 0.0)).b);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	if (solar > 0.0) {
		// Granulaatio: pieniä kirkkaita soluja tummine reunoineen, hitaasti eläen; reunatummennus säilyy.
		vec2 q = uv * vec2(aspect, 1.0) * 70.0;
		float g = vnoise(q + TIME * 0.05) * 0.6 + vnoise(q * 2.3 - TIME * 0.03) * 0.4;
		float disc = smoothstep(0.05, 0.2, lum);
		float l = lum * (1.0 + (g - 0.5) * 0.22 * disc);
		vec3 ramp = mix(vec3(0.0), vec3(0.55, 0.12, 0.0), smoothstep(0.0, 0.15, l));
		ramp = mix(ramp, vec3(1.0, 0.45, 0.08), smoothstep(0.12, 0.4, l));
		ramp = mix(ramp, vec3(1.0, 0.86, 0.55), smoothstep(0.4, 0.75, l));
		col = mix(col, ramp, solar);
	} else {
		col = mix(col, vec3(lum), 0.12) * vec3(0.94, 1.0, 1.06);
	}
	float scan = 1.0 - grain * (0.07 - 0.07 * sin(UV.y * 3.14159 * 360.0));
	float vig = smoothstep(1.0, 0.35, length(cc) / (0.5 * aspect));
	float n = hash(floor(UV * vec2(480.0, 270.0)) + fract(TIME * 7.0) * 91.0);
	col = col * scan * mix(0.45, 1.0, vig) + (n - 0.5) * 0.035 * grain;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
