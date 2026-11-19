class_name Cabin
extends Node3D
## Ohjaamo: etuseinänä ohjaamon kuva (assets/cockpit/ohjaamo.png) täsmälleen kuvan kuvakulmassa metrin päässä
## silmästä. Koska kamera vain kääntyy paikallaan, tasainen kuva näkyy oikein joka suuntaan katsottaessa. Kuva ja
## pelin näytöt sen päällä piirretään 2D-kerroksena (CockpitView, shaders/cockpit_overlay.gdshader), jotta kuvan
## värit säilyvät. Kuvan ympärillä näkyy ohjaamon 360°-panoraama (assets/cockpit/panoraama.webp), johon etukuva
## häivytetään reunoiltaan. Täällä ovat kuvan mitat, ikkunan ääriviiva, näyttöjen kulmat ja SubViewportit sekä
## lasi ikkunan takana.
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
## Ympäröivä 360°-panoraama (tasavälinen lieriöprojektio): 5824 × 2880 työpöydällä (sama pikselitiheys kuin
## etukuvassa), 4096 × 2048 selaimessa (muisti). Suurennettu käyttäjän kuvasta Real-ESRGANilla.
const PANORAMA := "res://assets/cockpit/panoraama.webp"
const PANORAMA_HIRES := "res://assets/cockpit/panoraama-6k.webp"


static func panorama_path() -> String:
	return PANORAMA_HIRES if not OS.has_feature("web") and ResourceLoader.exists(PANORAMA_HIRES) else PANORAMA

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
## Merkkivalot ovat kuvan valoja (assets/cockpit/ohjaamo_valot.png, B-kanava 1–6) tässä järjestyksessä; arvo 0–1.
const INDICATORS := ["moottori", "kiihdytys", "suunta", "vaikutuspiiri", "ilmakeha", "polttoaine"]
var lights := {}
var noise_tex: NoiseTexture2D
var scratch_tex: NoiseTexture2D


func _ready() -> void:
	noise_tex = _noise(512, 0.012, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 7)
	scratch_tex = _noise(512, 0.05, FastNoiseLite.TYPE_VALUE_CUBIC, 11)
	_build_image()
	_build_monitors()
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


func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi


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


## Näkyykö suunta d (aluksen koordinaateissa, silmästä) ohjaamon ikkunasta (panoraamassa ei ole ikkunoita).
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
	lights[name] = clampf(on, 0.0, 1.0)


## Merkkivalojen arvot INDICATORS-järjestyksessä (ohjaamon kuvan varjostimelle).
func indicator_values() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for n: String in INDICATORS:
		out.append(float(lights.get(n, 0.0)))
	return out
