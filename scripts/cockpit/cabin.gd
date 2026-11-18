class_name Cabin
extends Node3D
## Ohjaamon sisätila koodilla (web/js/cabin.js:n rakenne, PBR-materiaalein): kuomun kaari ja tuet, lasi,
## keskikonsoli kolmine näyttöineen, kattonäytöt (navigointi ja järjestelmät), sivukonsolit kytkimineen ja
## merkkivaloineen, ohjainsauva, tehovipu, istuin, kaapelinipput, lattia ja seinät.
## Yksikkö metri; silmät origossa, katse −z, ylös +y.

const SCREEN_SIZE := Vector2i(512, 288)

var screens: Array[CockpitScreen] = []
var nav_screen: CockpitScreen
var systems_screen: CockpitScreen
var glass_material: ShaderMaterial
var plasma_material: ShaderMaterial
var plasma: Node3D
var lights := {} # nimi → StandardMaterial3D (merkkivalot)
var switches: Array[Node3D] = []
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
var bezel: StandardMaterial3D
var floor_mat: ShaderMaterial


func _ready() -> void:
	noise_tex = _noise(512, 0.012, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 7)
	scratch_tex = _noise(512, 0.05, FastNoiseLite.TYPE_VALUE_CUBIC, 11)
	steel = _metal(Color(0.6, 0.64, 0.7), 0.75, 0.42, 0.55, 0.45)
	plate = _metal(Color(0.48, 0.52, 0.58), 0.65, 0.5, 0.6, 0.3)
	dark = _metal(Color(0.2, 0.22, 0.26), 0.5, 0.55, 0.5, 0.2)
	hull = _metal(Color(0.11, 0.12, 0.15), 0.25, 0.75, 0.35, 0.5)
	floor_mat = _metal(Color(0.32, 0.34, 0.37), 0.7, 0.45, 0.8, 0.15)
	floor_mat.set_shader_parameter("rivets", 0.0)
	rubber = StandardMaterial3D.new()
	rubber.albedo_color = Color(0.045, 0.047, 0.055)
	rubber.roughness = 0.92
	rubber.normal_enabled = true
	rubber.normal_texture = _noise(256, 0.08, FastNoiseLite.TYPE_SIMPLEX, 3, true)
	rubber.normal_scale = 0.3
	fabric = StandardMaterial3D.new()
	fabric.albedo_color = Color(0.12, 0.13, 0.16)
	fabric.roughness = 1.0
	fabric.normal_enabled = true
	fabric.normal_texture = _noise(256, 0.3, FastNoiseLite.TYPE_CELLULAR, 5, true)
	fabric.normal_scale = 0.5
	fabric.uv1_triplanar = true
	fabric.uv1_scale = Vector3(6, 6, 6)
	bezel = StandardMaterial3D.new()
	bezel.albedo_color = Color(0.03, 0.035, 0.04)
	bezel.roughness = 0.35
	bezel.metallic = 0.4
	_build_frame()
	_build_glass()
	_build_console()
	_build_overhead()
	_build_sides()
	_build_seat()
	_build_cables()
	_build_plasma()


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


# --- Apufunktiot ---

func _mesh(mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _box(size: Vector3, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, parent: Node3D = self) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return _mesh(b, mat, pos, rot, parent)


func _cyl(r_top: float, r_bottom: float, h: float, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO, parent: Node3D = self, segs: int = 24) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return _mesh(c, mat, pos, rot, parent)


## Palkki pisteestä a pisteeseen b (pituusakseli y).
func _beam(a: Vector3, b: Vector3, w: float, d: float, mat: Material) -> MeshInstance3D:
	var len := a.distance_to(b)
	var mi := _box(Vector3(w, len, d), mat, (a + b) * 0.5)
	mi.basis = Basis(Quaternion(Vector3.UP, (b - a).normalized()))
	return mi


## Pursotettu muoto (polygoni xy-tasossa, syvyys z-suuntaan) valmiiksi verkoksi.
func _extrude(points: PackedVector2Array, depth: float, mat: Material, pos: Vector3) -> MeshInstance3D:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var n := points.size()
	var tris := Geometry2D.triangulate_polygon(points)
	for side: float in [0.0, -depth]:
		var normal := Vector3.BACK if side == 0.0 else Vector3.FORWARD
		for i in range(0, tris.size(), 3):
			var ids := [tris[i], tris[i + 1], tris[i + 2]] if side == 0.0 else [tris[i], tris[i + 2], tris[i + 1]]
			for id: int in ids:
				verts.append(Vector3(points[id].x, points[id].y, side))
				normals.append(normal)
	for i in n:
		var a := points[i]
		var b := points[(i + 1) % n]
		var e := (b - a).normalized()
		var nn := Vector3(e.y, -e.x, 0.0)
		for v: Vector3 in [Vector3(a.x, a.y, 0), Vector3(b.x, b.y, 0), Vector3(b.x, b.y, -depth), Vector3(a.x, a.y, 0), Vector3(b.x, b.y, -depth), Vector3(a.x, a.y, -depth)]:
			verts.append(v)
			normals.append(nn)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh(m, mat, pos)


## Putki pisteiden kautta (kaapelit): ympyräpoikkileikkaus, Catmull–Rom-käyrä.
func _tube(pts: PackedVector3Array, radius: float, mat: Material, segs: int = 8) -> MeshInstance3D:
	var curve := Curve3D.new()
	for i in pts.size():
		var tin := Vector3.ZERO
		var tout := Vector3.ZERO
		if i > 0 and i < pts.size() - 1:
			var t := (pts[i + 1] - pts[i - 1]) * 0.25
			tin = -t
			tout = t
		curve.add_point(pts[i], tin, tout)
	curve.bake_interval = 0.04
	var path := curve.get_baked_points()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	var norms: Array[PackedVector3Array] = []
	for i in path.size():
		var dir := (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side := dir.cross(Vector3.UP)
		if side.length() < 0.01:
			side = dir.cross(Vector3.RIGHT)
		side = side.normalized()
		var up := side.cross(dir).normalized()
		var ring := PackedVector3Array()
		var nr := PackedVector3Array()
		for j in segs + 1:
			var a := TAU * j / segs
			var nv := side * cos(a) + up * sin(a)
			ring.append(path[i] + nv * radius)
			nr.append(nv)
		rings.append(ring)
		norms.append(nr)
	for i in rings.size() - 1:
		for j in segs:
			for q: Array in [[i, j], [i + 1, j], [i + 1, j + 1], [i, j], [i + 1, j + 1], [i, j + 1]]:
				st.set_normal(norms[q[0]][q[1]])
				st.add_vertex(rings[q[0]][q[1]])
	return _mesh(st.commit(), mat, Vector3.ZERO)


## Näyttö kehyksineen: SubViewport-kuva hehkuvana tasona. Palauttaa näytön sisällön.
func _monitor(kind: String, w: float, h: float, pos: Vector3, rot: Vector3) -> CockpitScreen:
	var g := Node3D.new()
	g.position = pos
	g.rotation = rot
	add_child(g)
	_box(Vector3(w + 0.04, h + 0.04, 0.035), bezel, Vector3(0, 0, -0.019), Vector3.ZERO, g)
	var vp := SubViewport.new()
	vp.size = SCREEN_SIZE
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	vp.disable_3d = true
	add_child(vp)
	var screen := CockpitScreen.new()
	screen.kind = kind
	screen.size = Vector2(SCREEN_SIZE)
	vp.add_child(screen)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/screen.gdshader")
	mat.set_shader_parameter("screen_tex", vp.get_texture())
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	_mesh(q, mat, Vector3(0, 0, 0.001), Vector3.ZERO, g)
	return screen


# --- Rakenne ---

func _arch(rx: float, ry: float, steps: int, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in steps + 1:
		var a := lerpf(from, to, float(i) / steps)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _build_frame() -> void:
	# Kuomun kaari: puolisoikio jalkoineen, pursotettu levystä.
	var outer := _arch(2.02, 1.42, 40, 0.0, PI)
	var inner := _arch(1.76, 1.17, 40, PI, 0.0)
	var shape := PackedVector2Array([Vector2(2.02, -0.9)])
	shape.append_array(outer)
	shape.append_array(PackedVector2Array([Vector2(-2.02, -0.9), Vector2(-1.76, -0.9)]))
	shape.append_array(inner)
	shape.append(Vector2(1.76, -0.9))
	_extrude(shape, 0.2, steel, Vector3(0, -0.45, -1.64))
	# Kaaren sisäreunan kumitiiviste.
	var lip := PackedVector2Array([Vector2(1.76, -0.9)])
	lip.append_array(_arch(1.76, 1.17, 40, 0.0, PI))
	lip.append_array(PackedVector2Array([Vector2(-1.76, -0.9), Vector2(-1.72, -0.9)]))
	lip.append_array(_arch(1.72, 1.13, 40, PI, 0.0))
	lip.append(Vector2(1.72, -0.9))
	_extrude(lip, 0.1, rubber, Vector3(0, -0.45, -1.6))
	_box(Vector3(3.6, 0.12, 0.22), plate, Vector3(0, -0.52, -1.55))
	_box(Vector3(3.6, 0.8, 0.1), hull, Vector3(0, -0.95, -1.62))
	# Yläpalkki, josta vinotuet laskevat keskikonsoliin.
	_box(Vector3(2.5, 0.14, 0.2), plate, Vector3(0, 0.79, -1.34))
	_box(Vector3(0.5, 0.06, 0.16), dark, Vector3(0, 0.7, -1.3))
	for s: float in [-1.0, 1.0]:
		_box(Vector3(0.3, 0.05, 0.14), dark, Vector3(s * 0.62, 0.705, -1.3))
		_beam(Vector3(s * 0.9, 0.74, -1.38), Vector3(s * 0.13, -0.3, -1.52), 0.085, 0.06, steel)
		_beam(Vector3(s * 0.84, 0.74, -1.36), Vector3(s * 0.1, -0.26, -1.5), 0.02, 0.02, dark)
		# Ristikkotuki kaaren kyljestä konsolin sivuun: kaksi laippaa ja poikkisiteet.
		var a := Vector3(s * 1.74, 0.36, -1.5)
		var b := Vector3(s * 0.98, -0.66, -1.14)
		for e: float in [-0.08, 0.08]:
			_beam(a + Vector3(e, 0, 0), b + Vector3(e, 0, 0), 0.022, 0.05, plate)
		for i in 7:
			var p0 := a.lerp(b, i / 7.0) + Vector3(-0.08, 0, 0)
			var p1 := a.lerp(b, (i + 1) / 7.0) + Vector3(0.08, 0, 0)
			_beam(p0, p1, 0.014, 0.014, dark)
		_box(Vector3(0.3, 0.12, 0.22), plate, b + Vector3(0, -0.02, 0))
		_box(Vector3(0.24, 0.2, 0.16), plate, Vector3(s * 1.72, 0.4, -1.5))
		# Sivurakenne: kylkikaari, alarunko, takaseinä ja kattolista.
		_beam(Vector3(s * 2.06, -0.4, -0.3), Vector3(s * 1.62, 1.0, -0.3), 0.14, 0.16, steel)
		_box(Vector3(0.1, 0.95, 2.9), hull, Vector3(s * 2.08, -0.88, -0.2))
		_box(Vector3(0.1, 0.1, 1.4), plate, Vector3(s * 2.05, -0.4, -0.95))
		_box(Vector3(0.08, 2.4, 1.5), hull, Vector3(s * 2.06, -0.1, 0.55))
		_box(Vector3(0.05, 0.05, 1.3), plate, Vector3(s * 1.82, 0.98, -0.95), Vector3(0, 0, s * 0.3))
		# Kylkiikkunan karmi.
		_beam(Vector3(s * 2.04, -0.4, -1.5), Vector3(s * 2.04, -0.4, -0.3), 0.06, 0.06, steel)
	# Katto: kaaresta taaksepäin, kattovalon kotelo.
	_box(Vector3(3.4, 0.08, 1.6), hull, Vector3(0, 1.06, 0.35))
	_box(Vector3(0.6, 0.04, 0.2), dark, Vector3(0, 1.0, -0.1))
	_box(Vector3(0.5, 0.01, 0.12), _emissive(Color(1.0, 0.9, 0.78), 1.5), Vector3(0, 0.975, -0.1))
	_box(Vector3(4.3, 2.4, 0.08), hull, Vector3(0, -0.1, 1.2))
	var fl := _box(Vector3(4.4, 0.04, 3.0), floor_mat, Vector3(0, -1.3, -0.2))
	fl.name = "Lattia"


func _build_glass() -> void:
	glass_material = ShaderMaterial.new()
	glass_material.shader = load("res://shaders/glass.gdshader")
	glass_material.set_shader_parameter("dirt", noise_tex)
	glass_material.set_shader_parameter("scratch_noise", scratch_tex)
	# Etulasi kaaren sisällä ja kylkilasit.
	var shape := PackedVector2Array([Vector2(1.76, -0.9)])
	shape.append_array(_arch(1.76, 1.17, 40, 0.0, PI))
	shape.append(Vector2(-1.76, -0.9))
	var front := _extrude(shape, 0.004, glass_material, Vector3(0, -0.45, -1.7))
	front.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for s: float in [-1.0, 1.0]:
		var q := QuadMesh.new()
		q.size = Vector2(1.25, 1.35)
		var g := _mesh(q, glass_material, Vector3(s * 2.0, 0.27, -0.9), Vector3(0, -s * PI / 2.0, 0))
		g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_console() -> void:
	# Keskikonsoli: runko ja kalteva taulu, jonka pinnalla ovat kolme näyttöä (taulu näyttöjen takana).
	_box(Vector3(1.9, 0.5, 0.55), hull, Vector3(0, -0.8, -1.3))
	var deck := Node3D.new()
	deck.position = Vector3(0, -0.42, -1.15)
	deck.rotation = Vector3(-0.62, 0, 0)
	add_child(deck)
	_box(Vector3(1.96, 0.42, 0.04), plate, Vector3(0, 0.0, -0.045), Vector3.ZERO, deck)
	_box(Vector3(1.98, 0.035, 0.07), rubber, Vector3(0, -0.225, -0.03), Vector3.ZERO, deck)
	_box(Vector3(1.98, 0.03, 0.06), dark, Vector3(0, 0.225, -0.035), Vector3.ZERO, deck)
	for i in 3:
		var x := (i - 1) * 0.62
		screens.append(_monitor("main", 0.54, 0.31, deck.position + deck.basis * Vector3(x, 0, 0), Vector3(-0.62, -x * 0.25, 0)))
	# Taulun alareunasta konsolin etureunaan.
	_box(Vector3(1.9, 0.04, 0.3), plate, Vector3(0, -0.6, -0.98), Vector3(-0.25, 0, 0))
	# Konsolin etureunan näppäinrivi ja merkkivalot.
	for i in 12:
		var x := -0.55 + i * 0.1
		_box(Vector3(0.05, 0.02, 0.035), dark, Vector3(x, -0.575, -0.94), Vector3(-0.25, 0, 0))
	var names := ["moottori", "kiihdytys", "polttoaine", "suunta", "vaikutuspiiri", "ilmakeha"]
	var colors := [Color(1.0, 0.55, 0.15), Color(0.37, 0.84, 1.0), Color(0.3, 0.9, 0.5), Color(0.37, 0.84, 1.0), Color(1.0, 0.8, 0.3), Color(1.0, 0.35, 0.3)]
	for i in names.size():
		var m := _emissive(colors[i], 0.0)
		lights[names[i]] = m
		_cyl(0.012, 0.012, 0.015, m, Vector3(-0.3 + i * 0.12, -0.585, -1.02), Vector3(-0.25 + PI / 2.0, 0, 0))



func _build_overhead() -> void:
	# Kattonäytöt yläkulmissa: navigointi (vasen) ja järjestelmät (oikea).
	for s: float in [-1.0, 1.0]:
		_box(Vector3(0.62, 0.1, 0.4), dark, Vector3(s * 0.78, 0.74, -1.12), Vector3(0.35, 0, 0))
		_box(Vector3(0.04, 0.24, 0.04), plate, Vector3(s * 0.55, 0.72, -1.08))
		_box(Vector3(0.04, 0.24, 0.04), plate, Vector3(s * 1.0, 0.72, -1.08))
	nav_screen = _monitor("nav", 0.5, 0.28, Vector3(-0.78, 0.57, -1.06), Vector3(0.45, 0.32, 0.06))
	systems_screen = _monitor("systems", 0.5, 0.28, Vector3(0.78, 0.57, -1.06), Vector3(0.45, -0.32, -0.06))


func _build_sides() -> void:
	for s: float in [-1.0, 1.0]:
		# Sivukonsoli kytkinpaneeleineen.
		_box(Vector3(0.36, 0.42, 0.9), hull, Vector3(s * 0.78, -0.95, -0.35))
		var top := Node3D.new()
		top.position = Vector3(s * 0.78, -0.72, -0.4)
		top.rotation = Vector3(0, 0, s * 0.18)
		add_child(top)
		_box(Vector3(0.38, 0.04, 0.82), plate, Vector3.ZERO, Vector3.ZERO, top)
		for row in 3:
			for col in 4:
				var p := Vector3(-0.12 + col * 0.08, 0.035, -0.28 + row * 0.1)
				_box(Vector3(0.05, 0.012, 0.06), dark, p - Vector3(0, 0.012, 0), Vector3.ZERO, top)
				var sw := Node3D.new()
				sw.position = p
				top.add_child(sw)
				_cyl(0.005, 0.007, 0.05, steel, Vector3(0, 0.022, 0), Vector3.ZERO, sw, 8)
				sw.rotation.x = 0.35 if (row + col) % 2 == 0 else -0.35
				switches.append(sw)
		# Koneistosylinterit ja kotelot kylkiseinässä.
		for i in 3:
			_cyl(0.08, 0.08, 0.5, steel, Vector3(s * 1.9, -0.75 + i * 0.22, 0.25), Vector3(PI / 2.0, 0, 0))
			_cyl(0.085, 0.085, 0.04, dark, Vector3(s * 1.9, -0.75 + i * 0.22, 0.02), Vector3(PI / 2.0, 0, 0))
		_box(Vector3(0.2, 0.5, 0.35), plate, Vector3(s * 1.85, 0.3, 0.5))
	# Ohjainsauva (oikea) ja tehovipu (vasen) käsinojissa.
	stick = Node3D.new()
	stick.position = Vector3(0.62, -0.68, -0.25)
	add_child(stick)
	_cyl(0.05, 0.065, 0.04, rubber, Vector3(0, 0.0, 0), Vector3.ZERO, stick)
	_cyl(0.015, 0.018, 0.2, steel, Vector3(0, 0.1, 0), Vector3.ZERO, stick)
	var grip := CapsuleMesh.new()
	grip.radius = 0.03
	grip.height = 0.14
	_mesh(grip, rubber, Vector3(0, 0.24, 0.0), Vector3(-0.2, 0, 0), stick)
	_cyl(0.008, 0.008, 0.02, _emissive(Color(1.0, 0.3, 0.25), 1.5), Vector3(0, 0.31, -0.02), Vector3(-0.2, 0, 0), stick)
	throttle = Node3D.new()
	throttle.position = Vector3(-0.62, -0.69, -0.3)
	add_child(throttle)
	_box(Vector3(0.1, 0.03, 0.3), dark, Vector3(0, 0.0, 0), Vector3.ZERO, throttle)
	var lever := Node3D.new()
	lever.name = "Vipu"
	throttle.add_child(lever)
	_box(Vector3(0.02, 0.16, 0.02), steel, Vector3(0, 0.08, 0), Vector3.ZERO, lever)
	_box(Vector3(0.09, 0.045, 0.05), rubber, Vector3(0, 0.17, 0), Vector3.ZERO, lever)


func _build_seat() -> void:
	_box(Vector3(0.58, 0.14, 0.6), fabric, Vector3(0, -0.88, 0.05))
	_box(Vector3(0.58, 0.85, 0.14), fabric, Vector3(0, -0.4, 0.42), Vector3(0.12, 0, 0))
	_box(Vector3(0.32, 0.22, 0.12), fabric, Vector3(0, 0.12, 0.5), Vector3(0.1, 0, 0))
	for s: float in [-1.0, 1.0]:
		_box(Vector3(0.1, 0.5, 0.7), fabric, Vector3(s * 0.33, -0.7, 0.15))
		_box(Vector3(0.06, 0.7, 0.06), steel, Vector3(s * 0.26, -0.4, 0.5), Vector3(0.12, 0, 0))
		# Turvavyön olkahihnat.
		_beam(Vector3(s * 0.14, 0.02, 0.36), Vector3(s * 0.2, -0.6, 0.12), 0.05, 0.008, rubber)
	_cyl(0.06, 0.08, 0.4, steel, Vector3(0, -1.1, 0.05))


func _build_cables() -> void:
	var cable := StandardMaterial3D.new()
	cable.albedo_color = Color(0.06, 0.06, 0.07)
	cable.roughness = 0.6
	var cable_red := StandardMaterial3D.new()
	cable_red.albedo_color = Color(0.35, 0.06, 0.05)
	cable_red.roughness = 0.55
	var cable_blue := StandardMaterial3D.new()
	cable_blue.albedo_color = Color(0.06, 0.12, 0.3)
	cable_blue.roughness = 0.55
	for s: float in [-1.0, 1.0]:
		for i in 4:
			var m: Material = [cable, cable_red, cable, cable_blue][i]
			var o := i * 0.035
			_tube(PackedVector3Array([Vector3(s * 1.98, 0.85 - o, -0.2), Vector3(s * 1.96, 0.5 - o, -0.6), Vector3(s * 1.95, -0.1 - o * 0.5, -1.0),
				Vector3(s * 1.4, -0.75 - o, -1.4), Vector3(s * 0.9, -0.82 - o, -1.5)]), 0.012, m)
		# Riippuva kaapelilenkki kattonäytön takana.
		_tube(PackedVector3Array([Vector3(s * 0.55, 0.85, -1.2), Vector3(s * 0.7, 0.6, -1.25), Vector3(s * 0.95, 0.82, -1.2)]), 0.01, cable)


func _build_plasma() -> void:
	# Ilmajarrutuksen plasma: hehkuvat tasot etu- ja sivuikkunoiden ulkopuolella.
	plasma_material = ShaderMaterial.new()
	plasma_material.shader = load("res://shaders/plasma.gdshader")
	plasma_material.set_shader_parameter("noise", noise_tex)
	plasma = Node3D.new()
	add_child(plasma)
	for c: Array in [[Vector3(0, 0.25, -2.0), 0.0, 4.8], [Vector3(-2.35, 0.25, -0.6), PI / 2.0, 2.8], [Vector3(2.35, 0.25, -0.6), -PI / 2.0, 2.8]]:
		var q := QuadMesh.new()
		q.size = Vector2(c[2], 2.6)
		var m := _mesh(q, plasma_material, c[0], Vector3(0, c[1], 0), plasma)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plasma.visible = false


## Merkkivalojen kirkkaus (0–1) nimen mukaan.
func set_light(name: String, on: float) -> void:
	var m: StandardMaterial3D = lights.get(name)
	if m != null:
		m.emission_energy_multiplier = on * 3.0
