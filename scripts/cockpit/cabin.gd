class_name Cabin
extends Node3D
## Ohjaamo: etuseinänä ohjaamon kuva (assets/cockpit/ohjaamo.png) täsmälleen kuvan kuvakulmassa metrin päässä
## silmästä. Koska kamera vain kääntyy paikallaan, tasainen kuva näkyy oikein joka suuntaan katsottaessa. Kuva ja
## pelin näytöt sen päällä piirretään 2D-kerroksena (CockpitView, shaders/cockpit_overlay.gdshader), jotta kuvan
## värit säilyvät; täällä ovat kuvan mitat, ikkunan ääriviiva, näyttöjen kulmat ja SubViewportit, lasi ikkunan
## takana sekä kuvan reunojen ulkopuolella jatkuva tumma sisätila (seinät, katto, lattia).
## Yksikkö metri; silmä origossa, katse −z, ylös +y.

## Kuvan koko, polttoväli ja keskipiste pikseleinä (vaakakuvakulma noin 95°).
const IMAGE_SIZE := Vector2(1382, 777)
const FOCAL := 633.0
const CENTER := Vector2(691.0, 388.5)
## Ikkunan ääriviiva kuvassa (pikselit), sama kuin kuvan alfakanavassa.
const WINDOW := [Vector2(100, 73), Vector2(200, 76), Vector2(280, 82), Vector2(430, 95), Vector2(560, 120), Vector2(590, 127),
	Vector2(700, 131), Vector2(780, 130), Vector2(810, 122), Vector2(880, 102), Vector2(1000, 92), Vector2(1100, 84), Vector2(1200, 77),
	Vector2(1299, 73), Vector2(1340, 95), Vector2(1379, 133), Vector2(1379, 205), Vector2(1335, 290), Vector2(1289, 367), Vector2(1275, 375),
	Vector2(1240, 376), Vector2(1100, 374), Vector2(1015, 371), Vector2(1012, 362), Vector2(820, 362), Vector2(815, 346), Vector2(570, 346),
	Vector2(565, 362), Vector2(380, 362), Vector2(375, 370), Vector2(133, 377), Vector2(110, 370), Vector2(60, 280), Vector2(7, 190),
	Vector2(7, 157), Vector2(13, 137), Vector2(40, 105), Vector2(73, 76)]
## Näytöt vasemmalta oikealle ja keskikonsolin pikkunäyttö: tyyppi ja näyttöpinnan kulmat kuvassa
## (vasen ylä, oikea ylä, oikea ala, vasen ala).
const MONITORS := [
	["nav", [Vector2(188, 413), Vector2(361, 391), Vector2(372, 481), Vector2(201, 517)]],
	["ship", [Vector2(400, 382), Vector2(545, 375), Vector2(550, 460), Vector2(407, 472)]],
	["target", [Vector2(588, 362), Vector2(808, 362), Vector2(808, 455), Vector2(587, 453)]],
	["systems", [Vector2(840, 372), Vector2(997, 382), Vector2(993, 470), Vector2(837, 458)]],
	["camera", [Vector2(1032, 392), Vector2(1218, 402), Vector2(1210, 517), Vector2(1025, 485)]],
	["mini", [Vector2(660, 480), Vector2(727, 480), Vector2(727, 501), Vector2(660, 501)]],
]
const SCREEN_WIDTH := 1024

## Kolme päänäyttöä pelin tilan näyttörivien järjestyksessä (aika, nopeus, kohde).
var screens: Array[CockpitScreen] = []
var nav_screen: CockpitScreen
var systems_screen: CockpitScreen
var mini_screen: CockpitScreen
## Kaikki näytöt: {"corners": PackedVector3Array (ohjaamon koordinaatit, zoomaus), "screen": CockpitScreen,
## "texture": näytön kuva, "homography": Basis kuvan pikselistä näytön UV:ksi}.
var monitors: Array[Dictionary] = []
var glass_material: ShaderMaterial
var plasma_material: ShaderMaterial
var plasma: Node3D
var lights := {} # merkkivalot ovat osa kuvaa
var noise_tex: NoiseTexture2D
var scratch_tex: NoiseTexture2D

var plate: ShaderMaterial
var dark: ShaderMaterial
var hull: ShaderMaterial
var led_blue: StandardMaterial3D


func _ready() -> void:
	noise_tex = _noise(512, 0.012, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 7)
	scratch_tex = _noise(512, 0.05, FastNoiseLite.TYPE_VALUE_CUBIC, 11)
	plate = _metal(Color(0.22, 0.23, 0.26), 0.7, 0.45, 0.5, 0.35)
	dark = _metal(Color(0.09, 0.1, 0.11), 0.55, 0.5, 0.4, 0.25)
	hull = _metal(Color(0.06, 0.065, 0.075), 0.35, 0.65, 0.3, 0.5)
	led_blue = StandardMaterial3D.new()
	led_blue.albedo_color = Color(0.08, 0.2, 0.3)
	led_blue.emission_enabled = true
	led_blue.emission = Color(0.25, 0.62, 1.0)
	led_blue.emission_energy_multiplier = 1.2
	_build_image()
	_build_monitors()
	_build_room()
	_build_plasma()


# --- Materiaalit ja apufunktiot ---

func _noise(size: int, freq: float, type: int, seed: int) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.generate_mipmaps = true
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.frequency = freq
	n.seed = seed
	n.fractal_octaves = 4
	t.noise = n
	return t


func _metal(color: Color, metallic: float, roughness: float, panel: float, wear: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/worn_metal.gdshader")
	m.set_shader_parameter("base_color", color)
	m.set_shader_parameter("metallic", metallic)
	m.set_shader_parameter("roughness", roughness)
	m.set_shader_parameter("panel_size", panel)
	m.set_shader_parameter("wear", wear)
	m.set_shader_parameter("noise", noise_tex)
	m.set_shader_parameter("scratch_noise", scratch_tex)
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


func _box(size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, mat, pos, rot)


## Kuvan pikseli suunnaksi silmästä (z = −1 -tasolla).
static func image_ray(p: Vector2) -> Vector3:
	return Vector3((p.x - CENTER.x) / FOCAL, -(p.y - CENTER.y) / FOCAL, -1.0)


## Suunta (ohjaamon koordinaateissa) kuvan pikseliksi; Vector2(-1, -1), jos suunta on kuvan takana.
static func image_point(d: Vector3) -> Vector2:
	if d.z >= -1e-6:
		return Vector2(-1, -1)
	return Vector2(CENTER.x + d.x / -d.z * FOCAL, CENTER.y - d.y / -d.z * FOCAL)


## Suunnikas, jonka kulmat näkyvät kuvassa pisteissä q (vasen ylä, oikea ylä, oikea ala, vasen ala): kulmien
## etäisyydet ratkaistaan ehdosta P0 + P2 = P1 + P3, ja taso skaalataan kuvatason eteen (enintään 0,97 m).
static func parallelogram(q: Array) -> PackedVector3Array:
	var r: Array[Vector3] = []
	for p: Vector2 in q:
		r.append(image_ray(p))
	# t2 r2 − t1 r1 − t3 r3 = −r0 (t0 = 1)
	var t := Basis(r[2], -r[1], -r[3]).inverse() * -r[0]
	var ts := [1.0, t.y, t.x, t.z]
	var k := 0.97 / maxf(maxf(ts[0], ts[1]), maxf(ts[2], ts[3]))
	var out := PackedVector3Array()
	for i in 4:
		out.append(r[i] * float(ts[i]) * k)
	return out


## Näkyykö suunta d (aluksen koordinaateissa, silmästä) ohjaamon ikkunasta.
static func through_window(d: Vector3) -> bool:
	var p := image_point(d)
	return p.x >= 0.0 and Geometry2D.is_point_in_polygon(p, PackedVector2Array(WINDOW))


# --- Rakenne ---

## Projektiivinen kuvaus kuvan pikselistä näytön UV:ksi (0–1), kun näytön kulmat ovat kuvassa pisteissä q
## (vasen ylä, oikea ylä, oikea ala, vasen ala): neliöstä nelikulmioon -kuvauksen käänteiskuvaus.
static func homography(q: Array) -> Basis:
	var p0: Vector2 = q[0]
	var p1: Vector2 = q[1]
	var p2: Vector2 = q[2]
	var p3: Vector2 = q[3]
	var d1 := p1 - p2
	var d2 := p3 - p2
	var d3 := p0 - p1 + p2 - p3
	var den := d1.x * d2.y - d2.x * d1.y
	var g := (d3.x * d2.y - d2.x * d3.y) / den
	var h := (d1.x * d3.y - d3.x * d1.y) / den
	var m := Basis(Vector3(p1.x - p0.x + g * p1.x, p1.y - p0.y + g * p1.y, g),
		Vector3(p3.x - p0.x + h * p3.x, p3.y - p0.y + h * p3.y, h), Vector3(p0.x, p0.y, 1.0))
	return m.inverse()


func _build_image() -> void:
	var size := IMAGE_SIZE / FOCAL
	# Lasi kuvatason takana: likaa, naarmuja ja Auringon häikäisy ikkuna-alueella.
	glass_material = ShaderMaterial.new()
	glass_material.shader = load("res://shaders/glass.gdshader")
	glass_material.set_shader_parameter("dirt", noise_tex)
	glass_material.set_shader_parameter("scratch_noise", scratch_tex)
	var g := QuadMesh.new()
	g.size = size * 1.02
	var gi := _mesh(g, glass_material, Vector3(0, 0, -1.02))
	gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_monitors() -> void:
	for m: Array in MONITORS:
		var corners := parallelogram(m[1])
		var w := corners[0].distance_to(corners[1])
		var h := corners[0].distance_to(corners[3])
		var vp := SubViewport.new()
		vp.size = Vector2i(SCREEN_WIDTH, roundi(SCREEN_WIDTH * h / w))
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		vp.disable_3d = true
		add_child(vp)
		var screen := CockpitScreen.new()
		screen.kind = m[0]
		screen.view_size = Vector2(vp.size)
		vp.add_child(screen)
		monitors.append({"corners": corners, "screen": screen, "texture": vp.get_texture(), "homography": homography(m[1])})
		match String(m[0]):
			"nav": nav_screen = screen
			"systems": systems_screen = screen
			"mini": mini_screen = screen
			_: screens.append(screen)


func _build_room() -> void:
	# Kuvan reunojen ulkopuolinen sisätila: seinät, katto, lattia ja takaseinä kuvan näkökartion ulkopuolella
	# (|x| > 1,09 |z| tai |y| > 0,61 |z|), jotta mikään ei peitä kuvaa.
	var hw := IMAGE_SIZE.x / 2.0 / FOCAL
	var hh := IMAGE_SIZE.y / 2.0 / FOCAL
	var top := 0.72
	var bottom := -0.76
	var side := 1.22
	# Etuseinän kehys kuvan ympärillä.
	_box(Vector3(side * 2.0, top - hh, 0.04), hull, Vector3(0, (top + hh) / 2.0, -1.02))
	_box(Vector3(side * 2.0, -hh - bottom, 0.04), hull, Vector3(0, (bottom - hh) / 2.0, -1.02))
	for s: float in [-1.0, 1.0]:
		_box(Vector3(side - hw, hh * 2.0, 0.04), hull, Vector3(s * (side + hw) / 2.0, 0, -1.02))
	_box(Vector3(side * 2.0, 0.06, 2.4), hull, Vector3(0, top + 0.03, 0.18))
	_box(Vector3(side * 2.0, 0.06, 2.4), plate, Vector3(0, bottom - 0.03, 0.18))
	_box(Vector3(side * 2.0, top - bottom, 0.06), hull, Vector3(0, (top + bottom) / 2.0, 1.4))
	for s: float in [-1.0, 1.0]:
		_box(Vector3(0.06, top - bottom, 2.4), hull, Vector3(s * (side + 0.03), (top + bottom) / 2.0, 0.18))
		# Sivukonsoli, paneelit ja valolistat seinällä.
		_box(Vector3(0.16, 0.5, 2.2), dark, Vector3(s * (side - 0.08), bottom + 0.25, 0.1))
		_box(Vector3(0.2, 0.03, 2.2), plate, Vector3(s * (side - 0.1), bottom + 0.5, 0.1), Vector3(0, 0, s * -0.3))
		for i in 4:
			var z := -0.75 + i * 0.5
			_box(Vector3(0.03, 0.34, 0.4), dark, Vector3(s * (side - 0.01), 0.15, z))
			_box(Vector3(0.012, 0.02, 0.3), led_blue, Vector3(s * (side - 0.03), 0.3, z))
		_box(Vector3(0.012, 0.018, 2.2), led_blue, Vector3(s * (side - 0.17), bottom + 0.52, 0.1))
	_box(Vector3(1.2, 0.012, 0.03), led_blue, Vector3(0, top - 0.01, 0.4))


func _build_plasma() -> void:
	# Ilmajarrutuksen plasma: hehkuva taso ikkunan takana.
	plasma_material = ShaderMaterial.new()
	plasma_material.shader = load("res://shaders/plasma.gdshader")
	plasma_material.set_shader_parameter("noise", noise_tex)
	plasma = Node3D.new()
	add_child(plasma)
	var q := QuadMesh.new()
	q.size = Vector2(5.0, 3.0)
	var m := MeshInstance3D.new()
	m.mesh = q
	m.material_override = plasma_material
	m.position = Vector3(0, 0, -1.5)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plasma.add_child(m)
	plasma.visible = false


## Merkkivalojen kirkkaus (0–1) nimen mukaan (kuvassa valot ovat kiinteitä).
func set_light(name: String, on: float) -> void:
	var m: StandardMaterial3D = lights.get(name)
	if m != null:
		m.emission_energy_multiplier = on * 3.0
