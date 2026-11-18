class_name CockpitView
extends SubViewportContainer
## 3D-ohjaamo (web/js/cockpit.js): pelaaja istuu aluksessa ja katsoo ikkunasta ulos. Näkymä on oma SubViewport,
## jolla on oma 3D-maailma, ympäristö ja laatutasot. Aluksen asento kääntyy pehmeästi kohti kohdetta, katsetta
## käännetään raahaamalla, näyttöä napsauttamalla katse zoomaa siihen (rullalla tai nipistämällä vapaasti), ja ohjaamon valaistus tulee Auringon suunnasta (varjot), lähimmästä kappaleesta
## (heijastunut valo), moottorista, näytöistä ja kattovalosta.

const SKY_DAY := Color(0.31, 0.56, 0.82)
const SKY_LIGHT := Color(0.66, 0.8, 1.0)

var viewport: SubViewport
var world: Node3D
var env: Environment
var cam_attr: CameraAttributesPractical
var ship: Node3D
var head: Node3D
var camera: Camera3D
var cabin: Cabin
var space: Space
var sky_mat: ShaderMaterial
var sun_beam: DirectionalLight3D
var shine: DirectionalLight3D
var ceiling: OmniLight3D
var engine: OmniLight3D
var screen_glow: OmniLight3D
var plasma_light: OmniLight3D
var flare: MeshInstance3D
var flare_mat: ShaderMaterial
var exhaust: GPUParticles3D
var smoke: GPUParticles3D
var sparks: GPUParticles3D
var tools: HBoxContainer
var overlay: ColorRect # ohjaamon kuva ja näytöt 3D-näkymän päällä
var overlay_mat: ShaderMaterial
var zoom_out_button: Button

## Pystykulma ilman zoomausta, tavoitekulma ja näyttö, johon on zoomattu (−1 = ei mihinkään).
var base_fov := 70.0
var fov_target := 70.0
var zoom_index := -1
var _look_target: Variant = null # Vector2(yaw, pitch), kun katse kääntyy itsestään
var _pre_zoom := Vector2.ZERO
var _press_moved := 0.0
var _bodies := {} # nimi → avaruuden kappale (näyttöjen pallot)

var yaw := 0.0
var pitch := 0.0
var _dragging := false
var _attitude_ready := false
var _main_at := 0.0
var _state: Dictionary = {}
var _sky_key := Vector4(-1, 0, 0, 0)
var quality := -1
var frame_ms := 0.0


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_3d = false
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	_build_environment()
	space = Space.new()
	world.add_child(space)
	ship = Node3D.new()
	world.add_child(ship)
	head = Node3D.new()
	ship.add_child(head)
	camera = Camera3D.new()
	camera.near = 0.02
	camera.far = 1.2e5
	camera.fov = 70.0
	camera.attributes = cam_attr
	head.add_child(camera)
	cabin = Cabin.new()
	ship.add_child(cabin)
	_build_lights()
	_build_particles()
	_build_flare()
	_build_overlay()
	_build_tools()
	Settings.quality_changed.connect(apply_quality)
	apply_quality(Settings.quality)
	resized.connect(_fit_fov)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("scene_to_eq", Space.scene_to_equatorial())
	var loader := BodyTextures.new()
	loader.threaded = false
	sky_mat.set_shader_parameter("milkyway", loader.get_texture(BodyTextures.DIR + "linnunrata-4k.webp"))
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.05
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_normalized = false
	env.glow_intensity = 0.6
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.5
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		env.set_glow_level(i, 1.0 if i >= 1 and i <= 5 else 0.0)
	cam_attr = CameraAttributesPractical.new()
	# Automaattinen valotus: silmä tottuu hitaasti. Herkkyys rajataan, jotta tumma avaruus ei ylivalota ohjaamoa.
	cam_attr.auto_exposure_scale = 0.3
	cam_attr.auto_exposure_speed = 0.8
	cam_attr.auto_exposure_min_sensitivity = 40.0
	cam_attr.auto_exposure_max_sensitivity = 120.0
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)


func _build_lights() -> void:
	sun_beam = DirectionalLight3D.new()
	sun_beam.light_color = Color(1.0, 0.96, 0.89)
	sun_beam.light_energy = 3.0
	sun_beam.shadow_enabled = true
	sun_beam.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun_beam.directional_shadow_max_distance = 6.0
	sun_beam.shadow_bias = 0.03
	sun_beam.shadow_normal_bias = 1.0
	sun_beam.shadow_blur = 1.5
	world.add_child(sun_beam)
	shine = DirectionalLight3D.new()
	shine.light_energy = 0.0
	shine.shadow_enabled = false
	world.add_child(shine)
	ceiling = OmniLight3D.new()
	ceiling.light_color = Color(1.0, 0.91, 0.8)
	ceiling.light_energy = 0.6
	ceiling.omni_range = 4.0
	ceiling.position = Vector3(0, 0.6, 0.2)
	ceiling.light_specular = 0.0
	cabin.add_child(ceiling)
	screen_glow = OmniLight3D.new()
	screen_glow.light_color = Color(0.37, 0.84, 1.0)
	screen_glow.light_energy = 0.35
	screen_glow.omni_range = 1.6
	screen_glow.position = Vector3(0, -0.1, -1.0)
	screen_glow.light_specular = 0.0 # näytöt valaisevat, mutta eivät näy heijastuksena
	cabin.add_child(screen_glow)
	engine = OmniLight3D.new()
	engine.light_color = Color(1.0, 0.54, 0.23)
	engine.light_energy = 0.0
	engine.omni_range = 6.0
	engine.position = Vector3(0, -0.6, 1.6)
	engine.light_specular = 0.3
	cabin.add_child(engine)
	plasma_light = OmniLight3D.new()
	plasma_light.light_color = Color(1.0, 0.45, 0.15)
	plasma_light.light_energy = 0.0
	plasma_light.omni_range = 5.0
	plasma_light.position = Vector3(0, 0.3, -2.2)
	cabin.add_child(plasma_light)


func _particles(amount: int, color: Color, size: float, lifetime: float, velocity: Vector2, spread: float, emissive: float) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, -1, 0)
	pm.spread = spread
	pm.initial_velocity_min = velocity.x
	pm.initial_velocity_max = velocity.y
	pm.gravity = Vector3.ZERO
	pm.scale_min = size * 0.6
	pm.scale_max = size * 1.4
	pm.damping_min = 2.0
	pm.damping_max = 6.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.9))
	ramp.set_color(1, Color(color.darkened(0.4), 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = ramp
	pm.color_ramp = gt
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED if emissive > 0.0 else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = _soft_dot()
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emissive
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	q.material = m
	p.draw_pass_1 = q
	p.visibility_aabb = AABB(Vector3(-60, -120, -60), Vector3(120, 160, 120))
	return p


func _soft_dot() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 64
	t.height = 64
	return t


func _build_particles() -> void:
	# Laukaisun liekki ja pakokaasupilvi aluksen alla; ilmajarrutuksen kipinät ikkunoiden ohi.
	exhaust = _particles(400, Color(1.0, 0.6, 0.25), 2.5, 0.6, Vector2(40, 70), 6.0, 6.0)
	exhaust.position = Vector3(0, -14, 1.0)
	ship.add_child(exhaust)
	smoke = _particles(500, Color(0.75, 0.73, 0.7), 14.0, 6.0, Vector2(8, 22), 70.0, 0.0)
	smoke.position = Vector3(0, -30, 1.0)
	ship.add_child(smoke)
	sparks = _particles(300, Color(1.0, 0.7, 0.35), 0.06, 0.5, Vector2(30, 50), 25.0, 8.0)
	sparks.position = Vector3(0, 0.4, -4.0)
	(sparks.process_material as ParticleProcessMaterial).direction = Vector3(0, 0, 1)
	(sparks.process_material as ParticleProcessMaterial).emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	(sparks.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(3, 1.5, 0.5)
	ship.add_child(sparks)


func _build_flare() -> void:
	# Koko näkymän peittävä taso, joka piirretään viimeisenä ja lukee syvyyspuskurin.
	flare = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2, 2)
	flare.mesh = q
	flare_mat = ShaderMaterial.new()
	flare_mat.shader = load("res://shaders/flare.gdshader")
	flare_mat.render_priority = 100
	flare.material_override = flare_mat
	flare.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flare.extra_cull_margin = 16384.0
	flare.position = Vector3(0, 0, -1)
	camera.add_child(flare)


func _build_overlay() -> void:
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_mat = ShaderMaterial.new()
	overlay_mat.shader = load("res://shaders/cockpit_overlay.gdshader")
	overlay_mat.set_shader_parameter("image", load("res://assets/cockpit/ohjaamo.png"))
	overlay_mat.set_shader_parameter("image_size", Cabin.IMAGE_SIZE)
	overlay_mat.set_shader_parameter("image_center", Cabin.CENTER)
	overlay_mat.set_shader_parameter("focal", Cabin.FOCAL)
	for i in cabin.monitors.size():
		overlay_mat.set_shader_parameter("screen%d" % i, cabin.monitors[i].texture)
		overlay_mat.set_shader_parameter("homography%d" % i, cabin.monitors[i].homography)
	overlay.material = overlay_mat
	add_child(overlay)


## Kerroksen kamera: kanta aluksen koordinaateissa, kuvakulma ja kuvasuhde.
func _update_overlay() -> void:
	overlay_mat.set_shader_parameter("cam_basis", ship.global_transform.basis.inverse() * camera.global_transform.basis)
	overlay_mat.set_shader_parameter("tan_half", tan(deg_to_rad(camera.fov) / 2.0))
	overlay_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))


func _build_tools() -> void:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	m.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(m)
	tools = UiKit.hbox(6)
	m.add_child(tools)
	var reset := UiKit.button("Katse eteen", reset_view)
	reset.tooltip_text = "Palauta katse eteenpäin (raahaa kääntääksesi, napsauta näyttöä zoomataksesi)"
	tools.add_child(reset)
	zoom_out_button = UiKit.button("Loitonna", zoom_out)
	zoom_out_button.tooltip_text = "Palauta näkymä (Esc)"
	zoom_out_button.visible = false
	tools.add_child(zoom_out_button)


## Kääntää katseen scene-suuntaan dir (kuvakaappaukset ja testit).
func look_toward(dir: Vector3) -> void:
	var local := ship.basis.inverse() * dir.normalized()
	yaw = clampf(atan2(-local.x, -local.z), -2.6, 2.6)
	pitch = clampf(asin(clampf(local.y, -1.0, 1.0)), -1.2, 1.05)


## Suunta kappaleeseen (scene) aluksesta.
func direction_to(name: String) -> Vector3:
	if name == "Aurinko":
		return space.sun_dir
	var t := Game.sim_now()
	return Space.to_scene(Flight.sub(Flight.body_state(name, t).r, _state.ship.r)).normalized()


## Kääntää aluksen nokan scene-suuntaan (kuvakaappaukset; pysyy, kun kohdetta ei ole).
func face(dir: Vector3) -> void:
	ship.basis = Basis.looking_at(dir.normalized(), Vector3.UP)
	_attitude_ready = true


## Asento suoraan tavoitteeseen seuraavalla ruudulla (tilan hyppäys, kuvakaappaukset).
func snap_attitude() -> void:
	_attitude_ready = false


func reset_view() -> void:
	yaw = 0.0
	pitch = 0.0
	zoom_index = -1
	_look_target = null
	fov_target = base_fov
	camera.fov = base_fov


## Zoomaa näyttöön i (cabin.monitors): katse kääntyy sen keskelle ja kuvakulma kapenee niin, että näyttö täyttää kuvan.
func zoom_to(i: int) -> void:
	if i < 0 or i >= cabin.monitors.size():
		return
	if zoom_index < 0:
		_pre_zoom = Vector2(yaw, pitch)
	var corners: PackedVector3Array = cabin.monitors[i].corners
	var center := Vector3.ZERO
	for c in corners:
		center += c / 4.0
	var dir := (cabin.transform * center).normalized()
	var look := Vector2(atan2(-dir.x, -dir.z), asin(clampf(dir.y, -1.0, 1.0)))
	# Kulmien suunnat katseen koordinaateissa: kuvakulma niin, että koko näyttö mahtuu kuvaan.
	var inv := Basis.from_euler(Vector3(look.y, look.x, 0.0), EULER_ORDER_YXZ).inverse()
	var aspect := size.x / size.y if size.x > 0.0 and size.y > 0.0 else 16.0 / 9.0
	var half := 0.0
	for c in corners:
		var v := inv * (cabin.transform * c)
		half = maxf(half, maxf(absf(v.y / v.z), absf(v.x / v.z) / aspect))
	fov_target = rad_to_deg(2.0 * atan(half * 1.08))
	_look_target = look
	zoom_index = i


## Palauttaa kuvakulman ja katseen zoomausta edeltäneeseen suuntaan.
func zoom_out() -> void:
	if zoom_index >= 0:
		_look_target = _pre_zoom
	zoom_index = -1
	fov_target = base_fov


## Vapaa zoomaus kertoimella (rulla, nipistys): < 1 lähemmäs.
func zoom_by(f: float) -> void:
	fov_target = clampf(fov_target * f, 5.0, base_fov)
	zoom_index = -1


## Näyttö, jonka päällä kohta p (näkymän koordinaatit) on, tai −1.
func monitor_at(p: Vector2) -> int:
	for i in cabin.monitors.size():
		var poly := PackedVector2Array()
		for c: Vector3 in cabin.monitors[i].corners:
			var wp := cabin.global_transform * c
			if camera.is_position_behind(wp):
				break
			poly.append(camera.unproject_position(wp))
		if poly.size() == 4 and Geometry2D.is_point_in_polygon(p, poly):
			return i
	return -1


func _click(p: Vector2) -> void:
	var i := monitor_at(p)
	if i >= 0 and i != zoom_index:
		zoom_to(i)
	elif zoom_index >= 0 or fov_target < base_fov - 0.5:
		zoom_out()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			if mb.pressed:
				_press_moved = 0.0
			elif _press_moved < 8.0:
				_click(mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_by(0.85)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_by(1.0 / 0.85)
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.index == 0:
			_dragging = st.pressed
			if st.pressed:
				_press_moved = 0.0
			elif _press_moved < 12.0:
				_click(st.position)
		accept_event()
	elif event is InputEventMagnifyGesture:
		zoom_by(1.0 / maxf(0.01, (event as InputEventMagnifyGesture).factor))
		accept_event()
	elif (event is InputEventMouseMotion and _dragging) or event is InputEventScreenDrag:
		var rel: Vector2 = event.relative
		_press_moved += rel.length()
		if _press_moved >= 8.0:
			# Raahaus kääntää katsetta; zoomattuna hitaammin.
			var k := 0.005 * camera.fov / base_fov
			yaw = clampf(yaw - rel.x * k, -2.6, 2.6)
			pitch = clampf(pitch - rel.y * k, -1.2, 1.05)
			_look_target = null
			zoom_index = -1
		accept_event()
	elif event is InputEventMouseMotion:
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if monitor_at((event as InputEventMouseMotion).position) >= 0 else Control.CURSOR_ARROW


func _unhandled_key_input(event: InputEvent) -> void:
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel") and fov_target < base_fov - 0.5:
		zoom_out()
		get_viewport().set_input_as_handled()


# Pystykulma niin, että ohjaamon kuva täyttää näkymän (kapeassa ikkunassa katsetta käännetään sivuille).
func _fit_fov() -> void:
	if size.y <= 0.0:
		return
	var aspect := size.x / size.y
	var zoomed := fov_target < base_fov - 0.5
	# Ohjaamon kuva täyttää näkymän: kuvakulma enintään kuvan pysty- ja vaakakulma.
	var half_v := Cabin.IMAGE_SIZE.y / 2.0 / Cabin.FOCAL
	var half_h := Cabin.IMAGE_SIZE.x / 2.0 / Cabin.FOCAL
	base_fov = rad_to_deg(2.0 * atan(minf(half_v, half_h / aspect) * 0.97))
	if zoom_index >= 0:
		zoom_to(zoom_index)
	elif not zoomed:
		fov_target = base_fov
		camera.fov = base_fov


## Laatutaso: varjot, SSAO, SSR, reunanpehmennys, partikkelit, karttojen tarkkuus ja ilmakehän näytteet.
func apply_quality(level: int) -> void:
	quality = level
	var compat := Settings.is_compatibility()
	var shadow: int = [1024, 2048, 4096, 4096][level]
	RenderingServer.directional_shadow_atlas_set_size(shadow, true)
	sun_beam.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if level == 0 else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun_beam.shadow_blur = [0.5, 1.0, 1.5, 2.0][level]
	RenderingServer.directional_soft_shadow_filter_set_quality([RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW,
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM, RenderingServer.SHADOW_QUALITY_SOFT_HIGH][level])
	env.ssao_enabled = not compat and level >= 2
	env.ssao_radius = 0.6
	env.ssao_intensity = 1.6
	env.ssr_enabled = not compat and level >= 3
	env.ssr_max_steps = 48
	env.ssil_enabled = false
	env.glow_enabled = true
	viewport.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_4X][level]
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if level == 0 else Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.positional_shadow_atlas_size = [1024, 2048, 2048, 4096][level]
	cam_attr.auto_exposure_enabled = not compat and level >= 1
	exhaust.amount = [80, 200, 400, 800][level]
	smoke.amount = [100, 250, 500, 900][level]
	sparks.amount = [60, 150, 300, 600][level]
	space.max_texture = [2048, 4096, 8192, 8192][level]
	space.atmo_samples = [4, 6, 10, 16][level]


func _ecl_to_scene(v: Variant) -> Vector3:
	return Space.to_scene(v)


func _process(delta: float) -> void:
	if not is_visible_in_tree() or Game.state.is_empty():
		return
	var t0 := Time.get_ticks_usec()
	_state = CockpitState.make()
	var s := _state
	var t: float = s.t
	var ship_km: PackedFloat64Array = s.ship.r
	var px_per_rad := size.y / 2.0 / tan(deg_to_rad(camera.fov) / 2.0)
	space.update(ship_km, t, px_per_rad)
	_attitude(s, delta)
	_zoom_step(delta)
	# Katse ja tärinä: nopeaa värinää, hitaampaa heiluntaa ja pientä kiertoa (zoomattuna vähemmän).
	var rumble := clampf(float(s.shake), 0.0, 1.0) * camera.fov / base_fov
	var tt := Time.get_ticks_msec() / 1000.0
	var jitter := func(k: float) -> float: return (randf() - 0.5) * k * rumble
	head.basis = Basis.from_euler(Vector3(pitch, yaw, 0.0), EULER_ORDER_YXZ) * Basis.from_euler(Vector3(jitter.call(0.014), jitter.call(0.01), jitter.call(0.012)))
	# Vain kiertoa: siirtymä liikuttaisi näyttöjä ohjaamon kuvan päällä.
	head.basis = head.basis * Basis.from_euler(Vector3((sin(tt * 31.0) * 0.4 + sin(tt * 47.0 + 1.0) * 0.3) * 0.012 * rumble, sin(tt * 23.0) * 0.006 * rumble, 0.0))
	camera.position = Vector3.ZERO
	_update_overlay()
	_lighting(s)
	_effects(s)
	_screens(s)
	frame_ms = (Time.get_ticks_usec() - t0) / 1000.0


# Zoomaus ja katseen kääntö kohti zoomattua näyttöä pehmeästi.
func _zoom_step(delta: float) -> void:
	var k := minf(1.0, delta * 7.0)
	if _look_target != null:
		var t: Vector2 = _look_target
		yaw = lerp_angle(yaw, t.x, k)
		pitch = lerpf(pitch, t.y, k)
		if absf(angle_difference(yaw, t.x)) < 1e-4 and absf(pitch - t.y) < 1e-4:
			_look_target = null
	camera.fov = lerpf(camera.fov, fov_target, k)
	zoom_out_button.visible = fov_target < base_fov - 0.5


# Aluksen asento: nokka kohteeseen (aim) tai annettuun suuntaan (nose, up), käännös pehmeästi.
func _attitude(s: Dictionary, delta: float) -> void:
	var want: Basis = ship.basis
	if s.get("nose") != null:
		var nose := _ecl_to_scene(s.nose).normalized()
		var up := _ecl_to_scene(s.up if s.get("up") != null else PackedFloat64Array([0, 0, 1])).normalized()
		want = Basis.looking_at(nose, up)
	elif s.get("aim") != null:
		var aim_km: PackedFloat64Array = Flight.body_state(s.aim, s.t).r
		var dir := Space.to_scene(Flight.sub(aim_km, s.ship.r)).normalized()
		want = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK)
	if not _attitude_ready:
		ship.basis = want
		_attitude_ready = true
	else:
		var q := ship.basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), minf(1.0, delta / 1.5))
		ship.basis = Basis(q)


func _lighting(s: Dictionary) -> void:
	var inv := ship.basis.inverse()
	var sun_local := inv * space.sun_dir
	var dist_factor := clampf(sqrt(Space.AU_M / space.sun_distance), 0.3, 1.3)
	# Auringonvalo ohjaamossa (DirectionalLight osoittaa valon kulkusuuntaan).
	sun_beam.basis = Basis.looking_at(-space.sun_dir, Vector3.UP if absf(space.sun_dir.y) < 0.99 else Vector3.BACK)
	sun_beam.light_energy = 3.2 * dist_factor * space.sunlit
	sun_beam.visible = sun_beam.light_energy > 0.01
	# Lähimmän kappaleen heijastama valo: väri kohteen mukaan, voimakkuus näennäisen koon ja vaiheen mukaan.
	if not space.nearest.is_empty() and space.nearest_size > 0.02:
		var b: Dictionary = space.nearest
		var pos: Vector3 = (b.root as Node3D).position
		var to_sun := (space.sun_dir * 1e9 - pos).normalized()
		var phase := (1.0 + to_sun.dot(-pos.normalized())) / 2.0
		var sz := minf(1.0, space.nearest_size)
		shine.light_color = (b.color as Color).lerp(Color.WHITE, 0.45)
		shine.light_energy = minf(0.8, 3.0 * sz * sz * phase + 0.3 * sz * phase) * dist_factor
		shine.basis = Basis.looking_at(pos.normalized(), Vector3.UP if absf(pos.normalized().y) < 0.99 else Vector3.BACK)
	else:
		shine.light_energy = 0.0
	# Taivas: päivätaivas laukaisussa, ilmajarrutuksen hehku; tähdet himmenevät kirkkaalla taivaalla.
	var sky := clampf(float(s.sky), 0.0, 1.0)
	var sky_color: Variant = s.get("sky_color")
	# Taivaan heijastukset lasketaan uudelleen vain, kun taivas muuttuu (päivätaivas, hehku, Auringon suunta).
	var sky_key := Vector4(snappedf(sky, 0.01), space.sun_dir.x, space.sun_dir.y, space.sun_dir.z).snappedf(0.01)
	if sky_key != _sky_key:
		_sky_key = sky_key
		sky_mat.set_shader_parameter("day", sky)
		sky_mat.set_shader_parameter("day_color", sky_color if sky_color != null else SKY_DAY)
		sky_mat.set_shader_parameter("sun_dir", space.sun_dir)
	space.star_material.set_shader_parameter("fade", maxf(0.0, 1.0 - sky * 2.5))
	env.ambient_light_color = (sky_color if sky_color != null else SKY_LIGHT) if sky > 0.0 else Color(0.55, 0.6, 0.7)
	env.ambient_light_energy = 0.05 + sky * 0.5
	# Lasin häikäisy ja linssiheijastus.
	var view_inv := camera.global_transform.basis.inverse()
	var sun_view := view_inv * space.sun_dir
	cabin.glass_material.set_shader_parameter("sun_dir_view", sun_view)
	var through := Cabin.through_window(sun_local)
	cabin.glass_material.set_shader_parameter("sun_visible", space.sunlit * (1.0 if through else 0.0) * (1.0 - sky))
	var vis := 0.0
	var sun_uv := Vector2(-1, -1)
	if sun_view.z < 0.0 and not camera.is_position_behind(space.sun_dir * 1e6):
		var sp := camera.unproject_position(space.sun_dir * 1e6)
		sun_uv = sp / size
		if sun_uv.x > -0.2 and sun_uv.x < 1.2 and sun_uv.y > -0.2 and sun_uv.y < 1.2:
			vis = space.sunlit * dist_factor * (1.0 if through else 0.0) # ohjaamon kuva peittää Auringon ikkunan ulkopuolella
	var look := maxf(0.0, -sun_view.z)
	flare.visible = vis > 0.0
	flare_mat.set_shader_parameter("sun_uv", sun_uv)
	flare_mat.set_shader_parameter("intensity", vis * (0.6 if quality >= 1 else 0.4))
	flare_mat.set_shader_parameter("glare", pow(look, 60.0) * vis)
	flare_mat.set_shader_parameter("aspect", size.x / maxf(1.0, size.y))


func _effects(s: Dictionary) -> void:
	var thrust := float(s.thrust)
	engine.light_energy = thrust * 6.0 * (0.85 + randf() * 0.3)
	var aero := float(s.get("aero", 0.0))
	space.dim = 1.0 - 0.6 * aero # plasma peittää näkymän ulos
	cabin.plasma.visible = aero > 0.0
	cabin.plasma_material.set_shader_parameter("intensity", aero * 0.18)
	plasma_light.light_energy = aero * 1.8 * (0.8 + randf() * 0.4)
	sparks.emitting = aero > 0.1
	var launching: bool = Game.state.pad and float(s.get("tau", -1.0)) >= -3.0
	exhaust.emitting = launching and thrust > 0.0
	smoke.emitting = launching and float(s.get("alt", 99.0)) < 3.0
	# Merkkivalot ja vipu pelin tilan mukaan.
	cabin.set_light("moottori", clampf(thrust * 1.5, 0.0, 1.0))
	cabin.set_light("kiihdytys", 1.0 if float(s.warp) > 1.0 else 0.15)
	cabin.set_light("polttoaine", 1.0 if float(s.fuel) > 0.2 else 0.0)
	var low := 1.0 if float(s.fuel) <= 0.2 else 0.0
	cabin.set_light("ilmakeha", maxf(aero, low * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 200.0))))
	var f: Variant = Game.state.flight
	cabin.set_light("vaikutuspiiri", 1.0 if f != null and float(s.t) >= float(f.soi) else 0.1)
	cabin.set_light("suunta", 1.0 if s.get("aim") != null or s.get("nose") != null else 0.1)
	# Moottorin ja plasman hehku ohjaamon kuvassa.
	var glow := Color(1.0, 0.54, 0.23) * (thrust * 0.12 * (0.85 + randf() * 0.3)) + Color(1.0, 0.45, 0.15) * (aero * 0.35 * (0.8 + randf() * 0.4))
	overlay_mat.set_shader_parameter("glow", Vector3(glow.r, glow.g, glow.b))


func _screens(s: Dictionary) -> void:
	var now := Time.get_ticks_msec()
	if now - _main_at > 100:
		_main_at = now
		var list: Array = s.screens
		for i in 3:
			var sc: Array = list[i]
			cabin.screens[i].set_main(sc[0], sc[1], sc[2] if sc.size() > 2 else null)
	var aim: Variant = s.get("aim")
	var data := {"t": s.t, "ship": s.ship.r, "aim": aim, "fuel": s.fuel, "thrust": float(s.thrust), "warp": s.warp,
		"engine": "poltto" if float(s.thrust) > 0.05 else "valmius"}
	# Etukamera ja hologrammi näyttävät kohteen (ilman kohdetta Auringon).
	var name: String = aim if aim != null else "Aurinko"
	if _bodies.is_empty():
		for b: Dictionary in space.bodies:
			_bodies[b.name] = b
	var body: Dictionary = _bodies.get(name, {})
	var tex: Texture2D = null
	var color := Color(1.0, 0.85, 0.5)
	if not body.is_empty():
		tex = (body.mat as ShaderMaterial).get_shader_parameter("albedo_tex")
		color = body.color
	for m: Dictionary in cabin.monitors:
		var screen: CockpitScreen = m.screen
		screen.set_data(data)
		screen.set_globe(name, tex, color)
		screen.tick()
