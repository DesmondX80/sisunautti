// Kulunut metalli (PBR): perusväri, likaa koloissa, naarmuja, levyjen saumat ja niittirivit. Kuviot lasketaan
// kappaleen koordinaateista kolmesta suunnasta (triplanar), joten ne sopivat mihin tahansa muotoon ilman UV-karttaa.
// Normaali saadaan korkeuskentän derivaatoista (bump), ja naarmut ovat kiiltävämpiä kuin muu pinta.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color : source_color = vec3(0.6, 0.63, 0.68);
uniform float metallic : hint_range(0.0, 1.0) = 0.7;
uniform float roughness : hint_range(0.0, 1.0) = 0.5;
uniform float wear : hint_range(0.0, 1.0) = 0.5;
uniform float panel_size = 0.4;
uniform float rivet_spacing = 0.06;
uniform float rivets : hint_range(0.0, 1.0) = 1.0;
uniform float bump_strength = 1.0;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D scratch_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 emission_color : source_color = vec3(0.0);

varying vec3 obj_pos;
varying vec3 obj_normal;

void vertex() {
	// Kappaleen koordinaatit skaalattuina metreiksi, jotta kuviot ovat saman kokoisia kaikissa osissa.
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	obj_pos = VERTEX * s;
	obj_normal = NORMAL;
}

float tri(sampler2D tex, vec3 p, vec3 w, float k) {
	return texture(tex, p.yz * k).r * w.x + texture(tex, p.xz * k).r * w.y + texture(tex, p.xy * k).r * w.z;
}

// Naarmut: pitkiksi venytetty kohina kahteen suuntaan, ohuet harjanteet.
float scratches(vec2 p) {
	float a = texture(scratch_noise, vec2(p.x * 0.35, p.y * 9.0)).r;
	float b = texture(scratch_noise, vec2((p.x + p.y) * 7.0, (p.x - p.y) * 0.3) + 0.37).r;
	float s1 = smoothstep(0.975, 0.995, 1.0 - abs(a * 2.0 - 1.0));
	float s2 = smoothstep(0.98, 0.997, 1.0 - abs(b * 2.0 - 1.0));
	// Naarmuja vain kuluneilla alueilla.
	float patch = smoothstep(0.55, 0.75, texture(noise, p * 0.35 + 0.5).r);
	return max(s1, s2 * 0.7) * patch;
}

// Levyjen saumat ja niitit tasossa p: palauttaa korkeuden (saumat ja niitin reunat), niittimaski y:ssä.
vec2 panels(vec2 p) {
	vec2 g = p / panel_size;
	vec2 f = abs(fract(g) - 0.5) * panel_size; // etäisyys levyn keskeltä
	float edge = min(panel_size * 0.5 - f.x, panel_size * 0.5 - f.y);
	float seam = 1.0 - smoothstep(0.0, 0.004, edge);
	// Niitit levyn reunojen suuntaisesti, hieman reunasta sisään.
	float along_x = fract(p.x / rivet_spacing) - 0.5;
	float along_y = fract(p.y / rivet_spacing) - 0.5;
	float rx = length(vec2(along_x * rivet_spacing, (panel_size * 0.5 - f.y) - 0.018)) ;
	float ry = length(vec2(along_y * rivet_spacing, (panel_size * 0.5 - f.x) - 0.018));
	float rivet = max(1.0 - smoothstep(0.004, 0.0065, rx), 1.0 - smoothstep(0.004, 0.0065, ry)) * rivets;
	return vec2(-seam * 0.6 + rivet * 0.5, rivet);
}

void fragment() {
	vec3 w = pow(abs(obj_normal), vec3(4.0));
	w /= (w.x + w.y + w.z);
	vec3 p = obj_pos;
	float grime = tri(noise, p, w, 0.9);
	float fine = tri(noise, p, w, 7.0);
	vec2 pa = w.x > 0.5 ? p.yz : (w.y > 0.5 ? p.xz : p.xy);
	float sc = scratches(pa * 1.3) * wear;
	vec2 pr = panels(pa);
	float height = pr.x - sc * 0.15 + fine * 0.04;
	// Bump: korkeuden muutos näytön suuntiin → normaalin kallistus.
	vec3 dpdx = dFdx(VERTEX);
	vec3 dpdy = dFdy(VERTEX);
	float dhx = dFdx(height);
	float dhy = dFdy(height);
	vec3 r1 = cross(dpdy, NORMAL);
	vec3 r2 = cross(NORMAL, dpdx);
	float det = dot(dpdx, r1);
	vec3 grad = sign(det) * (dhx * r1 + dhy * r2);
	NORMAL = normalize(abs(det) * NORMAL - grad * 0.004 * bump_strength);
	vec3 col = base_color * mix(0.8, 1.06, grime) * mix(1.0, 0.92, fine * 0.5);
	col = mix(col, col * 0.45, smoothstep(0.55, 0.85, grime) * wear * 0.8); // likaa
	col = mix(col, vec3(0.7, 0.72, 0.74), sc * 0.45); // naarmut paljastavat kirkkaan metallin
	col *= 1.0 - (1.0 - smoothstep(0.0, 0.5, pr.x + 0.6)) * 0.5; // saumojen pohja tummempi
	ALBEDO = col;
	METALLIC = mix(metallic, 1.0, sc);
	ROUGHNESS = clamp(roughness + (grime - 0.5) * 0.25 - sc * 0.3 + pr.y * -0.15, 0.08, 1.0);
	EMISSION = emission_color;
	AO = mix(1.0, 0.6, 1.0 - smoothstep(-0.3, 0.0, pr.x));
}
