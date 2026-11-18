// Ohjaamon kuva ja näytöt 2D-kerroksena 3D-näkymän päällä (ei sävykartoitusta eikä valotusta, joten kuvan värit
// säilyvät). Jokaiselle pikselille lasketaan katsesuunta aluksen koordinaateissa ja siitä kohta ohjaamon kuvassa
// (kuvataso metrin päässä, polttoväli focal pikseleinä). Ikkuna-alue ja kuvan ulkopuoli ovat läpinäkyviä.
// Näyttöjen kohdalla kuvan päälle piirretään pelin näyttö: kuvan pikselistä näytön UV:ksi projektiivisella
// kuvauksella (homografia).
shader_type canvas_item;

uniform sampler2D image : source_color, filter_linear_mipmap;
uniform vec2 image_size = vec2(1382.0, 777.0);
uniform vec2 image_center = vec2(691.0, 388.5);
uniform float focal = 633.0;
uniform mat3 cam_basis; // kameran kanta aluksen koordinaateissa
uniform float tan_half; // pystykuvakulman puolikkaan tangentti
uniform float aspect = 1.7778;
uniform vec3 glow = vec3(0.0); // moottorin ja plasman hehku
uniform sampler2D screen0 : source_color, filter_linear;
uniform sampler2D screen1 : source_color, filter_linear;
uniform sampler2D screen2 : source_color, filter_linear;
uniform sampler2D screen3 : source_color, filter_linear;
uniform sampler2D screen4 : source_color, filter_linear;
uniform sampler2D screen5 : source_color, filter_linear;
uniform mat3 homography0;
uniform mat3 homography1;
uniform mat3 homography2;
uniform mat3 homography3;
uniform mat3 homography4;
uniform mat3 homography5;
uniform float screen_brightness = 1.35;

bool screen_uv(mat3 h, vec2 p, out vec2 uv) {
	vec3 q = h * vec3(p, 1.0);
	uv = q.xy / q.z;
	return uv.x >= 0.0 && uv.x <= 1.0 && uv.y >= 0.0 && uv.y <= 1.0;
}

vec3 screen_color(sampler2D tex, vec2 uv) {
	vec3 c = texture(tex, uv).rgb;
	float vignette = smoothstep(0.0, 0.04, uv.x) * smoothstep(1.0, 0.96, uv.x) * smoothstep(0.0, 0.06, uv.y) * smoothstep(1.0, 0.94, uv.y);
	return c * screen_brightness * mix(0.7, 1.0, vignette) + vec3(0.004, 0.012, 0.02);
}

void fragment() {
	vec2 ndc = UV * 2.0 - 1.0;
	vec3 d = cam_basis * vec3(ndc.x * tan_half * aspect, -ndc.y * tan_half, -1.0);
	if (d.z >= -1e-4) {
		COLOR = vec4(0.0);
	} else {
		vec2 p = image_center + vec2(d.x, -d.y) / -d.z * focal;
		vec2 iuv = p / image_size;
		if (iuv.x < 0.0 || iuv.x > 1.0 || iuv.y < 0.0 || iuv.y > 1.0) {
			COLOR = vec4(0.0);
		} else {
			vec2 grad_x = dFdx(iuv);
			vec2 grad_y = dFdy(iuv);
			vec4 c = textureGrad(image, iuv, grad_x, grad_y);
			c.rgb += glow * c.rgb;
			vec2 suv;
			if (screen_uv(homography0, p, suv)) { c = vec4(screen_color(screen0, suv), 1.0); }
			else if (screen_uv(homography1, p, suv)) { c = vec4(screen_color(screen1, suv), 1.0); }
			else if (screen_uv(homography2, p, suv)) { c = vec4(screen_color(screen2, suv), 1.0); }
			else if (screen_uv(homography3, p, suv)) { c = vec4(screen_color(screen3, suv), 1.0); }
			else if (screen_uv(homography4, p, suv)) { c = vec4(screen_color(screen4, suv), 1.0); }
			else if (screen_uv(homography5, p, suv)) { c = vec4(screen_color(screen5, suv), 1.0); }
			// Kuvan reunat häivytetään ympäröivään sisätilaan.
			float edge = smoothstep(0.0, 0.006, iuv.x) * smoothstep(1.0, 0.994, iuv.x) * smoothstep(0.0, 0.01, iuv.y) * smoothstep(1.0, 0.99, iuv.y);
			COLOR = vec4(c.rgb, c.a * edge);
		}
	}
}
