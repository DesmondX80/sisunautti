// Ohjaamon näytön pyörivä pallo (kohdekamera ja järjestelmien hologrammi): pintakartta pallolle projisoituna,
// valaistus sivulta, ilmakehän reunahehku ja hologrammina sininen sävy juovineen. Aurinko hehkuu.
// Suunnattuna (oriented, kohdekamera lähellä kohdetta): pallo käännetään niin, että aluksen alla oleva kohta on
// keskellä (view_to_body: kuvan suunnat kappaleen pallon koordinaatteihin, Godotin SphereMeshin UV), Auringon
// suunta on light_dir, ja Maalla on pilvet (view_to_cloud) ja yövalot. Suorakaiteen täytyy olla neliö.
shader_type canvas_item;

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_tex = false;
uniform vec4 base_color : source_color = vec4(0.55, 0.6, 0.7, 1.0);
uniform float holo = 0.0;
uniform float spin = 0.01; // kierrosta sekunnissa
uniform bool sun = false;
uniform vec3 light_dir = vec3(-0.75, 0.35, 0.55);
uniform bool oriented = false;
uniform mat3 view_to_body = mat3(1.0);
uniform mat3 view_to_cloud = mat3(1.0);
uniform sampler2D night_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_night = false;
uniform sampler2D cloud_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool has_clouds = false;
uniform vec3 atmo_color = vec3(0.35, 0.6, 1.0);
uniform float atmo = 0.0; // ilmakehän voimakkuus (0 = ei ilmakehää)
uniform float margin = 1.0; // suorakaiteen puolileveys pallon säteinä (> 1: tilaa reunahehkulle)

vec2 sphere_uv(vec3 b) {
	return vec2(atan(b.x, b.z) / TAU, acos(clamp(b.y, -1.0, 1.0)) / PI);
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * margin;
	float r = length(p);
	float aa = fwidth(r) * 1.5;
	vec3 n = vec3(p.x, -p.y, sqrt(max(0.0, 1.0 - r * r)));
	float lon = atan(n.x, n.z) + TIME * spin * TAU;
	float lat = asin(clamp(n.y, -1.0, 1.0));
	vec2 raw = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	if (oriented) {
		raw = sphere_uv(normalize(view_to_body * n));
	}
	vec2 gx = dFdx(raw);
	vec2 gy = dFdy(raw);
	if (oriented) { // saumassa u hyppää yhdellä: derivaatta ilman hyppyä
		gx.x = gx.x - round(gx.x);
		gy.x = gy.x - round(gy.x);
	}
	vec3 c = has_tex ? textureGrad(tex, fract(raw), gx, gy).rgb : base_color.rgb;
	float inside = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, r);
	vec3 col;
	float alpha;
	if (sun) {
		float limb = pow(max(n.z, 0.0), 0.4);
		col = vec3(1.0, 0.78, 0.42) * (0.35 + 0.4 * limb);
		float corona = exp(-max(r - 1.0, 0.0) * 9.0) * (1.0 - inside);
		col = col * inside + vec3(0.8, 0.5, 0.22) * corona;
		alpha = max(inside, corona);
	} else if (oriented) {
		// Oikea valaistus: pehmeä terminaattori, yöpuolella kaupunkien valot, päivällä pilvet ja ilmakehän reuna.
		vec3 l = normalize(light_dir);
		float ndl = dot(n, l);
		float lit = smoothstep(-0.06, 0.25, ndl) * clamp(ndl * 0.8 + 0.4, 0.0, 1.0);
		vec3 surf = c * (0.012 + 1.05 * lit);
		if (has_clouds) {
			vec2 cu = sphere_uv(normalize(view_to_cloud * n));
			vec2 cgx = dFdx(cu);
			vec2 cgy = dFdy(cu);
			cgx.x -= round(cgx.x);
			cgy.x -= round(cgy.x);
			float cl = textureGrad(cloud_tex, fract(cu), cgx, cgy).r;
			surf = mix(surf, vec3(0.95) * (0.015 + 1.05 * lit), cl * 0.9);
		}
		if (has_night) {
			vec3 city = textureGrad(night_tex, fract(raw), gx, gy).rgb;
			surf += city * vec3(1.0, 0.8, 0.55) * 0.9 * (1.0 - smoothstep(-0.12, 0.05, ndl));
		}
		// Ilmakehä: reunalla sininen kaari valaistulla puolella, ohut hehku yöpuolen reunalla.
		float limb = pow(1.0 - n.z, 2.5);
		float day_edge = smoothstep(-0.3, 0.4, ndl);
		surf = mix(surf, atmo_color * (0.15 + 1.1 * day_edge), clamp(limb * atmo * 0.85, 0.0, 0.9));
		float halo_w = atmo > 0.0 ? 22.0 : 60.0;
		float halo = exp(-max(r - 1.0, 0.0) * halo_w) * (1.0 - inside) * (0.15 + 0.85 * smoothstep(-0.4, 0.5, dot(normalize(vec3(p.x, -p.y, 0.0)), l)));
		vec3 halo_col = atmo > 0.0 ? atmo_color * atmo : vec3(0.0);
		col = surf * inside + halo_col * halo;
		alpha = max(inside, atmo > 0.0 ? halo * atmo : 0.0);
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
