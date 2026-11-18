// Kirkkaat tähdet pisteinä: koko magnitudin mukaan, HDR-kirkkaus (automaattinen valotus himmentää ne, kun
// Aurinko tai valaistu planeetta on näkyvissä). Väri ja kirkkaus pisteen värissä.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform float energy = 1.0;
uniform float size_scale = 1.0;
uniform float fade = 1.0;

void vertex() {
	POINT_SIZE = (1.5 + COLOR.a * 3.5) * size_scale;
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	float r = length(POINT_COORD * 2.0 - 1.0);
	float a = smoothstep(1.0, 0.0, r);
	ALBEDO = COLOR.rgb * a * a * energy * fade;
}
