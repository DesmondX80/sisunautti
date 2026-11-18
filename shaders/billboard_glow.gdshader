// Hehku kameraan päin kääntyvänä tasona (Auringon korona ja kaukaisten kappaleiden pisteet). Koko pikseleinä
// vähintään min_pixels, jotta kaukainen kohde näkyy kirkkaana pisteenä.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform float min_pixels = 3.0;
uniform float falloff = 2.0;
uniform float core = 0.15;

void vertex() {
	// Taso kameraan päin; koko maailman yksikköinä (MODEL_MATRIX:n skaala), mutta vähintään min_pixels.
	vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float scale = length(MODEL_MATRIX[0].xyz);
	float dist = length(center - CAMERA_POSITION_WORLD);
	float px_world = 2.0 * dist / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	float size = max(scale, px_world * min_pixels);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = center + (right * VERTEX.x + up * VERTEX.y) * size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	float r = length(UV * 2.0 - 1.0);
	float glow = pow(max(1.0 - r, 0.0), falloff) + smoothstep(core, 0.0, r) * 2.0;
	ALBEDO = color.rgb * energy * glow;
	ALPHA = 1.0;
}
