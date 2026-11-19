class_name LaunchTower
extends Node3D
## Laukaisutorni laukaisualustalla: teräsristikkorakenne (noin 120 m) aluksen vieressä, ukkosenjohdinmasto,
## huoltotasot ja miehistön kulkusilta, vilkkuvat punaiset estevalot ja tasojen valonheittimet. Torni on kiinni Maan
## pinnassa: sen paikka lasketaan laukaisupaikasta (Flight.launch_state ilman laukaisua), joten nousussa torni
## liukuu alas ja katoaa näkyvistä korkeuden kasvaessa. Yksikkö metri, torni piirretään aluksen suhteen.

## Renderöintikerros: kappaleen heijastama valo (CockpitView.shine) ei valaise tornia, koska torni seisoo Maan päällä.
const LAYER := 2
## Tornin keskilinja aluksen ohjaamosta: sivulle (oikealle) ja katon suuntaan (m), jotta yläosa näkyy ikkunasta.
const OFFSET_RIGHT := 10.0
const OFFSET_ROOF := 12.0
const HEIGHT := 118.0 # tornin korkeus maasta
const WIDTH := 9.0
const LEVEL := 6.0 # ristikon kerroskorkeus
const MAST := 16.0 # ukkosenjohdinmasto tornin päällä
const HIDE_ALT_KM := 4.0

var _lights: Array[MeshInstance3D] = []
var _light_mat: StandardMaterial3D
var _lamp_mat: StandardMaterial3D
var _floods: Array[OmniLight3D] = []


func _ready() -> void:
	# Pääpalkit punaoranssit (kuten Saturn V:n laukaisutorni), tuet harmaata terästä.
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.16, 0.035, 0.015)
	paint.roughness = 0.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.05, 0.055, 0.06)
	steel.metallic = 0.25
	steel.roughness = 0.7
	var deck := StandardMaterial3D.new()
	deck.albedo_color = Color(0.03, 0.03, 0.035)
	deck.metallic = 0.1
	deck.roughness = 0.8
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.3, 0.08, 0.02)
	accent.metallic = 0.4
	accent.roughness = 0.6
	# Valaistus on mitoitettu avaruuteen: taivaan heijastus ja ympäristövalo ylivalottaisivat tornin.
	for m: StandardMaterial3D in [paint, steel, deck, accent]:
		m.metallic = 0.0
		m.metallic_specular = 0.15
		m.disable_ambient_light = true
	var truss := _truss()
	_add_mesh(truss[0], paint)
	_add_mesh(truss[1], steel)
	_add_mesh(_decks(), deck)
	_add_mesh(_arm(), accent)
	# Estevalot: punaiset, vilkkuvat (hehku). Valonheittimet: lämpimän valkoiset, näkyvät yöllä.
	_light_mat = _glow_material(Color(1.0, 0.12, 0.08))
	_lamp_mat = _glow_material(Color(1.0, 0.88, 0.68))
	var h := WIDTH / 2.0
	for p: Vector3 in [Vector3(-h, HEIGHT + 0.4, -h), Vector3(h, HEIGHT + 0.4, -h), Vector3(-h, HEIGHT + 0.4, h),
			Vector3(h, HEIGHT + 0.4, h), Vector3(0, HEIGHT + MAST + 0.5, 0), Vector3(-h, HEIGHT * 0.6, -h), Vector3(h, HEIGHT * 0.6, h)]:
		_lights.append(_dot(p, 0.45, _light_mat))
	for y in range(18, int(HEIGHT), 24):
		for x: float in [-h - 0.6, h + 0.6]:
			_dot(Vector3(x, float(y) + 1.2, -h - 0.6), 0.3, _lamp_mat)
		# Valonheittimet valaisevat tornia yöllä.
		var flood := OmniLight3D.new()
		flood.light_color = Color(1.0, 0.85, 0.62)
		flood.omni_range = 40.0
		flood.omni_attenuation = 1.2
		flood.shadow_enabled = false
		flood.position = Vector3(0, float(y) + 3.0, -h - 4.0)
		add_child(flood)
		_floods.append(flood)


static func _glow_material(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	return m


func _add_mesh(mesh: ArrayMesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.layers = LAYER
	add_child(mi)


func _dot(p: Vector3, r: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = r
	sphere.height = r * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	mi.mesh = sphere
	mi.material_override = mat
	mi.position = p
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Palkki pisteestä a pisteeseen b, poikkileikkaus w × w (kuusi tahkoa).
static func _beam(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	var axis := b - a
	var len := axis.length()
	if len < 1e-4:
		return
	var z := axis / len
	var x := z.cross(Vector3.UP if absf(z.y) < 0.95 else Vector3.RIGHT).normalized() * (w / 2.0)
	var y := z.cross(x).normalized() * (w / 2.0)
	var c := [a - x - y, a + x - y, a + x + y, a - x + y, b - x - y, b + x - y, b + x + y, b - x + y]
	for f: Array in [[0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7], [3, 2, 1, 0], [4, 5, 6, 7]]:
		var p0: Vector3 = c[f[0]]
		var p1: Vector3 = c[f[1]]
		var p2: Vector3 = c[f[2]]
		var p3: Vector3 = c[f[3]]
		var n := (p1 - p0).cross(p2 - p0).normalized()
		st.set_normal(n)
		for p: Vector3 in [p0, p1, p2, p0, p2, p3]:
			st.add_vertex(p)


## Ristikko: pystypalkit ja vaakapalkit (frame) sekä vinotuet ja maston tuet (braces).
func _truss() -> Array[ArrayMesh]:
	var frame := SurfaceTool.new()
	frame.begin(Mesh.PRIMITIVE_TRIANGLES)
	var braces := SurfaceTool.new()
	braces.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := WIDTH / 2.0
	var corners := [Vector3(-h, 0, -h), Vector3(h, 0, -h), Vector3(h, 0, h), Vector3(-h, 0, h)]
	for c: Vector3 in corners:
		_beam(frame, c, c + Vector3(0, HEIGHT, 0), 0.8)
	var y := 0.0
	while y < HEIGHT - 0.1:
		var y1 := minf(y + LEVEL, HEIGHT)
		for i in 4:
			var a: Vector3 = corners[i]
			var b: Vector3 = corners[(i + 1) % 4]
			_beam(frame, a + Vector3(0, y1, 0), b + Vector3(0, y1, 0), 0.45)
			# Vinotuet ristiin jokaisella sivulla.
			_beam(braces, a + Vector3(0, y, 0), b + Vector3(0, y1, 0), 0.22)
			_beam(braces, b + Vector3(0, y, 0), a + Vector3(0, y1, 0), 0.22)
		y = y1
	# Ukkosenjohdinmasto ja sen tuet.
	var top := Vector3(0, HEIGHT, 0)
	_beam(braces, top, top + Vector3(0, MAST, 0), 0.35)
	for c: Vector3 in corners:
		_beam(braces, c + Vector3(0, HEIGHT, 0), top + Vector3(0, MAST * 0.45, 0), 0.18)
	return [frame.commit(), braces.commit()]


func _decks() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := WIDTH / 2.0 + 0.8
	for y in range(12, int(HEIGHT), 24):
		var st_y := float(y)
		# Taso: matala laatikko koko tornin levyltä ja kaide.
		_slab(st, Vector3(0, st_y, 0), Vector3(h * 2.0, 0.35, h * 2.0))
		for s: float in [-h, h]:
			_beam(st, Vector3(-h, st_y + 1.1, s), Vector3(h, st_y + 1.1, s), 0.08)
			_beam(st, Vector3(s, st_y + 1.1, -h), Vector3(s, st_y + 1.1, h), 0.08)
	_slab(st, Vector3(0, HEIGHT, 0), Vector3(WIDTH + 1.0, 0.5, WIDTH + 1.0))
	return st.commit()


static func _slab(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var hx := size.x / 2.0
	var hz := size.z / 2.0
	var hy := size.y / 2.0
	var c := center
	var p := [c + Vector3(-hx, -hy, -hz), c + Vector3(hx, -hy, -hz), c + Vector3(hx, hy, -hz), c + Vector3(-hx, hy, -hz),
		c + Vector3(-hx, -hy, hz), c + Vector3(hx, -hy, hz), c + Vector3(hx, hy, hz), c + Vector3(-hx, hy, hz)]
	for f: Array in [[0, 3, 2, 1], [4, 5, 6, 7], [0, 1, 5, 4], [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5]]:
		var p0: Vector3 = p[f[0]]
		var p1: Vector3 = p[f[1]]
		var p2: Vector3 = p[f[2]]
		var p3: Vector3 = p[f[3]]
		st.set_normal((p1 - p0).cross(p2 - p0).normalized())
		for v: Vector3 in [p0, p1, p2, p0, p2, p3]:
			st.add_vertex(v)


## Miehistön kulkusilta ohjaamon korkeudella kohti alusta: tornin paikallisissa koordinaateissa x on oikealle ja z katon
## suuntaan, joten ohjaamo on kohdassa (−OFFSET_RIGHT, PAD_ALT, −OFFSET_ROOF).
func _arm() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := Flight.PAD_ALT_KM * 1000.0 - 1.5
	var from := Vector3(-WIDTH / 2.0, y, -WIDTH / 2.0)
	var to := Vector3(-OFFSET_RIGHT + 2.5, y, -OFFSET_ROOF + 2.5)
	_slab(st, (from + to) / 2.0, Vector3(2.4, 0.4, 2.4))
	for s: float in [-1.1, 1.1]:
		_beam(st, from + Vector3(s, 0.2, 0), to + Vector3(s, 0.2, 0), 0.2)
		_beam(st, from + Vector3(s, 2.4, 0), to + Vector3(s, 2.4, 0), 0.15)
	_beam(st, from, to, 1.6)
	return st.commit()


## Paikka ja asento hetkellä t: s on CockpitState (laukaisualustalla ja nousussa). Torni näkyy vain alustalla ja nousun
## alussa.
func update(s: Dictionary) -> void:
	visible = Game.state.pad and float(s.get("alt", 99.0)) < HIDE_ALT_KM
	if not visible:
		return
	var t: float = s.t
	# Nousumalli ei kierry Maan mukana, joten laukaisun jälkeen torni pysyy laukaisuhetken paikassa.
	var ascent: Variant = Game.state.get("ascent")
	var lift: Variant = ascent.get("liftoff") if ascent is Dictionary else null
	var pad := Flight.launch_state(null, minf(t, float(lift)) if lift != null else t)
	var ship_rel: PackedFloat64Array = Flight.sub(s.ship.r, Flight.planet_state("Maa", t).r)
	var pad_rel: PackedFloat64Array = pad.rel.r
	var up_e: PackedFloat64Array = Flight.scale(pad.nose, 1.0 / Flight.norm(pad.nose)) # pystysuunta laukaisupaikalla
	var roof_e: PackedFloat64Array = pad.up # katon suunta alustalla (vaakasuora)
	var right_e := Flight.cross(up_e, roof_e)
	# Tornin juuri maan pinnalla: alustan ohjaamon kohdalta PAD_ALT_KM alas ja sivuun.
	var base := Flight.add(pad_rel, Flight.scale(up_e, -Flight.PAD_ALT_KM))
	base = Flight.add(base, Flight.add(Flight.scale(right_e, OFFSET_RIGHT / 1000.0), Flight.scale(roof_e, OFFSET_ROOF / 1000.0)))
	position = Space.to_scene(Flight.scale(Flight.sub(base, ship_rel), 1000.0))
	var y := Space.to_scene(up_e).normalized()
	var x := Space.to_scene(right_e).normalized()
	var z := x.cross(y).normalized()
	basis = Basis(x, y, z)
	# Estevalot vilkkuvat sekunnin välein; hehku HDR:nä.
	var on := fmod(Time.get_ticks_msec() / 1000.0, 1.4) < 0.7
	_light_mat.emission_energy_multiplier = 8.0 if on else 0.3
	var night := 1.0 - clampf(float(s.get("sky", 0.0)) * 3.0, 0.0, 1.0)
	_lamp_mat.emission_energy_multiplier = lerpf(0.5, 3.0, night)
	for f in _floods:
		f.light_energy = 7.0 * night
		f.visible = night > 0.01
