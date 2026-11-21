class_name Space
extends Node3D
## Avaruus ohjaamon ympärillä: tähdet, Aurinko, planeetat ja kuut (web/js/cockpit.js).
##
## Mittakaavat: kamera on aina origossa (aluksen paikka), ja kappaleiden paikat lasketaan aluksen suhteen
## 64-bittisinä ennen kuin ne annetaan näytönohjaimelle 32-bittisinä. Lähellä (alle COMPRESS_M) kappaleet ovat
## oikeassa koossa ja paikassa (metreinä); kauempana etäisyys puristetaan logaritmisesti ja kappale pienennetään
## samassa suhteessa (skaalaus kameran ympäri), jolloin sen suunta ja näennäinen koko säilyvät ja kaikki mahtuu
## kaukotason (120 km) sisään. Avaruuden varjostimet kirjoittavat syvyysarvon aina ohjaamon taakse
## (shaders/space_depth.gdshaderinc), joten esimerkiksi laukaisualustan maanpinta ei näy ohjaamon sisällä.
## Koordinaatit: ekliptikan (x, y, z) → scene (x, z, −y), eli ekliptikan pohjoisnapa on ylöspäin.

const KM := 1000.0
const COMPRESS_M := 2.0e4
## Puristuksen jyrkkyys: Neptunus (4,5 mrd km) päätyy alle 100 km:n päähän.
const COMPRESS_K := 4.0e3
const OBLIQUITY := 23.4393 * PI / 180.0
const AU_M := Planets.AU_KM * KM
const STAR_DIST := 1.1e5
## Auringon leveän häikäisyn kulmasäde (rad) 1 AU:n etäisyydellä.
const HALO_AU := 0.03
# Pyöriminen (IAU 2015): nollameridiaanin kulma W = W0 + Ẇ · d (astetta, d vuorokausia J2000:sta) ja akselien
# pohjoisnavat (J2000: RA°, Dec°). Negatiivinen Ẇ = takaperoinen. Pintakartan keskikohta (pituusaste 0) osuu
# nollameridiaaniin, joten päivä ja yö ovat oikeissa kohdissa (esim. Maan yöpuoli oikeilla mantereilla).
const ROTATION := {"Merkurius": [329.5988, 6.1385108], "Venus": [160.20, -1.4813688], "Maa": [Flight.EARTH_W0, Flight.EARTH_W_DEG_DAY],
	"Mars": [176.049863, 350.891982443297], "Jupiter": [284.95, 870.5360000], "Saturnus": [38.90, 810.7939024],
	"Uranus": [203.81, -501.1600928], "Neptunus": [249.978, 541.1397757]}
const POLES := {"Merkurius": [281.01, 61.41], "Venus": [272.76, 67.16], "Maa": [0.0, 90.0], "Mars": [317.68, 52.89], "Jupiter": [268.06, 64.5],
	"Saturnus": [40.59, 83.54], "Uranus": [257.31, -15.18], "Neptunus": [299.36, 43.46]}
## Ilmakehät: väri, kuoren säde (planeetan säteinä), tiheys ja pinnan reunahehku.
const ATMOS := {
	"Maa": [Color(0.32, 0.58, 1.0), 1.022, 1.2, 0.9], "Venus": [Color(0.95, 0.82, 0.55), 1.03, 1.3, 0.8],
	"Mars": [Color(0.95, 0.6, 0.38), 1.02, 0.12, 0.25], "Titan": [Color(0.95, 0.62, 0.25), 1.12, 1.6, 1.0],
	"Jupiter": [Color(0.75, 0.78, 0.9), 1.008, 0.6, 0.5], "Saturnus": [Color(0.92, 0.85, 0.7), 1.01, 0.6, 0.5],
	"Uranus": [Color(0.6, 0.88, 0.95), 1.012, 0.8, 0.6], "Neptunus": [Color(0.42, 0.58, 1.0), 1.012, 0.8, 0.6]}
## Pölyn osuus ilmakehän sironnasta (eteenpäin sirottava vaihefunktio, atmosphere.gdshader).
const ATMO_DUST := {"Mars": 0.85}
const GIANTS := ["Jupiter", "Saturnus", "Uranus", "Neptunus"]
## Kaasujättiläisten pilvien pyörteily lähikuvassa (voimakkuus) ja värikylläisyys: pintakartta on lähellä vain
## muutama sata kuvapistettä ikkunan leveydellä ja näyttäisi muuten tasaisen harmaanvalkoiselta.
## Kolmas arvo on lähikuvan sävy (Jupiterin vaalea päiväntasaajavyöhyke on kartassa lähes valkoinen).
const CLOUD_DETAIL := {"Jupiter": [0.45, 1.3, Color(0.98, 0.87, 0.74)], "Saturnus": [0.25, 1.15, Color(1.0, 0.9, 0.72)],
	"Uranus": [0.06, 1.05, Color(1, 1, 1)], "Neptunus": [0.14, 1.1, Color(1, 1, 1)]}
## Kohokuviolliset kappaleet: korkeuskartan alue (m), rinteiden korostus (Marsin 1,3 km:n kartta pehmentää
## rinteitä), Lommel–Seeliger-osuus (ilmaton pöly 0,5, Marsin pöly
## ilmakehän alla lähes Lambert), pienten kraatterien voimakkuus, kirkkauden kontrasti ja värikylläisyys.
const RELIEF := {
	"Kuu": {"height": 4000.0, "normal": 1.0, "regolith": 0.5, "craters": 1.0, "contrast": 1.35, "saturation": 0.65},
	"Mars": {"height": 7000.0, "normal": 1.7, "regolith": 0.15, "craters": 0.55, "contrast": 1.3, "saturation": 1.0}}
# Kiekon säde pikseleinä, jolla kuva haetaan, jolla vaihdetaan tarkkaan karttaan ja jolla palataan takaisin.
const PHOTO_MIN_PX := 2.0
## Kaukaisten kappaleiden pisteiden näkyvyyskerros: kohdekamera (kaukoputki) ei näe niitä.
const DOT_LAYER := 8
## Kappaleen pallo lähipinnan ollessa käytössä (#45): pääkamera ei näe sitä (lähipinta korvaa), kaukoputki näkee.
const SPHERE_NEAR_LAYER := 16
const HIRES_PX := 200.0
const HIRES_BACK_PX := 120.0

var textures := BodyTextures.new()
var max_texture := 4096
var atmo_samples := 8
## Pinnan ja pilvien lähikuvan yksityiskohdat (0–1, laatutaso).
var surface_detail := 1.0
## Kuun varjojen askelmäärä korkeuskartalla (0 = ei varjoja, laatutaso).
var shadow_steps := 16
var bodies: Array[Dictionary] = []
var sun_root: Node3D
var sun_mesh: MeshInstance3D
var sun_glow: MeshInstance3D
var stars: MeshInstance3D
var star_material: ShaderMaterial
var noise_tex: NoiseTexture2D

## Viimeisimmän päivityksen tulokset ohjaamolle: Auringon suunta (scene), näkyvä osuus Auringon kiekosta,
## etäisyys Auringosta (m), lähin kappale ja sen näennäinen koko.
## Kappaleiden kirkkauskerroin (ilmajarrutuksen plasma himmentää näkymää).
var dim := 1.0
var sun_dir := Vector3.FORWARD
var sunlit := 1.0
var sun_distance := AU_M
var nearest: Dictionary = {}
var nearest_size := 0.0
## Kohdekameran kohde ja sen koko kamerakuvassa (px): kohteen pintakartta valitaan tämän mukaan, vaikka se
## näkyisi ikkunasta vain pisteenä.
var focus := ""
var focus_px := 0.0
## Kuun lähipinta (#45) ja ohjaamon tiedot sille: moottorin työntö ja onko alus pinnalla.
var surface: LunarSurface
var thrust := 0.0
var landed := false


static func to_scene(v: PackedFloat64Array) -> Vector3:
	return Vector3(v[0], v[2], -v[1])


static func equatorial(ra_hours: float, dec_deg: float) -> PackedFloat64Array:
	var ra := ra_hours * 15.0 * PI / 180.0
	var dec := dec_deg * PI / 180.0
	var x := cos(dec) * cos(ra)
	var y := cos(dec) * sin(ra)
	var z := sin(dec)
	return PackedFloat64Array([x, y * cos(OBLIQUITY) + z * sin(OBLIQUITY), -y * sin(OBLIQUITY) + z * cos(OBLIQUITY)])


## Päiväntasaajan koordinaattien (ICRF) yksikkövektori ekliptikan koordinaatteihin.
static func eq_to_ecliptic(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y * cos(OBLIQUITY) + z * sin(OBLIQUITY), -y * sin(OBLIQUITY) + z * cos(OBLIQUITY)])


## Kappaleen nollameridiaanin suunta päiväntasaajalla (scene) hetkellä t (ms): IAU:n W mitataan kappaleen
## päiväntasaajaa pitkin sen nousevasta solmusta ICRF:n päiväntasaajalla (RA = α + 90°).
static func prime_meridian(name: String, t: float) -> Vector3:
	var a := deg_to_rad(float(POLES[name][0]))
	var dec := deg_to_rad(float(POLES[name][1]))
	var rot: Array = ROTATION[name]
	var w := deg_to_rad(fposmod(float(rot[0]) + float(rot[1]) * (t - Planets.J2000_MS) / Fmt.DAY_MS, 360.0))
	var p := PackedFloat64Array([cos(dec) * cos(a), cos(dec) * sin(a), sin(dec)])
	var q := PackedFloat64Array([-sin(a), cos(a), 0.0])
	var pq := Flight.cross(p, q)
	var m := Flight.add(Flight.scale(q, cos(w)), Flight.scale(pq, sin(w)))
	return to_scene(eq_to_ecliptic(m[0], m[1], m[2])).normalized()


## Pyörähdyskulma akselin ympäri (spin-solmu), jolla pituusaste 0 (pallon −z) osuu nollameridiaaniin.
static func spin_angle_for(name: String, t: float) -> float:
	var pole := to_scene(equatorial(float(POLES[name][0]) / 15.0, float(POLES[name][1]))).normalized()
	var m := Basis(Quaternion(Vector3.UP, pole)).inverse() * prime_meridian(name, t)
	return atan2(-m.x, -m.z)


## Kierto scene-koordinaateista päiväntasaajan koordinaatteihin (taivaan panoraamaa varten).
static func scene_to_equatorial() -> Basis:
	# scene (x, y, z) = ekliptika (x, z, −y) → ekliptika (x, −z, y) → päiväntasaaja (kierto x-akselin ympäri).
	var to_ecl := Basis(Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, -1, 0)) # sarakkeet: scene x, y, z ekliptikassa
	var c := cos(OBLIQUITY)
	var s := sin(OBLIQUITY)
	var to_eq := Basis(Vector3(1, 0, 0), Vector3(0, c, s), Vector3(0, -s, c))
	return to_eq * to_ecl


## Puristettu etäisyys (m) ja skaala.
static func compress(d: float) -> float:
	return d if d <= COMPRESS_M else COMPRESS_M + COMPRESS_K * log(d / COMPRESS_M)


func _ready() -> void:
	noise_tex = NoiseTexture2D.new()
	noise_tex.seamless = true
	noise_tex.width = 512
	noise_tex.height = 512
	noise_tex.noise = FastNoiseLite.new()
	_build_stars()
	_build_sun()
	surface = LunarSurface.new()
	add_child(surface)
	for name in Planets.NAMES:
		var info := Planets.info(name)
		_build_body(name, info.radius_km, info.color, false)
	for m: String in Flight.MOONS:
		var md: Dictionary = Flight.MOONS[m]
		_build_body(m, md.radiusKm, Color(md.color), true)


func _exit_tree() -> void:
	textures.wait_all()


func _build_stars() -> void:
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/stars.json"))
	var verts := PackedVector3Array()
	var colors := PackedColorArray()
	for s: Array in list:
		var mag: float = s[3]
		var b := clampf(1.15 - mag * 0.25, 0.35, 1.0)
		verts.append(to_scene(equatorial(s[1], s[2])) * STAR_DIST)
		# Väri ja kirkkaus; alfa = koko.
		var e := pow(2.512, -mag) * 6.0 + 0.6
		colors.append(Color(b * e, b * e, minf(1.0, b * 1.05) * e, clampf(1.0 - (mag + 1.5) / 4.5, 0.0, 1.0)))
	# Himmeä tausta, joka tihenee Linnunradan tasoa kohti (satunnaiset tähdet, vain jakauma vastaa taivasta).
	var pole := equatorial(12.857, 27.128)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234567
	var faint := 0
	while faint < 3200:
		var z := rng.randf() * 2.0 - 1.0
		var a := rng.randf() * TAU
		var r := sqrt(1.0 - z * z)
		var v := PackedFloat64Array([r * cos(a), r * sin(a), z])
		var lat := asin(absf(v[0] * pole[0] + v[1] * pole[1] + v[2] * pole[2])) * 180.0 / PI
		if rng.randf() > 0.3 + 0.7 * exp(-pow(lat / 14.0, 2.0)):
			continue
		var l := 0.25 + rng.randf() * 0.35
		var tint := rng.randf()
		verts.append(to_scene(v) * STAR_DIST)
		colors.append(Color(l * (1.1 if tint > 0.8 else 0.95), l, l * (1.15 if tint < 0.2 else 1.0), 0.0))
		faint += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_POINTS, arrays)
	mesh.custom_aabb = AABB(Vector3.ONE * -STAR_DIST, Vector3.ONE * STAR_DIST * 2.0)
	star_material = ShaderMaterial.new()
	star_material.shader = load("res://shaders/stars.gdshader")
	stars = MeshInstance3D.new()
	stars.mesh = mesh
	stars.material_override = star_material
	stars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stars.extra_cull_margin = 16384.0
	add_child(stars)


func _build_sun() -> void:
	sun_root = Node3D.new()
	add_child(sun_root)
	sun_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = 48
	sm.rings = 24
	sun_mesh.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/sun.gdshader")
	sun_mesh.material_override = mat
	sun_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun_root.add_child(sun_mesh)
	sun_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	sun_glow.mesh = q
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/sun_glow.gdshader")
	sun_glow.material_override = gm
	sun_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sun_glow.extra_cull_margin = 1e6
	# Häikäisy syntyy silmässä ja lasissa: kohdekameran kaukoputki (aurinkosuodin) ei näe sitä.
	sun_glow.layers = DOT_LAYER
	sun_root.add_child(sun_glow)


func _sphere(segments: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = segments
	m.rings = segments / 2
	return m


func _build_body(name: String, radius_km: float, color: Color, moon: bool) -> void:
	var root := Node3D.new()
	root.name = name
	add_child(root)
	var tilt := Node3D.new()
	root.add_child(tilt)
	if POLES.has(name):
		var pole := to_scene(equatorial(POLES[name][0] / 15.0, POLES[name][1])).normalized()
		tilt.quaternion = Quaternion(Vector3.UP, pole)
	var spin := Node3D.new()
	tilt.add_child(spin)
	var mesh := MeshInstance3D.new()
	mesh.mesh = _sphere(160 if not moon else 96)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/planet.gdshader")
	var base := BodyTextures.file_for(name, 2048)
	var fallback: Texture2D = BodyTextures.drawn(name, color)
	mat.set_shader_parameter("albedo_tex", fallback)
	mat.set_shader_parameter("limb_darkening", 0.5 if GIANTS.has(name) else 0.0)
	if RELIEF.has(name):
		# Kohokuvio korkeusmallista (tools/make_moon_textures.py, tools/make_mars_textures.py), heijastusmalli ja
		# lähikuvan kraatterit.
		var r: Dictionary = RELIEF[name]
		mat.set_shader_parameter("relief", r.normal)
		mat.set_shader_parameter("relief_height", r.height)
		mat.set_shader_parameter("regolith", r.regolith)
		mat.set_shader_parameter("craters", r.craters)
		mat.set_shader_parameter("albedo_contrast", r.contrast)
		mat.set_shader_parameter("saturation", r.saturation)
		mat.set_shader_parameter("radius_m", radius_km * KM)
	if CLOUD_DETAIL.has(name):
		mat.set_shader_parameter("detail_strength", CLOUD_DETAIL[name][0])
		mat.set_shader_parameter("saturation", CLOUD_DETAIL[name][1])
		mat.set_shader_parameter("detail_tint", CLOUD_DETAIL[name][2])
	mesh.material_override = mat
	spin.add_child(mesh)
	var b := {"name": name, "radius_m": radius_km * KM, "color": color, "moon": moon, "root": root, "tilt": tilt, "spin": spin,
		"mesh": mesh, "mat": mat, "level": 0, "base": base, "hires": "", "fallback": fallback, "atmo": null, "clouds": null, "rings": null, "dot": null}
	if ATMOS.has(name):
		var a: Array = ATMOS[name]
		mat.set_shader_parameter("atmo_color", a[0])
		mat.set_shader_parameter("atmo_strength", a[3])
		var am := MeshInstance3D.new()
		am.mesh = _sphere(96)
		var amat := ShaderMaterial.new()
		amat.shader = load("res://shaders/atmosphere.gdshader")
		amat.set_shader_parameter("atmo_color", a[0])
		amat.set_shader_parameter("atmo_radius", a[1])
		amat.set_shader_parameter("density", a[2])
		amat.set_shader_parameter("mie", ATMO_DUST.get(name, 0.0))
		amat.render_priority = 1 # pilvien jälkeen
		am.material_override = amat
		am.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tilt.add_child(am)
		b.atmo = amat
	if name == "Maa":
		mat.set_shader_parameter("night_strength", 1.6)
		mat.set_shader_parameter("spec_strength", 1.0)
		b.night_path = BodyTextures.DIR + "maa-yo.webp"
		b.spec_path = BodyTextures.DIR + "maa-meri.webp"
		var cm := MeshInstance3D.new()
		cm.mesh = _sphere(128)
		cm.scale = Vector3.ONE * 1.004
		var cmat := ShaderMaterial.new()
		cmat.shader = load("res://shaders/clouds.gdshader")
		cm.material_override = cmat
		cm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var cspin := Node3D.new()
		tilt.add_child(cspin)
		cspin.add_child(cm)
		b.clouds = cmat
		b.cloud_spin = cspin
		b.cloud_path = BodyTextures.DIR + "maa-pilvet.webp"
	if RELIEF.has(name):
		b.relief_base = name.to_lower() + "-pinta"
		b.relief_path = BodyTextures.DIR + b.relief_base + ".webp"
	if name == "Saturnus":
		var rm := MeshInstance3D.new()
		rm.mesh = _ring_mesh(1.24, 2.27, 256)
		var rmat := ShaderMaterial.new()
		rmat.shader = load("res://shaders/rings.gdshader")
		rm.material_override = rmat
		rm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tilt.add_child(rm)
		b.rings = rmat
		mat.set_shader_parameter("has_rings", true)
	# Kaukainen kappale näkyy kirkkaana pisteenä.
	var dot := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	dot.mesh = q
	var dm := ShaderMaterial.new()
	dm.shader = load("res://shaders/billboard_glow.gdshader")
	dm.set_shader_parameter("color", color)
	dm.set_shader_parameter("energy", 1.6)
	dm.set_shader_parameter("min_pixels", 3.0)
	dm.set_shader_parameter("falloff", 1.5)
	dm.set_shader_parameter("core", 0.4)
	dot.material_override = dm
	dot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dot.extra_cull_margin = 1e6
	dot.layers = DOT_LAYER
	root.add_child(dot)
	b.dot = dot
	bodies.append(b)


func _ring_mesh(inner: float, outer: float, segments: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in segments + 1:
		var a := TAU * i / segments
		var d := Vector3(cos(a), 0.0, sin(a))
		verts.append(d * inner)
		verts.append(d * outer)
		uvs.append(Vector2(0, 0.5))
		uvs.append(Vector2(1, 0.5))
		if i < segments:
			var k := i * 2
			idx.append_array([k, k + 1, k + 2, k + 1, k + 3, k + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


# Osuus Auringon kiekosta, jonka sen edessä oleva kappale peittää: kahden ympyrän leikkausala jaettuna Auringon
# kiekon alalla (kulmasäteet ja keskipisteiden kulmaetäisyys).
static func covered(sun_r: float, body_r: float, sep: float) -> float:
	if sep >= sun_r + body_r:
		return 0.0
	if sep <= absf(body_r - sun_r):
		return 1.0 if body_r >= sun_r else pow(body_r / sun_r, 2.0)
	var a := sun_r * sun_r
	var b := body_r * body_r
	var lens := a * acos(clampf((sep * sep + a - b) / (2.0 * sep * sun_r), -1.0, 1.0)) + b * acos(clampf((sep * sep + b - a) / (2.0 * sep * body_r), -1.0, 1.0)) \
		- 0.5 * sqrt(maxf(0.0, (-sep + sun_r + body_r) * (sep + sun_r - body_r) * (sep - sun_r + body_r) * (sep + sun_r + body_r)))
	return lens / (PI * a)


## Päivittää kappaleiden paikat ja valaistuksen. ship_km: aluksen paikka (km, Auringon suhteen), t: hetki (ms),
## px_per_rad: pikseliä radiaania kohden (kiekon koko ruudulla).
func update(ship_km: PackedFloat64Array, t: float, px_per_rad: float) -> void:
	if textures.poll():
		for b in bodies:
			_apply_textures(b)
	# Aurinko
	var sun_rel := Flight.scale(ship_km, -KM) # m, Auringon paikka aluksesta
	var sun_vec := to_scene(sun_rel)
	sun_distance = Flight.norm(sun_rel)
	sun_dir = sun_vec.normalized()
	var sd := compress(sun_distance)
	var sk := sd / sun_distance
	sun_root.position = sun_dir * sd
	sun_mesh.scale = Vector3.ONE * Planets.SUN_RADIUS_KM * KM * sk
	var sun_ang := asin(minf(1.0, Planets.SUN_RADIUS_KM * KM / sun_distance))
	var sun_mat := sun_mesh.material_override as ShaderMaterial
	sun_mat.set_shader_parameter("sim_days", fmod((t - Planets.J2000_MS) / Fmt.DAY_MS, 36000.0))
	sunlit = 1.0
	nearest = {}
	nearest_size = 0.0
	for b in bodies:
		var name: String = b.name
		var body_km: PackedFloat64Array = Flight.body_state(name, t).r
		var rel := Flight.scale(Flight.sub(body_km, ship_km), KM)
		var d := Flight.norm(rel)
		if d < 1.0: # alus kappaleen keskipisteessä (ei pelissä, mutta vältetään nollalla jako)
			rel = PackedFloat64Array([0.0, 0.0, 1.0])
			d = 1.0
		var dir := to_scene(rel) / d
		var cd := compress(d)
		var k := cd / d
		var radius: float = b.radius_m
		var root: Node3D = b.root
		root.position = dir * cd
		var size := radius / d # kulmasäde (rad, pienillä kulmilla)
		if size > nearest_size:
			nearest_size = size
			nearest = b
		if d < sun_distance:
			sunlit *= 1.0 - covered(sun_ang, asin(minf(1.0, radius / d)), dir.angle_to(sun_dir))
		(b.tilt as Node3D).scale = Vector3.ONE * radius * k
		# Pyöriminen: kuut kääntävät aina saman puolen planeettaansa kohti.
		var spin_angle: float
		if b.moon:
			# Lähipuoli (pituusaste 0, kartan keskikohta, pallon −z) kohti emoplaneettaa; libraatiota ei mallinneta.
			var to_parent := to_scene(Flight.sub(Flight.body_state(Flight.MOONS[name].parent, t).r, body_km))
			spin_angle = atan2(-to_parent.x, -to_parent.z)
		else:
			spin_angle = spin_angle_for(name, t)
		(b.spin as Node3D).basis = Basis(Vector3.UP, spin_angle)
		if b.has("cloud_spin"):
			# Pilvet ajelehtivat hitaasti pinnan suhteen (kierros 40 vuorokaudessa).
			(b.cloud_spin as Node3D).basis = Basis(Vector3.UP, spin_angle + 0.4 + TAU * fposmod(t / Fmt.DAY_MS / 40.0, 1.0))
		# Valaistus kappaleen koordinaatistossa: suunta kappaleesta Aurinkoon.
		var to_sun := to_scene(Flight.scale(body_km, -1.0)).normalized()
		var mesh: MeshInstance3D = b.mesh
		var inv := mesh.global_transform.basis.orthonormalized().inverse()
		var sun_local := inv * to_sun
		var body_sun_d := Flight.norm(body_km) * KM
		var intensity := 1.5 * clampf(pow(AU_M / body_sun_d, 0.5), 0.3, 1.5) * dim
		if Landing.can_land(name):
			var em: ShaderMaterial = b.mat
			var earth_km: PackedFloat64Array = Flight.body_state(Flight.MOONS[name].parent, t).r
			surface.update_surface(b, -dir * d, d, to_sun, to_scene(Flight.sub(earth_km, ship_km)).normalized(), intensity,
				float(em.get_shader_parameter("earthshine")) if em.get_shader_parameter("earthshine") != null else 0.0, thrust, landed, sunlit)
		var mat: ShaderMaterial = b.mat
		mat.set_shader_parameter("sun_local", sun_local)
		mat.set_shader_parameter("sun_intensity", intensity)
		var tilt_inv := (b.tilt as Node3D).global_transform.basis.orthonormalized().inverse()
		var sun_tilt := tilt_inv * to_sun
		if b.atmo != null:
			b.atmo.set_shader_parameter("sun_local", sun_tilt)
			b.atmo.set_shader_parameter("sun_intensity", intensity)
			b.atmo.set_shader_parameter("samples", atmo_samples)
		if not GIANTS.has(b.name):
			(b.mat as ShaderMaterial).set_shader_parameter("surface_detail", surface_detail)
		if b.has("relief_path"):
			mat.set_shader_parameter("shadow_steps", shadow_steps)
			if name == "Kuu":
				_earthshine(b, body_km, inv, t)
		if b.clouds != null:
			var cinv := (b.cloud_spin as Node3D).global_transform.basis.orthonormalized().inverse()
			b.clouds.set_shader_parameter("sun_local", cinv * to_sun)
			b.clouds.set_shader_parameter("sun_intensity", intensity)
			b.clouds.set_shader_parameter("surface_detail", surface_detail)
		if b.rings != null:
			b.rings.set_shader_parameter("sun_local", sun_tilt)
			b.rings.set_shader_parameter("sun_intensity", intensity)
		# Kaukainen kappale pisteenä; kuun piste vain alle 20 milj. km päästä.
		var px := size * px_per_rad
		(b.dot as Node3D).visible = px < 2.0 and (not b.moon or d < 2e10)
		(b.dot as Node3D).scale = Vector3.ONE * radius * k
		_texture_level(b, maxf(px, focus_px) if name == focus else px)
	_update_sun_glow(sun_ang, sd)


## Auringon häikäisyn koko ja kirkkaus valon määrän mukaan (säteilyvuo F = (1 AU / d)²): leveän hehkun kulmasäde
## kasvaa kuten √F (Maan etäisyydellä 3,2°) ja kirkkaus kuten F^0,35 (silmä mukautuu, kuten light_factor). Korona ja
## kiekon reuna ovat Auringon säteinä, joten ne näkyvät oikean kokoisina kaikilta etäisyyksiltä.
func _update_sun_glow(sun_ang: float, sd: float) -> void:
	var flux := pow(AU_M / sun_distance, 2.0)
	var halo_ang := HALO_AU * sqrt(flux)
	var quad_ang := minf(1.2, maxf(halo_ang * 3.4, sun_ang * 6.0))
	var tq := tan(quad_ang)
	sun_glow.scale = Vector3.ONE * tq * sd
	var gm := sun_glow.material_override as ShaderMaterial
	gm.set_shader_parameter("disk_frac", tan(sun_ang) / tq)
	gm.set_shader_parameter("halo_frac", tan(halo_ang) / tq)
	gm.set_shader_parameter("energy", 1.2 * pow(flux, 0.35) * dim)
	gm.set_shader_parameter("core_energy", 12.0 * pow(flux, 0.1) * dim)
	gm.set_shader_parameter("visible", sunlit)


## Valon voimakkuuskerroin ohjaamossa ja häikäisyssä etäisyyden d (m) mukaan: säteilyvuo (1 AU / d)² korotettuna
## potenssiin 0,35, koska silmä mukautuu (Jupiterilla 0,32, Neptunuksella 0,09, Merkuriuksella 1,8).
static func light_factor(d: float) -> float:
	return clampf(pow(AU_M / d, 0.7), 0.08, 1.8)


func _texture_level(b: Dictionary, px: float) -> void:
	var name: String = b.name
	if name == "Titan":
		return
	var level: int = b.level
	var hires_w := BodyTextures.best_width(name, max_texture)
	if level == 0 and px > PHOTO_MIN_PX:
		b.level = 2 if hires_w > 2048 and px > HIRES_PX else 1
	elif level == 1 and hires_w > 2048 and px > HIRES_PX:
		b.level = 2
	elif level == 2 and px < HIRES_BACK_PX:
		b.level = 1
	if b.level != level:
		var old: String = b.hires
		b.hires = BodyTextures.file_for(name, hires_w) if b.level == 2 else ""
		if old != "" and old != b.hires:
			textures.release(old)
		_apply_textures(b)


## Maanvalo Kuun yöpuolella: Maan valaistu osuus Kuusta katsottuna (täysi maa, kun Kuu on uusi) ja suunta.
## Täysimaan valo on Kuun pinnalla noin 50 kertaa täysikuun valoa kirkkaampi, mutta silti vain promilleja auringonvalosta.
func _earthshine(b: Dictionary, moon_km: PackedFloat64Array, inv: Basis, t: float) -> void:
	var earth_km: PackedFloat64Array = Flight.body_state("Maa", t).r
	var to_earth := Flight.sub(earth_km, moon_km)
	var de := Flight.norm(to_earth)
	var cos_phase := -Flight.dot(earth_km, to_earth) / (Flight.norm(earth_km) * de) # Maa→Aurinko · Maa→Kuu
	var lit := 0.5 * (1.0 + cos_phase)
	var mat: ShaderMaterial = b.mat
	mat.set_shader_parameter("earth_local", inv * to_scene(Flight.scale(to_earth, 1.0 / de)))
	mat.set_shader_parameter("earthshine", 0.035 * lit * dim)


## Maan yö- tai pilvikartta tai Kuun kohokuvio tasolle: lähellä tarkin (8k, jos laatutaso sallii ja tiedosto on mukana, muuten 4k).
func _layer_map(base: String, level: int) -> String:
	if level == 2:
		var hi := BodyTextures.DIR + base + "-8k.webp"
		if max_texture >= 8192 and BodyTextures.exists(hi):
			return hi
		return BodyTextures.DIR + base + "-4k.webp"
	return BodyTextures.DIR + base + ".webp"


func _apply_textures(b: Dictionary) -> void:
	if b.level == 0:
		return
	var mat: ShaderMaterial = b.mat
	var tex: Texture2D = null
	if b.hires != "":
		tex = textures.get_texture(b.hires)
	if tex == null:
		tex = textures.get_texture(b.base)
	if tex != null:
		mat.set_shader_parameter("albedo_tex", tex)
	if b.has("night_path"):
		var n := textures.get_texture(_layer_map("maa-yo", b.level))
		if n == null:
			n = textures.get_texture(b.night_path)
		if n != null:
			mat.set_shader_parameter("night_tex", n)
		var s := textures.get_texture(b.spec_path)
		if s != null:
			mat.set_shader_parameter("spec_tex", s)
	if b.has("relief_path"):
		var rt := textures.get_texture(_layer_map(b.relief_base, b.level))
		if rt == null:
			rt = textures.get_texture(b.relief_path)
		if rt != null:
			mat.set_shader_parameter("relief_tex", rt)
	if b.clouds != null:
		var c := textures.get_texture(_layer_map("maa-pilvet", b.level))
		if c == null:
			c = textures.get_texture(b.cloud_path)
		if c != null:
			b.clouds.set_shader_parameter("cloud_tex", c)
			mat.set_shader_parameter("cloud_tex", c)
			mat.set_shader_parameter("cloud_shadow", 0.35)
	if b.rings != null:
		var r := textures.get_texture(BodyTextures.DIR + "saturnus-renkaat.webp")
		if r != null:
			b.rings.set_shader_parameter("ring_tex", r)
			mat.set_shader_parameter("ring_tex", r)
