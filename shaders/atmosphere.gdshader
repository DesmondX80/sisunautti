// Ilmakehän sironta: kuorikerros planeetan ympärillä (säde atmo_radius planeetan säteinä). Näkösäteen matka
// ilmakehässä (planeetan ohi tai sen pintaan) lasketaan analyyttisesti, ja sironnut valo kerätään muutamasta
// näytteestä (samples, laatutason mukaan). Piirretään takapinnat lisäävällä sekoituksella, joten kuori toimii myös
// ilmakehän sisältä (laukaisu).
shader_type spatial;
render_mode unshaded, cull_front, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform vec3 sun_local = vec3(1.0, 0.0, 0.0);
uniform float sun_intensity = 1.0;
uniform vec3 atmo_color = vec3(0.35, 0.6, 1.0);
uniform float atmo_radius = 1.025;
uniform float density = 1.0;
uniform int samples = 8;

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

void fragment() {
	DEPTH = space_depth(VERTEX);
	vec3 o = cam_local;
	vec3 d = normalize(local_pos - cam_local);
	vec2 a = sphere(o, d, atmo_radius);
	vec2 p = sphere(o, d, 1.0);
	float t0 = max(a.x, 0.0);
	float t1 = a.y;
	if (p.x > 0.0 && p.x < t1) t1 = p.x; // planeetan pinta katkaisee säteen
	if (t1 <= t0) discard;
	vec3 l = normalize(sun_local);
	float h = atmo_radius - 1.0;
	vec3 total = vec3(0.0);
	float depth = 0.0;
	float step = (t1 - t0) / float(samples);
	for (int i = 0; i < samples; i++) {
		vec3 x = o + d * (t0 + step * (float(i) + 0.5));
		float alt = clamp((length(x) - 1.0) / h, 0.0, 1.0);
		float rho = exp(-alt * 4.0);
		depth += rho * step;
		float lit = smoothstep(-0.2, 0.25, dot(normalize(x), l));
		// Auringonlasku: lähellä terminaattoria ja pitkällä matkalla valo punertuu.
		vec3 tint = mix(vec3(1.0, 0.42, 0.18), atmo_color, smoothstep(-0.05, 0.35, dot(normalize(x), l)));
		total += tint * rho * lit * step * exp(-depth / h * 0.6 * density);
	}
	float mu = dot(d, l);
	float phase = 0.75 * (1.0 + mu * mu) + 0.6 * pow(max(mu, 0.0), 8.0);
	// Kyllästys: pitkä matka ilmakehässä (reuna, sisältä katsottuna) ei kasva rajatta.
	vec3 col = (vec3(1.0) - exp(-total / h * density * 0.35)) * phase * sun_intensity * 0.8;
	ALBEDO = col;
}
