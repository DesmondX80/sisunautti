// Saturnuksen renkaat: väri ja läpikuultavuus säteen mukaan renkaiden kuvasta, valaistus molemmilta puolilta
// (jääkiteet sirottavat valoa) ja planeetan varjo renkailla. Kappaleen koordinaatisto: planeetan säde 1.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, shadows_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform sampler2D ring_tex : source_color, filter_linear, repeat_disable;
uniform vec3 sun_local = vec3(1.0, 0.0, 0.0);
uniform float sun_intensity = 1.0;
uniform float ring_inner = 1.24;
uniform float ring_outer = 2.27;

varying vec3 local_pos;
varying vec3 cam_local;

void vertex() {
	local_pos = VERTEX;
	cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	float r = length(local_pos.xz);
	float u = (r - ring_inner) / (ring_outer - ring_inner);
	if (u < 0.0 || u > 1.0) discard;
	vec4 tex = texture(ring_tex, vec2(u, 0.5));
	vec3 l = normalize(sun_local);
	// Planeetan varjo: säde Aurinkoa kohti osuu palloon.
	float b = dot(local_pos, l);
	float c = dot(local_pos, local_pos) - 1.0;
	float shadow = (b < 0.0 && b * b - c > 0.0) ? 0.06 : 1.0;
	// Valaistu puoli (sama puoli kuin Aurinko) on kirkkaampi kuin takaa läpi kuultava.
	vec3 v = normalize(cam_local - local_pos);
	float same = sign(l.y) * sign(v.y);
	float lit = mix(0.45, 1.0, step(0.0, same)) * (0.35 + 0.65 * abs(l.y) * 4.0);
	lit = clamp(lit, 0.2, 1.0);
	ALBEDO = tex.rgb * sun_intensity * lit * shadow;
	ALPHA = tex.a;
}
