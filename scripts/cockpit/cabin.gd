class_name Cabin
extends Node3D
## Ohjaamon sisätila koodilla (PBR-materiaalein): leveä panoraamaikkuna raskaine kehyksineen, yläkehyksen
## paneelit sinisine valolistoineen, kaareva kojelauta viisine näyttöineen ja painikeriveineen, keskikonsoli
## pikkunäyttöineen, ohjainsauvat ja lentäjän kädet, istuimen niskatuki etualalla sekä sivukonsolit painikkeineen.
## Kiinteät osat kootaan materiaaleittain yhdeksi verkoksi (vähän piirtokutsuja); liikkuvat osat, merkkivalot ja
## näytöt ovat omia solmujaan. Yksikkö metri; katse origossa lentäjän takana, katse −z, ylös +y.

const SCREEN_SIZE := Vector2i(1024, 576)
## Etulasi: taso, puolileveys sekä ala- ja yläreuna.
const WIN_Z := -1.75
const WIN_HALF_W := 1.95
const WIN_BOTTOM := -0.02
const WIN_TOP := 0.86
## Kylkilasit: x-taso, z-väli ja y-väli.
const SIDE_X := 2.4
const SIDE_Z := Vector2(-1.55, -0.55)
const SIDE_Y := Vector2(0.0, 0.75)
## Kojelaudan näytöt vasemmalta oikealle: [tyyppi, vaakakulma °, pystykulma °, etäisyys, leveys].
const MONITORS := [["nav", -36.5, -5.0, 1.05, 0.31], ["ship", -20.0, -3.2, 1.18, 0.3], ["target", 0.0, -2.0, 1.25, 0.46],
	["systems", 20.0, -3.2, 1.18, 0.3], ["camera", 36.5, -5.0, 1.05, 0.31]]

## Kolme päänäyttöä pelin tilan näyttörivien järjestyksessä (aika, nopeus, kohde).
var screens: Array[CockpitScreen] = []
var nav_screen: CockpitScreen
var systems_screen: CockpitScreen
var mini_screen: CockpitScreen
## Kaikki näytöt zoomausta varten: {"node": Node3D, "size": Vector2, "screen": CockpitScreen}.
var monitors: Array[Dictionary] = []
var glass_material: ShaderMaterial
var plasma_material: ShaderMaterial
var plasma: Node3D
var lights := {} # nimi → StandardMaterial3D (merkkivalot)
var throttle: Node3D
var stick: Node3D
var noise_tex: NoiseTexture2D
var scratch_tex: NoiseTexture2D

var steel: ShaderMaterial
var plate: ShaderMaterial
var dark: ShaderMaterial
var hull: ShaderMaterial
var rubber: StandardMaterial3D
var fabric: StandardMaterial3D
var suit: StandardMaterial3D
var bezel: StandardMaterial3D
var floor_mat: ShaderMaterial
var led_blue: StandardMaterial3D
var led_white: StandardMaterial3D
var keys: Array[Material] = [] # painikkeiden värit: tumma, sininen, valkoinen, punainen, keltainen, vihreä

var _batches := {} # Material → SurfaceTool
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7
	noise_tex = _noise(512, 0.012, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 7)
	scratch_tex = _noise(512, 0.05, FastNoiseLite.TYPE_VALUE_CUBIC, 11)
	steel = _metal(Color(0.5, 0.53, 0.58), 0.8, 0.38, 0.55, 0.45)
	plate = _metal(Color(0.3, 0.32, 0.36), 0.7, 0.45, 0.6, 0.35)
	dark = _metal(Color(0.12, 0.13, 0.15), 0.55, 0.5, 0.5, 0.25)
	hull = _metal(Color(0.075, 0.08, 0.095), 0.35, 0.65, 0.35, 0.5)
	floor_mat = _metal(Color(0.2, 0.21, 0.23), 0.7, 0.45, 0.8, 0.15)
	floor_mat.set_shader_parameter("rivets", 0.0)
	rubber = StandardMaterial3D.new()
	rubber.albedo_color = Color(0.035, 0.037, 0.042)
	rubber.roughness = 0.7
	rubber.normal_enabled = true
	rubber.normal_texture = _noise(256, 0.08, FastNoiseLite.TYPE_SIMPLEX, 3, true)
	rubber.normal_scale = 0.3
	fabric = StandardMaterial3D.new()
	fabric.albedo_color = Color(0.035, 0.037, 0.042)
	fabric.roughness = 0.75
	fabric.normal_enabled = true
	fabric.normal_texture = _noise(256, 0.3, FastNoiseLite.TYPE_CELLULAR, 5, true)
	fabric.normal_scale = 0.5
	fabric.uv1_triplanar = true
	fabric.uv1_scale = Vector3(6, 6, 6)
	suit = fabric.duplicate()
	suit.albedo_color = Color(0.07, 0.073, 0.08)
	suit.roughness = 0.6
	suit.uv1_scale = Vector3(14, 14, 14)
	bezel = StandardMaterial3D.new()
	bezel.albedo_color = Color(0.025, 0.028, 0.032)
	bezel.roughness = 0.32
	bezel.metallic = 0.5
	led_blue = _emissive(Color(0.25, 0.62, 1.0), 2.6)
	led_white = _emissive(Color(0.85, 0.92, 1.0), 2.0)
	keys = [dark, _emissive(Color(0.25, 0.6, 1.0), 1.1), _emissive(Color(0.7, 0.85, 1.0), 0.8), _emissive(Color(1.0, 0.22, 0.18), 1.3),
		_emissive(Color(1.0, 0.65, 0.2), 1.0), _emissive(Color(0.3, 1.0, 0.5), 0.9)]
	_build_frame()
	_build_glass()
	_build_dashboard()
	_build_center()
	_build_sides()
	_build_pilot()
	_build_plasma()
	_commit()


# --- Materiaalit ---

func _noise(size: int, freq: float, type: int, seed: int, normal: bool = false) -> NoiseTexture2D:
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.as_normal_map = normal
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


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color * 0.3
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m


# --- Kokoaminen ---

## Lisää verkon kiinteään yhdistelmäverkkoon materiaalin mukaan.
func _add(mesh: Mesh, mat: Material, xf: Transform3D) -> void:
	var st: SurfaceTool = _batches.get(mat)
	if st == null:
		st = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[mat] = st
	st.append_from(mesh, 0, xf)


func _commit() -> void:
	for mat: Material in _batches:
		var mi := MeshInstance3D.new()
		mi.mesh = (_batches[mat] as SurfaceTool).commit()
		mi.material_override = mat
		if mat == led_blue or mat == led_white or keys.has(mat) and mat != dark:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	_batches.clear()


func _xf(pos: Vector3, rot: Vector3 = Vector3.ZERO) -> Transform3D:
	return Transform3D(Basis.from_euler(rot), pos)


func _box(size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, base: Transform3D = Transform3D.IDENTITY) -> void:
	var b := BoxMesh.new()
	b.size = size
	_add(b, mat, base * _xf(pos, rot))


func _cyl(r_top: float, r_bottom: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, base: Transform3D = Transform3D.IDENTITY, segs: int = 20) -> void:
	_add(_cyl_mesh(r_top, r_bottom, h, segs), mat, base * _xf(pos, rot))


func _cyl_mesh(r_top: float, r_bottom: float, h: float, segs: int = 20) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


## Oma solmu (liikkuvat osat ja merkkivalot).
func _node_mesh(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _node_box(size: Vector3, mat: Material, pos: Vector3, rot: Vector3, parent: Node3D) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _node_mesh(b, mat, pos, rot, parent)


## Palkki pisteestä a pisteeseen b (pituusakseli y).
func _beam(a: Vector3, b: Vector3, w: float, d: float, mat: Material) -> void:
	var box := BoxMesh.new()
	box.size = Vector3(w, a.distance_to(b), d)
	_add(box, mat, Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * 0.5))


## Kolmio, jonka etupuoli osoittaa normaalin n suuntaan.
func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3) -> void:
	if (b - a).cross(c - a).dot(n) < 0.0:
		var tmp := b
		b = c
		c = tmp
	for v: Vector3 in [a, b, c]:
		st.set_normal(n)
		st.set_uv(Vector2(v.x, v.y))
		st.add_vertex(v)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	_tri(st, a, b, c, n)
	_tri(st, a, c, d, n)


## Pyöristetty suorakaide xy-tasossa vastapäivään: keskipiste, puolimitat ja kulmien säteet (ylä, ala).
func _rrect(c: Vector2, hw: float, hh: float, r_top: float, r_bot: float, seg: int = 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [[Vector2(hw - r_bot, -hh + r_bot), r_bot, -PI / 2.0], [Vector2(hw - r_top, hh - r_top), r_top, 0.0],
		[Vector2(-hw + r_top, hh - r_top), r_top, PI / 2.0], [Vector2(-hw + r_bot, -hh + r_bot), r_bot, PI]]
	for k: Array in corners:
		for i in seg + 1:
			var a: float = k[2] + PI / 2.0 * i / seg
			pts.append(c + k[0] + Vector2(cos(a), sin(a)) * float(k[1]))
	return pts


## Kehys kahden samanmuotoisen ääriviivan välissä tasossa z (etupinta), syvyys taaksepäin; sisä- ja ulkoreunat.
## Oma solmu: SurfaceToolin verkot eivät sovi samaan yhdistelmäverkkoon BoxMeshien kanssa (eri tietomuoto).
func _ring(inner: PackedVector2Array, outer: PackedVector2Array, z: float, depth: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := inner.size()
	var center := Vector2.ZERO
	for p in inner:
		center += p / n
	for i in n:
		var j := (i + 1) % n
		var a := inner[i]
		var b := inner[j]
		var A := outer[i]
		var B := outer[j]
		_quad(st, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(B.x, B.y, z), Vector3(A.x, A.y, z), Vector3.BACK)
		_quad(st, Vector3(a.x, a.y, z - depth), Vector3(b.x, b.y, z - depth), Vector3(B.x, B.y, z - depth), Vector3(A.x, A.y, z - depth), Vector3.FORWARD)
		var mid := (a + b) * 0.5
		var nin := (center - mid).normalized()
		var e := (b - a).normalized()
		var side := Vector2(-e.y, e.x)
		if side.dot(nin) < 0.0:
			side = -side
		_quad(st, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(b.x, b.y, z - depth), Vector3(a.x, a.y, z - depth), Vector3(side.x, side.y, 0))
		_quad(st, Vector3(A.x, A.y, z), Vector3(B.x, B.y, z), Vector3(B.x, B.y, z - depth), Vector3(A.x, A.y, z - depth), Vector3(-side.x, -side.y, 0))
	_node_mesh(st.commit(), mat, Vector3.ZERO, Vector3.ZERO, self)


## Pyöristetty laatta (pehmusteet): pyöristetty suorakaide xy-tasossa, paksuus z-suuntaan, oma solmu.
func _slab(w: float, h: float, depth: float, r: float, mat: Material, xf: Transform3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := _rrect(Vector2.ZERO, w / 2.0, h / 2.0, r, r, 6)
	var n := pts.size()
	var zf := depth / 2.0
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		_tri(st, Vector3(0, 0, zf), Vector3(a.x, a.y, zf), Vector3(b.x, b.y, zf), Vector3.BACK)
		_tri(st, Vector3(0, 0, -zf), Vector3(a.x, a.y, -zf), Vector3(b.x, b.y, -zf), Vector3.FORWARD)
		var e := (b - a).normalized()
		var out := Vector3(e.y, -e.x, 0)
		if out.dot(Vector3(a.x + b.x, a.y + b.y, 0)) < 0.0:
			out = -out
		_quad(st, Vector3(a.x, a.y, zf), Vector3(b.x, b.y, zf), Vector3(b.x, b.y, -zf), Vector3(a.x, a.y, -zf), out)
	var mi := _node_mesh(st.commit(), mat, Vector3.ZERO, Vector3.ZERO, self)
	mi.transform = xf


## Painikerivistö paneelin pinnalla (paikallinen x leveys, z syvyys, y ylös): tummia ja valaistuja näppäimiä.
func _keypad(base: Transform3D, w: float, d: float, cols: int, rows: int, lit: float = 0.25) -> void:
	_box(Vector3(w, 0.01, d), dark, Vector3(0, 0.005, 0), Vector3.ZERO, base)
	var cw := w / cols
	var rd := d / rows
	for r in rows:
		for c in cols:
			var p := Vector3(-w / 2.0 + cw * (c + 0.5), 0.014, -d / 2.0 + rd * (r + 0.5))
			var mat: Material = keys[0]
			if _rng.randf() < lit:
				var pick := _rng.randf()
				mat = keys[1] if pick < 0.55 else (keys[2] if pick < 0.75 else (keys[3] if pick < 0.87 else (keys[4] if pick < 0.95 else keys[5])))
			_box(Vector3(cw * 0.6, 0.008, rd * 0.55), mat if mat == dark else dark, p, Vector3.ZERO, base)
			if mat != dark:
				_box(Vector3(cw * 0.42, 0.002, rd * 0.35), mat, p + Vector3(0, 0.005, 0), Vector3.ZERO, base)


## Pinnan pienet ulokkeet (kotelot, levyt): satunnaisia laatikoita alueelle.
func _greebles(base: Transform3D, w: float, h: float, count: int, mats: Array) -> void:
	for i in count:
		var s := Vector3(_rng.randf_range(0.04, 0.22), _rng.randf_range(0.03, 0.12), _rng.randf_range(0.01, 0.035))
		var p := Vector3(_rng.randf_range(-w / 2.0, w / 2.0), _rng.randf_range(-h / 2.0, h / 2.0), s.z / 2.0)
		_box(s, mats[_rng.randi() % mats.size()], p, Vector3.ZERO, base)


## Näyttö kehyksineen: SubViewport-kuva hehkuvana tasona. Tasoa käännetään niin, että se katsoo silmään.
func _monitor(kind: String, w: float, pos: Vector3, frame: bool = true) -> CockpitScreen:
	var h := w * SCREEN_SIZE.y / SCREEN_SIZE.x
	var g := Node3D.new()
	g.position = pos
	g.basis = Basis.looking_at(pos.normalized(), Vector3.UP)
	add_child(g)
	var xf := g.transform
	_box(Vector3(w + 0.035, h + 0.035, 0.04), bezel, Vector3(0, 0, -0.021), Vector3.ZERO, xf)
	if frame:
		# Kotelo: paksu kehys, yläreunan lippa ja kulmaruuvit.
		_box(Vector3(w + 0.09, h + 0.09, 0.05), plate, Vector3(0, 0, -0.05), Vector3.ZERO, xf)
		_box(Vector3(w + 0.11, 0.022, 0.07), steel, Vector3(0, h / 2.0 + 0.045, -0.02), Vector3(-0.2, 0, 0), xf)
		_box(Vector3(w + 0.06, 0.03, 0.05), dark, Vector3(0, -h / 2.0 - 0.04, -0.02), Vector3.ZERO, xf)
		for sx: float in [-1.0, 1.0]:
			_box(Vector3(0.022, h + 0.05, 0.06), dark, Vector3(sx * (w / 2.0 + 0.045), 0, -0.025), Vector3.ZERO, xf)
			for sy: float in [-1.0, 1.0]:
				_cyl(0.006, 0.006, 0.01, steel, Vector3(sx * (w / 2.0 + 0.032), sy * (h / 2.0 + 0.032), 0.0), Vector3(PI / 2.0, 0, 0), xf, 8)
			# Kotelon kyljen merkkivalot.
			_box(Vector3(0.008, 0.03, 0.01), led_blue, Vector3(sx * (w / 2.0 + 0.045), h / 2.0 - 0.04, 0.008), Vector3.ZERO, xf)
	var vp := SubViewport.new()
	vp.size = SCREEN_SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.disable_3d = true
	add_child(vp)
	var screen := CockpitScreen.new()
	screen.kind = kind
	vp.add_child(screen)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/screen.gdshader")
	mat.set_shader_parameter("screen_tex", vp.get_texture())
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	var mi := _node_mesh(q, mat, Vector3(0, 0, 0.001), Vector3.ZERO, g)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	monitors.append({"node": g, "size": Vector2(w, h), "screen": screen})
	return screen


## Suunta silmästä (vaaka- ja pystykulma asteina).
static func direction(yaw_deg: float, pitch_deg: float) -> Vector3:
	var y := deg_to_rad(yaw_deg)
	var p := deg_to_rad(pitch_deg)
	return Vector3(sin(y) * cos(p), sin(p), -cos(y) * cos(p))


## Näkyykö suunta d (aluksen koordinaateissa, silmästä) ikkunasta: etulasi tai kylkilasit.
static func through_window(d: Vector3) -> bool:
	if d.z < -0.05:
		var k := WIN_Z / d.z
		var x := d.x * k
		var y := d.y * k
		if absf(x) < WIN_HALF_W - 0.05 and y > WIN_BOTTOM + 0.03 and y < WIN_TOP - 0.05:
			return true
	if absf(d.x) > 0.05:
		var k := SIDE_X / absf(d.x)
		var z := d.z * k
		var y := d.y * k
		return z > SIDE_Z.x and z < SIDE_Z.y and y > SIDE_Y.x and y < SIDE_Y.y
	return false


# --- Rakenne ---

func _build_frame() -> void:
	var c := Vector2(0, (WIN_TOP + WIN_BOTTOM) / 2.0)
	var hh := (WIN_TOP - WIN_BOTTOM) / 2.0
	var hw := WIN_HALF_W
	var rt := 0.34
	var rb := 0.1
	var glass := _rrect(c, hw, hh, rt, rb)
	# Kumitiiviste, sisäkehys (syvä, viistetty vaikutelma kahdella portaalla) ja raskas ulkokehys.
	var rings := [0.0, 0.02, 0.055, 0.11]
	var mats := [rubber, steel, plate]
	var zs := [WIN_Z + 0.02, WIN_Z + 0.1, WIN_Z + 0.14]
	var ds := [0.06, 0.14, 0.06]
	for i in 3:
		_ring(_rrect(c, hw + rings[i], hh + rings[i], rt + rings[i], rb + rings[i]), _rrect(c, hw + rings[i + 1], hh + rings[i + 1], rt + rings[i + 1], rb + rings[i + 1]), zs[i], ds[i], mats[i])
	_ring(_rrect(c, hw + 0.11, hh + 0.11, rt + 0.11, rb + 0.11), _rrect(c, hw + 0.75, hh + 0.65, rt + 0.6, rb + 0.6), WIN_Z + 0.12, 0.1, hull)
	# Yläkehyksen paneelit: kotelot, siniset valolistat ja valkoiset valot.
	var top_y := WIN_TOP + 0.11
	var face := _xf(Vector3(0, 0, WIN_Z + 0.12))
	for sx: float in [-1.0, 1.0]:
		for x: float in [0.55, 1.35]:
			_box(Vector3(0.36, 0.07, 0.05), dark, Vector3(sx * x, top_y + 0.045, 0.025), Vector3.ZERO, face)
			_box(Vector3(0.28, 0.022, 0.02), led_blue, Vector3(sx * x, top_y + 0.03, 0.055), Vector3.ZERO, face)
		for x: float in [0.95, 1.75]:
			_box(Vector3(0.22, 0.045, 0.04), plate, Vector3(sx * x, top_y + 0.05, 0.02), Vector3.ZERO, face)
			_box(Vector3(0.17, 0.014, 0.012), led_white, Vector3(sx * x, top_y + 0.05, 0.045), Vector3.ZERO, face)
		# Yläkulmien pystytuet ja vinot kulmalevyt.
		_beam(Vector3(sx * (hw + 0.45), WIN_TOP + 0.5, WIN_Z + 0.2), Vector3(sx * (hw + 0.5), WIN_BOTTOM - 0.3, WIN_Z + 0.2), 0.16, 0.12, plate)
		_beam(Vector3(sx * (hw + 0.1), WIN_TOP + 0.35, WIN_Z + 0.22), Vector3(sx * (hw + 0.55), WIN_TOP - 0.15, WIN_Z + 0.22), 0.12, 0.06, steel)
	_box(Vector3(0.5, 0.14, 0.1), dark, Vector3(0, top_y + 0.1, 0.05), Vector3.ZERO, face)
	_box(Vector3(0.32, 0.03, 0.02), led_blue, Vector3(0, top_y + 0.08, 0.105), Vector3.ZERO, face)
	_greebles(_xf(Vector3(0, top_y + 0.24, WIN_Z + 0.12)), 3.8, 0.2, 50, [dark, plate, hull])
	# Katto, kyljet, takaseinä ja lattia.
	_box(Vector3(5.2, 0.1, 3.2), hull, Vector3(0, WIN_TOP + 0.6, -0.15))
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.1, 2.6, 3.2), hull, Vector3(sx * (SIDE_X + 0.15), 0.0, -0.15))
		# Kylkilasin karmi.
		_box(Vector3(0.08, 0.06, SIDE_Z.y - SIDE_Z.x + 0.1), steel, Vector3(sx * SIDE_X, SIDE_Y.x - 0.03, (SIDE_Z.x + SIDE_Z.y) / 2.0))
		_box(Vector3(0.08, 0.06, SIDE_Z.y - SIDE_Z.x + 0.1), steel, Vector3(sx * SIDE_X, SIDE_Y.y + 0.03, (SIDE_Z.x + SIDE_Z.y) / 2.0))
		for z: float in [SIDE_Z.x, SIDE_Z.y]:
			_box(Vector3(0.08, SIDE_Y.y - SIDE_Y.x + 0.12, 0.06), steel, Vector3(sx * SIDE_X, (SIDE_Y.x + SIDE_Y.y) / 2.0, z))
		# Seinän valolistat.
		_box(Vector3(0.02, 0.025, 1.4), led_blue, Vector3(sx * (SIDE_X + 0.09), -0.22, -0.3))
		_box(Vector3(0.02, 0.025, 1.0), led_blue, Vector3(sx * (SIDE_X + 0.09), 1.1, -0.5))
	_box(Vector3(5.0, 2.6, 0.08), hull, Vector3(0, 0.0, 1.4))
	_box(Vector3(0.6, 0.04, 0.2), dark, Vector3(0, WIN_TOP + 0.53, 0.2))
	_box(Vector3(0.5, 0.01, 0.12), led_white, Vector3(0, WIN_TOP + 0.51, 0.2))
	_box(Vector3(5.0, 0.04, 3.2), floor_mat, Vector3(0, -1.3, -0.15))


func _build_glass() -> void:
	glass_material = ShaderMaterial.new()
	glass_material.shader = load("res://shaders/glass.gdshader")
	glass_material.set_shader_parameter("dirt", noise_tex)
	glass_material.set_shader_parameter("scratch_noise", scratch_tex)
	var outline := _rrect(Vector2(0, (WIN_TOP + WIN_BOTTOM) / 2.0), WIN_HALF_W + 0.02, (WIN_TOP - WIN_BOTTOM) / 2.0 + 0.02, 0.36, 0.12)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var center := Vector3(0, (WIN_TOP + WIN_BOTTOM) / 2.0, WIN_Z)
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		_tri(st, center, Vector3(a.x, a.y, WIN_Z), Vector3(b.x, b.y, WIN_Z), Vector3.BACK)
	var front := _node_mesh(st.commit(), glass_material, Vector3.ZERO, Vector3.ZERO, self)
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s: float in [-1.0, 1.0]:
		var q := QuadMesh.new()
		q.size = Vector2(SIDE_Z.y - SIDE_Z.x, SIDE_Y.y - SIDE_Y.x)
		var g := _node_mesh(q, glass_material, Vector3(s * SIDE_X, (SIDE_Y.x + SIDE_Y.y) / 2.0, (SIDE_Z.x + SIDE_Z.y) / 2.0), Vector3(0, -s * PI / 2.0, 0), self)
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_dashboard() -> void:
	# Viisi näyttöä kaaressa; kunkin alla kalteva painikekansi ja etulevy lattiaan.
	for m: Array in MONITORS:
		var dir := direction(m[1], m[2])
		var d: float = m[3]
		var w: float = m[4]
		var h := w * SCREEN_SIZE.y / SCREEN_SIZE.x
		var pos := dir * d
		var screen := _monitor(m[0], w, pos)
		match String(m[0]):
			"nav": nav_screen = screen
			"systems": systems_screen = screen
			_: screens.append(screen)
		var yaw := deg_to_rad(-float(m[1]))
		var flat := Vector3(dir.x, 0, dir.z).normalized()
		var bottom := pos.y - h / 2.0 - 0.06
		# Näytön takana konsolin selkä ikkunan alareunaan.
		var back := Transform3D(Basis(Vector3.UP, yaw), flat * (d + 0.12) + Vector3(0, bottom - 0.05, 0))
		_box(Vector3(w + 0.06, 0.2, 0.2), hull, Vector3(0, 0.05, 0), Vector3.ZERO, back)
		_box(Vector3(w + 0.2, 0.03, 0.24), plate, Vector3(0, -0.04, 0.02), Vector3.ZERO, back)
		# Kalteva painikekansi.
		var deck := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, 0.32), flat * (d - 0.1) + Vector3(0, bottom - 0.04, 0))
		_box(Vector3(w + 0.24, 0.03, 0.26), plate, Vector3(0, -0.015, 0), Vector3.ZERO, deck)
		_box(Vector3(w + 0.25, 0.02, 0.03), steel, Vector3(0, 0.0, 0.13), Vector3.ZERO, deck)
		_keypad(deck.translated_local(Vector3(-w * 0.22, 0, -0.02)), w * 0.44, 0.15, 10, 3, 0.35)
		_keypad(deck.translated_local(Vector3(w * 0.26, 0, -0.02)), w * 0.36, 0.15, 7, 3, 0.5)
		# Etulevy kannen etureunasta lattiaan, kaapelikanava ja sininen valolista.
		var front := Transform3D(Basis(Vector3.UP, yaw), flat * (d - 0.24) + Vector3(0, bottom - 0.1, 0))
		_box(Vector3(w + 0.24, 0.04, 0.06), dark, Vector3(0, -0.02, 0), Vector3.ZERO, front)
		_box(Vector3(w + 0.22, 1.1, 0.06), hull, Vector3(0, -0.6, -0.06), Vector3.ZERO, front)
		_greebles(front.translated_local(Vector3(0, -0.35, -0.03)), w, 0.3, 6, [dark, plate])


func _build_center() -> void:
	# Keskikonsoli ohjainsauvojen välissä: kalteva pinta pikkunäyttöineen, merkkivalot ja painikkeet.
	_box(Vector3(0.22, 0.9, 0.3), hull, Vector3(0, -0.73, -1.0))
	var top := _xf(Vector3(0, -0.25, -0.96), Vector3(1.0, 0, 0))
	_box(Vector3(0.24, 0.03, 0.26), plate, Vector3(0, -0.015, 0), Vector3.ZERO, top)
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.022, 0.05, 0.28), steel, Vector3(sx * 0.12, 0.0, 0), Vector3.ZERO, top)
	mini_screen = _monitor("mini", 0.12, Vector3(0, -0.205, -0.985), false)
	_keypad(top.translated_local(Vector3(0, 0, 0.09)), 0.18, 0.05, 6, 1, 0.6)
	var names := ["moottori", "kiihdytys", "polttoaine", "suunta", "vaikutuspiiri", "ilmakeha"]
	var colors := [Color(1.0, 0.55, 0.15), Color(0.37, 0.84, 1.0), Color(0.3, 0.9, 0.5), Color(0.37, 0.84, 1.0), Color(1.0, 0.8, 0.3), Color(1.0, 0.35, 0.3)]
	var row := Node3D.new()
	row.transform = top.translated_local(Vector3(0, 0, 0.03))
	add_child(row)
	for i in names.size():
		var m := _emissive(colors[i], 0.0)
		lights[names[i]] = m
		_node_mesh(_cyl_mesh(0.007, 0.007, 0.012, 12), m, Vector3(-0.075 + i * 0.03, 0.006, 0), Vector3.ZERO, row)
	# Ohjainsauvojen jalustat.
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.14, 0.95, 0.2), hull, Vector3(sx * 0.21, -0.82, -0.9))
		_box(Vector3(0.18, 0.05, 0.26), plate, Vector3(sx * 0.21, -0.345, -0.9))
		_box(Vector3(0.12, 0.06, 0.06), dark, Vector3(sx * 0.21, -0.36, -1.0))
		_keypad(_xf(Vector3(sx * 0.24, -0.318, -0.98)), 0.08, 0.05, 3, 2, 0.5)
		_cyl(0.04, 0.055, 0.04, rubber, Vector3(sx * 0.2, -0.315, -0.86))


func _build_sides() -> void:
	for s: float in [-1.0, 1.0]:
		# Sivukonsoli: kalteva painikepöytä, korotettu takapaneeli valolistoineen ja runko lattiaan.
		var desk := _xf(Vector3(s * 1.12, -0.34, -0.85), Vector3(0, s * 0.45, s * 0.22))
		_box(Vector3(0.85, 0.04, 0.85), plate, Vector3(0, -0.02, 0), Vector3.ZERO, desk)
		_box(Vector3(0.87, 0.6, 0.86), hull, Vector3(0, -0.34, 0.0), Vector3.ZERO, desk)
		for r in 2:
			for c in 2:
				_keypad(desk.translated_local(Vector3(-0.2 + c * 0.4, 0, -0.2 + r * 0.38)), 0.34, 0.26, 10, 6, 0.3)
		var panel := _xf(Vector3(s * 1.62, -0.12, -0.95), Vector3(0, s * -1.1, 0)) * _xf(Vector3.ZERO, Vector3(-0.35, 0, 0))
		_box(Vector3(1.1, 0.4, 0.06), dark, Vector3(0, 0, -0.03), Vector3.ZERO, panel)
		_box(Vector3(0.9, 0.025, 0.015), led_blue, Vector3(0, 0.16, 0.005), Vector3.ZERO, panel)
		_keypad(panel * _xf(Vector3(-0.22, -0.05, 0.0), Vector3(PI / 2.0, 0, 0)), 0.5, 0.2, 8, 3, 0.4)
		_keypad(panel * _xf(Vector3(0.3, -0.05, 0.0), Vector3(PI / 2.0, 0, 0)), 0.36, 0.2, 5, 3, 0.25)
		# Ylempi sivupaneeli ikkunan vieressä: kotelot ja valolista.
		var upper := _xf(Vector3(s * 2.0, 0.25, -1.3), Vector3(0, s * -0.9, 0))
		_box(Vector3(0.7, 0.9, 0.08), hull, Vector3(0, 0, -0.04), Vector3.ZERO, upper)
		_box(Vector3(0.02, 0.6, 0.012), led_blue, Vector3(s * -0.3, 0, 0.005), Vector3.ZERO, upper)
		_greebles(upper, 0.6, 0.8, 18, [dark, plate, steel])
		# Kaapelikanavat seinällä.
		for i in 3:
			_cyl(0.018, 0.018, 1.6, rubber, Vector3(s * (SIDE_X + 0.05), -0.55 - i * 0.05, -0.4), Vector3(PI / 2.0, 0, 0), Transform3D.IDENTITY, 10)


func _build_pilot() -> void:
	# Istuimen niskatuki ja selkänoja etualalla.
	# Pehmusteet ovat pyöristettyjä laattoja; keskellä sauma, sivuilla siivekkeet ja runko teräsputkesta.
	var seat := _xf(Vector3(0, -0.27, -0.56), Vector3(-0.1, 0, 0))
	_slab(0.2, 0.17, 0.08, 0.05, fabric, seat)
	_slab(0.17, 0.14, 0.03, 0.04, suit, seat * _xf(Vector3(0, 0.0, 0.04)))
	_box(Vector3(0.008, 0.13, 0.008), dark, Vector3(0, 0.0, 0.056), Vector3.ZERO, seat)
	for sx: float in [-1.0, 1.0]:
		_slab(0.07, 0.2, 0.09, 0.03, fabric, seat * _xf(Vector3(sx * 0.125, -0.01, -0.005), Vector3(0, sx * 0.45, 0)))
		_box(Vector3(0.01, 0.15, 0.01), steel, Vector3(sx * 0.16, -0.01, 0.03), Vector3(0, sx * 0.45, 0), seat)
		_cyl(0.007, 0.007, 0.12, steel, Vector3(sx * 0.06, -0.14, 0.0), Vector3.ZERO, seat, 8)
	_slab(0.36, 0.7, 0.12, 0.08, fabric, seat * _xf(Vector3(0, -0.5, 0.02), Vector3(0.05, 0, 0)))
	_slab(0.3, 0.5, 0.03, 0.06, suit, seat * _xf(Vector3(0, -0.46, 0.08), Vector3(0.05, 0, 0)))
	_box(Vector3(0.44, 0.6, 0.05), dark, Vector3(0, -0.6, -0.05), Vector3(0.05, 0, 0), seat)
	# Ohjainsauva (oikea) ja tehovipu (vasen); lentäjän käsineet ovat kahvoissa ja liikkuvat niiden mukana.
	stick = Node3D.new()
	stick.position = Vector3(0.2, -0.31, -0.86)
	add_child(stick)
	throttle = Node3D.new()
	throttle.position = Vector3(-0.2, -0.31, -0.86)
	add_child(throttle)
	var lever := Node3D.new()
	lever.name = "Vipu"
	throttle.add_child(lever)
	for p: Node3D in [stick, lever]:
		_node_mesh(_cyl_mesh(0.014, 0.018, 0.12, 12), steel, Vector3(0, 0.06, 0), Vector3.ZERO, p)
		var grip := CapsuleMesh.new()
		grip.radius = 0.026
		grip.height = 0.13
		_node_mesh(grip, rubber, Vector3(0, 0.16, 0), Vector3(-0.15, 0, 0), p)
		_node_mesh(_cyl_mesh(0.012, 0.012, 0.012, 10), _emissive(Color(1.0, 0.3, 0.25) if p == stick else Color(0.3, 0.7, 1.0), 2.0), Vector3(0, 0.235, -0.012), Vector3(-0.15, 0, 0), p)
		_glove(p, 1.0 if p == stick else -1.0)
	# Kyynär- ja olkavarret istuimen takaa kahvoihin.
	for sx: float in [-1.0, 1.0]:
		var shoulder := Vector3(sx * 0.24, -0.47, -0.62)
		var elbow := Vector3(sx * 0.42, -0.5, -0.7)
		var wrist := Vector3(sx * 0.215, -0.23, -0.82)
		_limb(shoulder, elbow, 0.07, 0.065)
		_limb(elbow, wrist, 0.064, 0.05)
		# Hihan saumat ja kyynärsuoja.
		_add(_cyl_mesh(0.068, 0.068, 0.02, 16), rubber, Transform3D(Basis(Quaternion(Vector3.UP, (wrist - elbow).normalized())), elbow.lerp(wrist, 0.45)))
		var pad := SphereMesh.new()
		pad.radius = 0.07
		pad.height = 0.1
		_add(pad, plate, _xf(elbow + Vector3(sx * 0.01, -0.01, 0.02)))


## Käsine kahvan ympärillä: nyrkki, rystyset, peukalo ja ranneke.
func _glove(parent: Node3D, sx: float) -> void:
	var g := Node3D.new()
	g.position = Vector3(0, 0.15, 0.005)
	g.rotation = Vector3(-0.15, 0, 0)
	parent.add_child(g)
	var fist := CapsuleMesh.new()
	fist.radius = 0.045
	fist.height = 0.11
	_node_mesh(fist, rubber, Vector3(sx * 0.008, 0, 0.0), Vector3(0, 0, 0), g)
	for i in 4:
		var k := CapsuleMesh.new()
		k.radius = 0.016
		k.height = 0.05
		_node_mesh(k, suit, Vector3(sx * -0.012, 0.036 - i * 0.024, -0.036), Vector3(0, 0, PI / 2.0), g)
	var thumb := CapsuleMesh.new()
	thumb.radius = 0.014
	thumb.height = 0.06
	_node_mesh(thumb, rubber, Vector3(sx * -0.03, 0.06, -0.01), Vector3(0.4, 0, sx * 0.8), g)
	_node_box(Vector3(0.05, 0.03, 0.04), plate, Vector3(sx * 0.03, 0.01, 0.012), Vector3(0, 0, 0), g)
	_node_mesh(_cyl_mesh(0.058, 0.05, 0.05, 16), rubber, Vector3(sx * 0.01, -0.07, 0.04), Vector3(0.7, 0, 0), g)


## Puvun hiha kahden pisteen välillä (kartiomainen sylinteri ja pallonivel).
func _limb(a: Vector3, b: Vector3, ra: float, rb: float) -> void:
	_add(_cyl_mesh(rb, ra, a.distance_to(b), 16), suit, Transform3D(Basis(Quaternion(Vector3.UP, (b - a).normalized())), (a + b) * 0.5))
	var joint := SphereMesh.new()
	joint.radius = ra
	joint.height = ra * 2.0
	_add(joint, suit, _xf(a))


func _build_plasma() -> void:
	# Ilmajarrutuksen plasma: hehkuvat tasot etu- ja sivuikkunoiden ulkopuolella.
	plasma_material = ShaderMaterial.new()
	plasma_material.shader = load("res://shaders/plasma.gdshader")
	plasma_material.set_shader_parameter("noise", noise_tex)
	plasma = Node3D.new()
	add_child(plasma)
	for c: Array in [[Vector3(0, 0.4, WIN_Z - 0.3), 0.0, 5.0], [Vector3(-SIDE_X - 0.3, 0.4, -1.0), PI / 2.0, 2.8], [Vector3(SIDE_X + 0.3, 0.4, -1.0), -PI / 2.0, 2.8]]:
		var q := QuadMesh.new()
		q.size = Vector2(c[2], 2.6)
		var m := _node_mesh(q, plasma_material, c[0], Vector3(0, c[1], 0), plasma)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plasma.visible = false


## Merkkivalojen kirkkaus (0–1) nimen mukaan.
func set_light(name: String, on: float) -> void:
	var m: StandardMaterial3D = lights.get(name)
	if m != null:
		m.emission_energy_multiplier = on * 3.0
