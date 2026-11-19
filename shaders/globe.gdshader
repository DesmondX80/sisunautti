// Ohjaamon näytön pyörivä pallo (kohdekamera ja järjestelmien hologrammi): pintakartta pallolle projisoituna,
// valaistus sivulta, ilmakehän reunahehku ja hologrammina sininen sävy juovineen. Aurinko hehkuu.
// Suorakaiteen täytyy olla neliö.
shader_type canvas_item;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_tex = false;
uniform vec4 base_color : source_color = vec4(0.55, 0.6, 0.7, 1.0);
uniform float holo = 0.0;
uniform float spin = 0.01; // kierrosta sekunnissa
uniform bool sun = false;
uniform vec3 light_dir = vec3(-0.75, 0.35, 0.55);

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	vec3 n = vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r * r)));
	float lon = atan(n.x, n.z) + TIME * spin * TAU;
	float lat = asin(clamp(n.y, -1.0, 1.0));
	vec2 raw = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	vec3 c = has_tex ? textureGrad(tex, fract(raw), dFdx(raw), dFdy(raw)).rgb : base_color.rgb;
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	vec3 col;
	float alpha;
	if (sun) {
		float limb = pow(max(n.z, 0.0), 0.4);
		col = vec3(1.0, 0.78, 0.42) * (0.35 + 0.4 * limb);
		float corona = exp(-max(r - 1.0, 0.0) * 9.0) * (1.0 - inside);
		col = col * inside + vec3(0.8, 0.5, 0.22) * corona;
		alpha = max(inside, corona);
	} else {
		float lit = clamp(dot(n, normalize(light_dir)), 0.0, 1.0);
		vec3 surf = c * (0.03 + 0.8 * lit);
		float rim = pow(1.0 - n.z, 3.0) * (0.3 + lit);
		surf += vec3(0.35, 0.6, 1.0) * rim * 0.5;
		if (holo > 0.0) {
			float lum = dot(c, vec3(0.3, 0.59, 0.11));
			vec3 h = mix(vec3(0.03, 0.15, 0.32), vec3(0.55, 0.92, 1.0), clamp(lum * 1.5, 0.0, 1.0)) * (0.35 + 0.75 * lit);
			h += vec3(0.4, 0.85, 1.0) * pow(1.0 - n.z, 2.0) * 0.6;
			h *= 0.85 + 0.15 * sin(UV.y * 260.0);
			surf = mix(surf, h, holo);
		}
		float halo = exp(-max(r - 1.0, 0.0) * 30.0) * (1.0 - inside) * 0.6;
		col = surf * inside + vec3(0.35, 0.65, 1.0) * halo;
		alpha = max(inside, halo);
	}
	COLOR = vec4(col, alpha);
}
