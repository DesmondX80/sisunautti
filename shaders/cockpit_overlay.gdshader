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
// reunalle image_edge, jolloin panoraaman kojelauta jää etukuvan taakse ja sen sivukonsolit jatkavat etukuvan
// konsoleita. Sivuilla ja takana kulmat puristuvat tasaisesti, suoraan taakse kuva on ennallaan.
uniform float pano_edge = 1.152; // 66°
// Ikkuna ulottuu etukuvan sivureunoihin: reunoilla ikkunan peittää kehyspilari (leveys px), jottei avaruus katkea
// sumeasti seinään.
uniform float frame_width = 56.0;
uniform float image_edge = 0.829;

vec3 panorama_color(vec3 d) {
	d = normalize(d);
	float lv = atan(d.x, -d.z);
	float a = abs(lv);
	float lp = a < image_edge ? a * pano_edge / image_edge : pano_edge + (a - image_edge) * (PI - pano_edge) / (PI - image_edge);
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

void fragment() {
	vec2 ndc = UV * 2.0 - 1.0;
	vec3 d = cam_basis * vec3(ndc.x * tan_half * aspect, -ndc.y * tan_half, -1.0);
	vec3 pano = panorama_color(d);
	vec4 col = vec4(pano, 1.0);
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
			// Ikkunan kohdalla ei häivytetä: ikkuna päättyy sivureunoilla terävään kehyspilariin (panoraaman seinän
			// sävyinen metalli, viistetty valoreuna ja varjo ikkunan puolella). Muu kuva häivytetään panoraamaan.
			float ex = min(p.x, image_size.x - p.x);
			float px = fwidth(p.x) + 1e-4;
			float pil = 1.0 - smoothstep(frame_width - px, frame_width + px, ex);
			float t = clamp(ex / frame_width, 0.0, 1.0);
			// Tumma metallirunko (kuten etukuvan ikkunakehys): pystysuuntainen sävy, paneelisaumat ja niitit.
			vec3 metal = mix(vec3(0.045, 0.05, 0.06), vec3(0.1, 0.11, 0.125), smoothstep(0.15, 0.85, t));
			metal *= 0.92 + 0.08 * sin(p.y * 0.21) * sin(p.y * 0.047);
			float panel = smoothstep(0.6, 0.0, abs(fract(p.y / 46.0) - 0.5) * 46.0 - 21.5);
			metal *= 1.0 - 0.35 * panel;
			float rivet = smoothstep(2.2, 1.2, length(vec2(ex - frame_width * 0.45, (fract(p.y / 23.0) - 0.5) * 23.0)));
			metal += vec3(0.12, 0.13, 0.15) * rivet;
			// Viistetty valoreuna ikkunan puolella ja tumma sauma lasia vasten.
			float bevel = exp(-pow((frame_width - 4.0 - ex) / 2.2, 2.0));
			metal += vec3(0.28, 0.4, 0.55) * bevel * 0.55;
			metal *= 1.0 - 0.7 * exp(-pow((frame_width - ex) / 1.0, 2.0));
			// Ulkoreunalla runko jatkuu panoraaman seinään.
			metal = mix(pano * 0.75, metal, smoothstep(0.0, 14.0, ex));
			float shade = (1.0 - pil) * 0.45 * exp(-max(ex - frame_width, 0.0) / 9.0);
			vec3 opaque = mix(pano, c.rgb, w);
			float win = 1.0 - c.a;
			float a_out = c.a + win * max(pil, shade);
			vec3 win_rgb = mix(vec3(0.0), metal, pil / max(max(pil, shade), 1e-4));
			col = vec4((c.a * opaque + win * max(pil, shade) * win_rgb) / max(a_out, 1e-4), a_out);
		}
	}
	col.rgb += glow * col.rgb;
	COLOR = col;
}
