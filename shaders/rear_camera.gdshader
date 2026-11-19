// Takakameran kuva kohdekameranäytöllä: hieman tynnyrimäinen linssi, värivirhe reunoilla, juovat, kohina ja
// reunojen tummennus, jotta kuva näyttää kameran syötteeltä eikä ikkunalta.
shader_type canvas_item;

uniform float aspect = 1.7778; // kuvan leveys / korkeus

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = UV - 0.5;
	vec2 cc = c * vec2(aspect, 1.0);
	vec2 uv = 0.5 + c * (1.0 - 0.05 * dot(cc, cc));
	float ca = 0.0025 * length(cc);
	vec3 col = vec3(texture(TEXTURE, uv + vec2(ca, 0.0)).r, texture(TEXTURE, uv).g, texture(TEXTURE, uv - vec2(ca, 0.0)).b);
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum), 0.12) * vec3(0.94, 1.0, 1.06);
	float scan = 0.93 + 0.07 * sin(UV.y * 3.14159 * 360.0);
	float vig = smoothstep(1.0, 0.35, length(cc) / (0.5 * aspect));
	float n = hash(floor(UV * vec2(480.0, 270.0)) + fract(TIME * 7.0) * 91.0);
	col = col * scan * mix(0.45, 1.0, vig) + (n - 0.5) * 0.035;
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}
