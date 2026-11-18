// Taivas: Linnunradan panoraama (NASA Deep Star Maps, päiväntasaajan koordinaatit) himmeänä taustana ja
// päivätaivas (laukaisu Maan pinnalta) tai ilmajarrutuksen hehku. eq_to_scene kiertää suunnan scene-koordinaateista
// päiväntasaajan koordinaatteihin.
shader_type sky;

uniform sampler2D milkyway : source_color, filter_linear_mipmap, repeat_enable;
uniform float milkyway_strength = 0.06;
uniform mat3 scene_to_eq = mat3(1.0);
uniform vec3 day_color = vec3(0.31, 0.56, 0.82);
uniform float day = 0.0;
uniform vec3 sun_dir = vec3(0.0, 0.0, -1.0);

void sky() {
	vec3 d = scene_to_eq * EYEDIR;
	// Rektaskensio kasvaa vasemmalle, ja 0 h on kuvan keskellä.
	float ra = atan(d.y, d.x);
	float dec = asin(clamp(d.z, -1.0, 1.0));
	vec2 uv = vec2(0.5 - ra / (2.0 * PI), 0.5 - dec / PI);
	vec3 mw = texture(milkyway, uv).rgb;
	vec3 col = mw * mw * milkyway_strength;
	// Päivätaivas: horisonttia kohti vaaleampi, Auringon ympärillä kirkas.
	float sun = pow(max(dot(EYEDIR, normalize(sun_dir)), 0.0), 24.0);
	vec3 dayc = day_color * (0.7 + 0.5 * (1.0 - abs(EYEDIR.y))) + vec3(1.0, 0.9, 0.7) * sun * 2.0;
	COLOR = mix(col, dayc * 0.85, clamp(day, 0.0, 1.0));
}
