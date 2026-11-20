// Ohjaamon kuva, näytöt ja ympäröivä panoraama 2D-kerroksena 3D-näkymän päällä (ei sävykartoitusta eikä valotusta,
// joten kuvan värit säilyvät). Jokaiselle pikselille lasketaan katsesuunta aluksen koordinaateissa ja siitä kohta ohjaamon kuvassa
// (kuvataso metrin päässä, polttoväli focal pikseleinä). Ikkuna-alueet ovat läpinäkyviä.
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

// Kuvan elävöitys: kädet ja sauvat liikkuvat (siirto pikseleinä pehmeällä painolla) ja merkkivalot palavat pelin
// tilan mukaan. Valokartta (ohjaamo_valot.png): R = vaihe, G = vilkkutapa (0 tasainen, 1 hidas, 2 nopea),
// B = merkkivalon numero (1–6, pelin tila indicators[]), A = valon peitto.
uniform sampler2D lights_map : filter_nearest;
uniform float indicators[6];
uniform vec2 throttle_px = vec2(0.0); // vasen käsi: tehovipu
uniform vec2 stick_px = vec2(0.0); // oikea käsi: ohjainsauva
const vec2 THROTTLE_C = vec2(528.0, 505.0);
const vec2 STICK_C = vec2(862.0, 505.0);

vec2 animate_hands(vec2 p) {
	float wl = 1.0 - smoothstep(22.0, 92.0, length((p - THROTTLE_C) * vec2(1.0, 0.8)));
	float wr = 1.0 - smoothstep(22.0, 92.0, length((p - STICK_C) * vec2(1.0, 0.8)));
	return p - throttle_px * wl - stick_px * wr;
}

vec3 panel_lights(vec3 c, vec2 iuv) {
	vec4 L = texture(lights_map, iuv);
	if (L.a <= 0.0) {
		return c;
	}
	float ph = L.r;
	float kind = L.g * 255.0;
	float ind = L.b * 255.0;
	float on;
	if (ind > 0.5) {
		on = indicators[clamp(int(ind + 0.5) - 1, 0, 5)];
	} else if (kind < 0.5) {
		on = 0.8 + 0.2 * sin(TIME * (1.5 + ph * 3.0) + ph * 40.0);
	} else if (kind < 1.5) {
		on = step(0.45, fract(TIME * (0.3 + ph * 0.4) + ph));
	} else {
		on = step(0.72, fract(TIME * (1.6 + ph * 1.5) + ph * 7.0));
	}
	return c * mix(1.0, mix(0.22, 1.5, on), L.a);
}

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

// Kuvan ympärillä on ohjaamon 360°-panoraama (tasavälinen lieriöprojektio, eteenpäin kuvan keskellä). Kuvan
// reunoilla etukuva häivytetään panoraamaan; panoraaman sävy sovitetaan etukuvaan.
uniform sampler2D panorama : source_color, filter_linear_mipmap, repeat_enable;
uniform float pano_yaw = 0.0; // panoraaman kierto (rad)
uniform float pano_pitch = -0.19; // panoraaman kojelauta etukuvan kojelaudan taakse (rad)
uniform vec3 pano_tint = vec3(0.88, 0.95, 1.08); // viileämpi ja tummempi kuin kuva sellaisenaan, kuten etukuvan metalli
uniform float pano_gain = 0.72;
uniform float seam = 70.0; // häivytyksen leveys etukuvan reunalla (px)
// Panoraaman kojelauta on leveämpi kuin etukuvan: panoraaman suunta pano_edge (rad keskeltä) asetetaan etukuvan
// reunalle image_edge, jolloin panoraaman kojelauta jää etukuvan taakse. Sivukuvien ulkoreunalla side_edge
// panoraama jatkuu suunnasta pano_side (sivukuvan oven kohdalta). Taakse kuva on ennallaan.
uniform float pano_edge = 1.152; // 66°
uniform float image_edge = 0.829;
uniform float side_edge = 1.192; // 68,3°
uniform float pano_side = 1.38; // 79°
// Vasen sivu (peilattu kuva) katkaistaan ennen kuvan ovea kohdassa side_cut_left (px), ja panoraama jatkuu
// pylväästä.
uniform float side_cut_left = 720.0;
uniform float side_edge_left = 1.096; // 62,8°
uniform float pano_side_left = 1.54; // 88°

// Sivukuvat: ohjaamon oikea sivu (ikkunan viisto pilari, sivukonsoli, seinä ja ovi) omana kuvatasonaan, jonka
// kanta side_basis on sovitettu etukuvaan (kuvan näyttö osuu etukuvan näyttöön). Vasen sivu on sama kuva
// peilattuna. Etukuva peittää sivukuvan, ja sivukuvan reunat häivytetään panoraamaan.
uniform sampler2D side_image : source_color, filter_linear_mipmap;
uniform vec2 side_size = vec2(848.0, 1264.0);
uniform vec2 side_center = vec2(424.0, 632.0);
uniform float side_focal = 1101.0;
uniform mat3 side_basis;
uniform float side_seam = 60.0; // häivytys panoraamaan (px)
uniform vec3 side_tint = vec3(1.0);

vec3 panorama_color(vec3 d) {
	d = normalize(d);
	float lv = atan(d.x, -d.z);
	float a = abs(lv);
	float se = lv < 0.0 ? side_edge_left : side_edge;
	float ps = lv < 0.0 ? pano_side_left : pano_side;
	float lp;
	if (a < image_edge) {
		lp = a * pano_edge / image_edge;
	} else if (a < se) {
		lp = pano_edge + (a - image_edge) * (ps - pano_edge) / (se - image_edge);
	} else {
		lp = ps + (a - se) * (PI - ps) / (PI - se);
	}
	float lon = sign(lv) * lp + pano_yaw;
	float lat = asin(clamp(d.y, -1.0, 1.0)) + pano_pitch;
	vec2 uv = vec2(lon / TAU + 0.5, 0.5 - lat / PI);
	// Gradientit saumattomasta koordinaatista, jotta kierroksen kohdalle ei tule viivaa.
	vec2 uv2 = vec2(fract(uv.x + 0.5), uv.y);
	vec2 gx = dFdx(uv);
	vec2 gy = dFdy(uv);
	vec2 gx2 = dFdx(uv2);
	vec2 gy2 = dFdy(uv2);
	gx.x = abs(gx.x) < abs(gx2.x) ? gx.x : gx2.x;
	gy.x = abs(gy.x) < abs(gy2.x) ? gy.x : gy2.x;
	vec3 c = textureGrad(panorama, vec2(fract(uv.x), clamp(uv.y, 0.0, 1.0)), gx, gy).rgb;
	return c * pano_tint * pano_gain;
}

// Sivukuvan väri (premultiplied, a = peitto) ja paino w (0 kuvan ulkopuolella, häivytys reunoilla).
vec4 side_color(vec3 d, out float w) {
	w = 0.0;
	vec3 m = vec3(abs(d.x), d.y, d.z);
	vec3 l = transpose(side_basis) * m;
	if (l.z > -1e-4) {
		return vec4(0.0);
	}
	vec2 p = side_center + vec2(l.x, -l.y) / -l.z * side_focal;
	float right = d.x < 0.0 ? side_cut_left : side_size.x;
	if (p.x < 0.0 || p.y < 0.0 || p.x > right || p.y > side_size.y) {
		return vec4(0.0);
	}
	vec2 uv = p / side_size;
	vec4 c = textureGrad(side_image, uv, dFdx(uv), dFdy(uv));
	float e = min(min(p.x, right - p.x), min(p.y, side_size.y - p.y));
	w = smoothstep(0.0, side_seam, e);
	return vec4(c.rgb * side_tint * c.a, c.a);
}

void fragment() {
	vec2 ndc = UV * 2.0 - 1.0;
	vec3 d = cam_basis * vec3(ndc.x * tan_half * aspect, -ndc.y * tan_half, -1.0);
	vec3 pano = panorama_color(d);
	// Takana panoraama, sen päällä sivukuva (ikkunan kohdalla läpinäkyvä), päällimmäisenä etukuva.
	float ws;
	vec4 side = side_color(d, ws);
	vec4 back = mix(vec4(pano, 1.0), side, ws); // premultiplied
	vec4 col = back;
	if (d.z < -1e-4) {
		vec2 p = image_center + vec2(d.x, -d.y) / -d.z * focal;
		vec2 iuv = p / image_size;
		if (iuv.x >= 0.0 && iuv.x <= 1.0 && iuv.y >= 0.0 && iuv.y <= 1.0) {
			vec2 auv = animate_hands(p) / image_size;
			vec4 c = textureGrad(image, auv, dFdx(iuv), dFdy(iuv));
			c.rgb = panel_lights(c.rgb, auv);
			vec2 suv;
			if (screen_uv(homography0, p, suv)) { c = vec4(screen_color(screen0, suv), 1.0); }
			else if (screen_uv(homography1, p, suv)) { c = vec4(screen_color(screen1, suv), 1.0); }
			else if (screen_uv(homography2, p, suv)) { c = vec4(screen_color(screen2, suv), 1.0); }
			else if (screen_uv(homography3, p, suv)) { c = vec4(screen_color(screen3, suv), 1.0); }
			else if (screen_uv(homography4, p, suv)) { c = vec4(screen_color(screen4, suv), 1.0); }
			else if (screen_uv(homography5, p, suv)) { c = vec4(screen_color(screen5, suv), 1.0); }
			float e = min(min(p.x, image_size.x - p.x), min(p.y, image_size.y - p.y));
			float w = smoothstep(0.0, seam, e);
			col = mix(back, vec4(c.rgb * c.a, c.a), w);
		}
	}
	col.rgb /= max(col.a, 1e-4);
	col.rgb += glow * col.rgb;
	COLOR = col;
}
