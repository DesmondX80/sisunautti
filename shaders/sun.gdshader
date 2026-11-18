// Auringon kiekko: HDR-kirkas, reunat hieman tummemmat (reunatummeneminen).
shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

#include "res://shaders/space_depth.gdshaderinc"

uniform float brightness = 40.0;
uniform float visible = 1.0;

varying vec3 local_pos;
varying vec3 cam_local;

void vertex() {
	local_pos = VERTEX;
	// VERTEX-kirjoitus pakottaa Forward+:n syvyysesikierroksen käyttämään tätä varjostinta (DEPTH) eikä yhteistä
	// oletusmateriaalia, joka kirjoittaisi oikean syvyyden: väripass hylkäisi silloin pinnan (musta pallo ilman SSAO:ta).
	VERTEX = local_pos;
	cam_local = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
}

void fragment() {
	DEPTH = space_depth(VERTEX);
	float mu = max(dot(normalize(local_pos), normalize(cam_local - local_pos)), 0.0);
	float limb = 0.45 + 0.55 * pow(mu, 0.5);
	ALBEDO = vec3(1.0, 0.93, 0.82) * brightness * limb * visible;
}
