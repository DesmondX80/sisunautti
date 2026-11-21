class_name LunarSurface
extends MeshInstance3D
## Kuun lähipinta laskeutuessa ja pinnalla (#45): säteittäinen verkko aluksen alta horisonttiin
## (shaders/lunar_surface.gdshader), aluksen varjo ja moottorin puhaltama pöly. Näkyy, kun alus on laskeutumiseen
## sopivan kappaleen (Landing.BODIES) lähellä alle ACTIVE_KM korkeudella; silloin kappaleen pallo piilotetaan, koska
## sen tasaiset kolmiot eivät riitä lähelle.

const ACTIVE_KM := 80.0
const RINGS := 160
const SEGMENTS := 256
## Silmän korkeus pinnasta laskeutuneena (m): ohjaamo on laskeutumisjalkojen päällä.
const EYE_M := 4.0
## Aluksen varjon säde (m).
const SHIP_R := 8.0

var mat: ShaderMaterial
var dust: GPUParticles3D
var _dust_mat: StandardMaterial3D
var active := false
var body := ""
## Pinnan korkeus aluksen alla (km, silmä mukaan lukien) viimeisimmästä päivityksestä.
var alt_km := INF
## Auringon korkeus (°) aluksen alla viimeisimmästä päivityksestä (testit ja raportit).
var sun_elev := 0.0


func _ready() -> void:
	mesh = _grid()
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/lunar_surface.gdshader")
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	visible = false
	# Kaukoputki (kohdekamera) näyttää kappaleen pallon; lähipinta ja pöly näkyvät ikkunasta ja ulkokameroista.
	layers = Space.DOT_LAYER
	_build_dust()
	dust.layers = Space.DOT_LAYER


## Verkko: keskipiste ja RINGS rengasta SEGMENTS suuntaan. UV.x = rengas 0–1 (logaritminen etäisyys
## varjostimessa), UV.y = suuntakulma 0–1.
func _grid() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for i in RINGS + 1:
		for j in SEGMENTS + 1:
			verts.append(Vector3(float(i), 0.0, float(j)))
			uvs.append(Vector2(float(i) / RINGS, float(j) / SEGMENTS))
	var w := SEGMENTS + 1
	for i in RINGS:
		for j in SEGMENTS:
			var a := i * w + j
			idx.append_array([a, a + w, a + 1, a + 1, a + w, a + w + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	m.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	return m


## Pöly: hiukkaset lentävät moottorin alta säteittäin pitkin pintaa (tyhjiössä matalassa kaaressa).
func _build_dust() -> void:
	dust = GPUParticles3D.new()
	dust.amount = 600
	dust.lifetime = 2.2
	dust.explosiveness = 0.0
	dust.emitting = false
	dust.visibility_aabb = AABB(Vector3(-200, -20, -200), Vector3(400, 60, 400))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
	pm.emission_ring_axis = Vector3.UP
	pm.emission_ring_radius = 6.0
	pm.emission_ring_inner_radius = 1.5
	pm.emission_ring_height = 0.3
	pm.direction = Vector3(1, 0.04, 0)
	pm.spread = 180.0
	pm.flatness = 1.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 45.0
	pm.gravity = Vector3(0, -1.62, 0)
	pm.scale_min = 0.6
	pm.scale_max = 2.4
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.0))
	fade.add_point(0.15, Color(1, 1, 1, 0.55))
	fade.set_color(fade.get_point_count() - 1, Color(1, 1, 1, 0.0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	dust.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(2.5, 1.2)
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_mat.vertex_color_use_as_albedo = true
	_dust_mat.albedo_texture = _soft_dot()
	_dust_mat.albedo_color = Color(0.55, 0.52, 0.48)
	q.material = _dust_mat
	dust.draw_pass_1 = q
	dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(dust)


static func _soft_dot() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y in 32:
		for x in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			img.set_pixel(x, y, Color(1, 1, 1, pow(clampf(1.0 - d, 0.0, 1.0), 1.8)))
	return ImageTexture.create_from_image(img)


## Päivitys Space.update:sta: b = kappaleen tiedot (Space.bodies), rel_ship = aluksen paikka kappaleen suhteen (m,
## scene), sun_w ja earth_w suunnat (scene), intensity Auringon valo, thrust moottorin työntö 0–1.
func update_surface(b: Dictionary, rel_ship: Vector3, rel_len: float, sun_w: Vector3, earth_w: Vector3, intensity: float,
		earthshine: float, thrust: float, landed: bool, sunlit: float = 1.0) -> void:
	var radius: float = b.radius_m
	var alt := rel_len - radius + (EYE_M if landed else 0.0)
	alt_km = alt / 1000.0
	active = alt_km < ACTIVE_KM
	visible = active
	(b.mesh as MeshInstance3D).layers = Space.SPHERE_NEAR_LAYER if active else 1
	if not active:
		dust.emitting = false
		return
	body = b.name
	var up := rel_ship.normalized()
	var spin_basis := (b.mesh as MeshInstance3D).global_transform.basis.orthonormalized()
	var pole := spin_basis.y.normalized()
	var north := (pole - up * pole.dot(up))
	if north.length() < 1e-6:
		north = spin_basis.z.cross(up)
	north = north.normalized()
	var east := north.cross(up).normalized()
	var bm: ShaderMaterial = b.mat
	mat.set_shader_parameter("albedo_tex", bm.get_shader_parameter("albedo_tex"))
	mat.set_shader_parameter("relief_tex", bm.get_shader_parameter("relief_tex"))
	mat.set_shader_parameter("relief_height", bm.get_shader_parameter("relief_height"))
	mat.set_shader_parameter("up_w", up)
	mat.set_shader_parameter("east_w", east)
	mat.set_shader_parameter("north_w", north)
	mat.set_shader_parameter("world_to_body", spin_basis.inverse())
	mat.set_shader_parameter("radius_m", radius)
	mat.set_shader_parameter("alt_m", alt)
	# Renkaat: lähin noin sadasosa korkeudesta (vähintään 0,5 m), uloin horisontin taakse (vuoret näkyvät kauempaa).
	var s0 := maxf(0.5, alt * 0.01)
	var s_max := sqrt(2.0 * radius * maxf(alt, 1.0)) + 120000.0
	mat.set_shader_parameter("s0", s0)
	mat.set_shader_parameter("s_ratio", s_max / s0)
	mat.set_shader_parameter("sun_w", sun_w)
	# Pimennys (Maa Auringon edessä) himmentää myös pinnan.
	mat.set_shader_parameter("sun_intensity", intensity * sunlit)
	mat.set_shader_parameter("earth_w", earth_w)
	mat.set_shader_parameter("earthshine", earthshine)
	mat.set_shader_parameter("datum_k", 1.0 - smoothstep(1500.0, 6000.0, alt))
	mat.set_shader_parameter("datum_oct", 5 if alt < 300.0 else (2 if alt < 3000.0 else 1))
	# Aluksen varjo: kohta, johon Auringon säde aluksesta osuu (tasainen pinta aluksen alla).
	var e := sun_w.dot(up)
	sun_elev = rad_to_deg(asin(clampf(e, -1.0, 1.0)))
	var k := 0.0
	var shadow_p := Vector3.ZERO
	if e > 0.03 and alt < 2000.0:
		shadow_p = -sun_w * (alt / e)
		k = clampf(1.0 - alt / 1500.0, 0.0, 1.0) * 0.75
	mat.set_shader_parameter("ship_shadow", shadow_p)
	mat.set_shader_parameter("ship_shadow_r", SHIP_R)
	mat.set_shader_parameter("ship_shadow_k", k)
	var blast := clampf(thrust, 0.0, 1.0) * (1.0 - smoothstep(10.0, 40.0, alt))
	mat.set_shader_parameter("blast", blast)
	# Pöly moottorin alla matalalla.
	dust.emitting = blast > 0.05
	dust.amount_ratio = clampf(blast * 1.2, 0.0, 1.0)
	dust.transform = Transform3D(Basis(east, up, -north), -up * alt)
	var day := clampf(e * 4.0 + 0.2, 0.05, 1.0)
	_dust_mat.albedo_color = Color(0.55, 0.52, 0.48) * day * intensity * 0.8


func set_quality(level: int) -> void:
	mat.set_shader_parameter("detail", [0.0, 0.6, 1.0, 1.0][clampi(level, 0, 3)])
	mat.set_shader_parameter("shadow_steps", [6, 10, 14, 20][clampi(level, 0, 3)])
