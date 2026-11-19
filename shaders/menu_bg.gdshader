// Aloitusvalikon tausta: avaruuskuva hitaasti liukuen ja zoomaten (Ken Burns), hiiren mukaan parallaksi,
// kirkkaat tähdet tuikkivat, ja vasen reuna ja kulmat tummuvat, jotta valikon teksti erottuu.
shader_type canvas_item;

uniform sampler2D image : source_color, filter_linear_mipmap;
uniform float view_aspect = 1.7778;
uniform float image_aspect = 1.7266;
uniform vec2 parallax = vec2(0.0); // −1…1
uniform float fade = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float t = TIME;
	float zoom = 1.1 + 0.05 * sin(t * 0.045);
	vec2 pan = vec2(sin(t * 0.027), cos(t * 0.019)) * 0.018 + parallax * 0.012;
	vec2 uv = UV - 0.5;
	if (view_aspect > image_aspect) {
		uv.y *= image_aspect / view_aspect;
	} else {
		uv.x *= view_aspect / image_aspect;
	}
	uv = uv / zoom + 0.5 + pan;
	vec3 c = texture(image, uv).rgb;
	// Tuike: kirkkaat pisteet sykkivät hieman kukin omassa tahdissaan.
	float lum = dot(c, vec3(0.3, 0.59, 0.11));
	float h = hash(floor(uv * vec2(900.0, 520.0)));
	c *= 1.0 + smoothstep(0.7, 0.95, lum) * 0.22 * sin(t * (1.5 + h * 3.0) + h * 40.0);
	// Luettavuus: vasen reuna ja alareuna tummemmiksi, reunojen tummennus.
	c *= 1.0 - 0.62 * smoothstep(0.7, 0.0, UV.x);
	c *= 1.0 - 0.35 * smoothstep(0.6, 1.0, UV.y);
	vec2 v = UV - 0.5;
	c *= 1.0 - 0.7 * dot(v, v);
	COLOR = vec4(c * fade, 1.0);
}
