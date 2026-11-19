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
var tower: LaunchTower
## Ulkokamera: toinen kamera samassa 3D-maailmassa, kuva kohdekameranäytölle. Tilat (cycle_camera, T):
## "kohde" kaukoputki aluksen paikalta kohteeseen (#39), "taka" takakamera ja "360" aluksen katolla kääntyvä
## kamera (#38), jonka voi avata koko näytölle (toggle_pan_full).
var rear_view: SubViewport
var rear_cam: Camera3D
var rear_button: Button
var cam_mode := "kohde"
const CAM_MODES := ["kohde", "taka", "360"]
const CAM_NAMES := {"kohde": "Kohdekamera", "taka": "Takakamera", "360": "360°-kamera"}
## 360°-kameran suuntima (rad, myötäpäivään keulasta), kallistus (rad) ja zoomauskerroin.
var pan_bearing := 0.0
var pan_tilt := -0.15
var pan_zoom := 1.0
var pan_full := false
var pan_full_button: Button
var _pan_layer: Control # koko näytön kuva ja tähtäin
var _pan_rect: TextureRect
var _pan_hud: Control
var _pan_drag := false
const PAN_FOV := 64.0
## Kohdekamera: kohteen säde osuutena kuvan korkeudesta, suurin pystykuvakulma ja musta tausta (kaukoputkessa
## Linnunrata olisi suurennettuna pelkkää sumua).
const TELE_RADIUS := 0.34
const TELE_MAX_FOV := 62.0
var tele_env: Environment
const PAN_MOUNT := Vector3(0.0, 0.9, 0.2) # aluksen katolla ohjaamon takana
var _throttle := 0.0 # tehovivun asento 0–1 (pehmennetty)
## Manuaaliohjaus (#30): aluksen asento näppäimillä 360°, kaasu ja jarrutus lennolla.
var manual := false
var manual_throttle := 0.0
var manual_button: Button
var _manual_hud: PanelContainer
var _manual_label: Label
var _braking := false
const MANUAL_RATE := 0.6 # rad/s
var _steer := Vector2.ZERO # ohjainsauvan poikkeama (px) aluksen kääntymisen mukaan
const REAR_TILT := 0.87 # 50°
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
	tower = LaunchTower.new()
	world.add_child(tower)
	_build_lights()
	_build_particles()
	_build_flare()
	_build_overlay()
	_build_rear()
	_build_pan_layer()
	_build_tools()
	set_cam_mode("kohde")
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
	env.glow_bloom = 0.015
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
	shine.light_cull_mask = ~LaunchTower.LAYER
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
	flare.layers = Cabin.INTERIOR_LAYER
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
	overlay_mat.set_shader_parameter("panorama", load(Cabin.panorama_path()))
	overlay_mat.set_shader_parameter("lights_map", load("res://assets/cockpit/ohjaamo_valot.png"))
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
	manual_button = UiKit.button("Manuaaliohjaus", toggle_manual)
	manual_button.tooltip_text = "Ohjaa alusta itse (M): W/S nokka, A/D kääntö, Q/E kallistus, Shift/Ctrl kaasu, X nollaa, B jarruta"
	tools.add_child(manual_button)
	_build_manual_hud()
	rear_button = UiKit.button("Takakamera", cycle_camera)
	rear_button.tooltip_text = "Vaihda kameranäyttö: kohdekamera, takakamera ja 360°-kamera (T)"
	tools.add_child(rear_button)
	pan_full_button = UiKit.button("Koko näyttö", toggle_pan_full)
	pan_full_button.tooltip_text = "360°-kamera koko näytölle ja takaisin ohjaamoon (F, Esc): raahaa kääntääksesi, rulla zoomaa"
	pan_full_button.visible = false
	tools.add_child(pan_full_button)


func _build_manual_hud() -> void:
	_manual_hud = PanelContainer.new()
	_manual_hud.theme_type_variation = "Overlay"
	_manual_hud.visible = false
	_manual_hud.mouse_filter = Control.MOUSE_FILTER_PASS
	_manual_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_manual_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_manual_hud.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_manual_hud.position.y -= 56.0
	add_child(_manual_hud)
	var v := UiKit.vbox(6)
	_manual_hud.add_child(v)
	_manual_label = UiKit.label("", "", false)
	v.add_child(_manual_label)
	var row := UiKit.hbox(6)
	row.add_child(UiKit.button("Kaasu −", func() -> void: manual_throttle = maxf(0.0, manual_throttle - 0.25)))
	row.add_child(UiKit.button("Kaasu +", func() -> void: manual_throttle = minf(1.0, manual_throttle + 0.25)))
	row.add_child(UiKit.button("Nollaa", func() -> void: manual_throttle = 0.0))
	var brake := UiKit.button("Jarruta (pidä)", func() -> void: pass)
	brake.button_down.connect(func() -> void: _braking = true)
	brake.button_up.connect(func() -> void: _braking = false)
	row.add_child(brake)
	v.add_child(row)
	v.add_child(UiKit.label("W/S nokka · A/D kääntö · Q/E kallistus · Shift/Ctrl kaasu · X nollaa · B jarruta · M lopeta", "MutedLabel", false))


## Manuaaliohjaus päälle ja pois: pois kytkettäessä kaasu nollataan ja asento palaa automaattiseksi.
func toggle_manual() -> void:
	manual = not manual
	manual_throttle = 0.0
	_braking = false
	Game.manual_thrust(PackedFloat64Array([1.0, 0.0, 0.0]), 0.0, 0.0)
	manual_button.text = "Automaattiohjaus" if manual else "Manuaaliohjaus"
	_manual_hud.visible = manual


# Manuaaliohjaus: näppäimet kääntävät alusta sen omien akselien ympäri, kaasu polttaa nokan suuntaan ja jarrutus
# menosuuntaa vastaan (Game.manual_thrust). Kaasu ja jarrutus vain lennolla.
func _manual_step(s: Dictionary, delta: float) -> void:
	var keys := is_visible_in_tree() and not (get_viewport().gui_get_focus_owner() is LineEdit)
	var axis := func(neg: Key, pos: Key) -> float:
		return (1.0 if keys and Input.is_key_pressed(pos) else 0.0) - (1.0 if keys and Input.is_key_pressed(neg) else 0.0)
	var rate := Vector3(axis.call(KEY_S, KEY_W), axis.call(KEY_D, KEY_A), axis.call(KEY_E, KEY_Q)) * MANUAL_RATE
	if rate != Vector3.ZERO:
		ship.basis = (ship.basis * Basis.from_euler(rate * delta)).orthonormalized()
	if keys and Input.is_key_pressed(KEY_SHIFT):
		manual_throttle = minf(1.0, manual_throttle + delta * 0.6)
	if keys and Input.is_key_pressed(KEY_CTRL):
		manual_throttle = maxf(0.0, manual_throttle - delta * 0.6)
	if keys and Input.is_key_pressed(KEY_X):
		manual_throttle = 0.0
	var braking := _braking or (keys and Input.is_key_pressed(KEY_B))
	var dir: PackedFloat64Array
	var power := manual_throttle
	if braking and s.get("heading") != null:
		var h: PackedFloat64Array = s.heading
		dir = Flight.scale(h, -1.0 / maxf(Flight.norm(h), 1e-9))
		power = 1.0
	else:
		var n := -ship.basis.z
		dir = PackedFloat64Array([n.x, -n.z, n.y]) # scene → ekliptika (Space.to_scene käänteisenä)
	var ok := Game.manual_thrust(dir, power, delta)
	var state := "POLTTO" if ok else ("ei polttoa: vain lennolla" if power > 0.0 and not Game.can_manual_burn() else "valmius")
	_manual_label.text = "MANUAALIOHJAUS   kaasu %d %%%s   %s   polttoaine %s" % [roundi(manual_throttle * 100.0),
		"  · JARRUTUS" if braking else "", state, Fmt.dv(float(Game.state.fuel))]


func _build_rear() -> void:
	rear_view = SubViewport.new()
	rear_view.size = Vector2i(768, 432)
	rear_view.world_3d = viewport.find_world_3d()
	rear_view.audio_listener_enable_3d = false
	rear_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	# Ei tämän SubViewportContainerin lapseksi: säiliö piirtäisi kaikki SubViewport-lapsensa näkymän päälle.
	viewport.add_child(rear_view)
	rear_cam = Camera3D.new()
	rear_cam.near = camera.near
	rear_cam.far = camera.far
	rear_cam.fov = 62.0
	# Kiinteä valotus: kuva päivitetään harvoin, joten automaattinen valotus ei ehtisi sopeutua.
	var attr := CameraAttributesPractical.new()
	attr.auto_exposure_enabled = false
	attr.exposure_multiplier = 0.8
	rear_cam.attributes = attr
	# Ohjaamon sisäosat (lasi, plasma, häikäisy) eivät näy ulkokameraan.
	rear_cam.cull_mask = 0xFFFFF & ~Cabin.INTERIOR_LAYER
	rear_view.add_child(rear_cam)
	tele_env = env.duplicate()
	tele_env.background_mode = Environment.BG_COLOR
	tele_env.background_color = Color.BLACK


## Koko näytön 360°-kamera: kuva ja tähtäin ohjaamonäkymän päällä (työkalurivin alla).
func _build_pan_layer() -> void:
	_pan_layer = Control.new()
	_pan_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pan_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pan_layer.visible = false
	add_child(_pan_layer)
	_pan_rect = TextureRect.new()
	_pan_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pan_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pan_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pan_rect.stretch_mode = TextureRect.STRETCH_SCALE
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/rear_camera.gdshader")
	_pan_rect.material = mat
	_pan_layer.add_child(_pan_rect)
	_pan_hud = Control.new()
	_pan_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pan_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pan_hud.draw.connect(_draw_pan_full)
	_pan_layer.add_child(_pan_hud)


func _draw_pan_full() -> void:
	var sz := _pan_hud.size
	var s := clampf(minf(sz.x / 1024.0, sz.y / 640.0), 0.6, 1.4)
	# Yläpalkki näkymävalitsimen (Ohjaamo/Kartta) alle.
	CockpitScreen.draw_pan_hud(_pan_hud, load(UiKit.FONT_BOLD), load(UiKit.FONT), sz, pan_vector(), s, 46.0)
	var hint := "Raahaa kääntääksesi · nuolinäppäimet · rulla zoomaa · Esc ohjaamoon"
	var fs := roundi(15 * s)
	var mono: Font = load(UiKit.FONT)
	var w := mono.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w < sz.x - 40.0:
		_pan_hud.draw_rect(Rect2((sz.x - w) / 2.0 - 14.0, sz.y - 74.0 - fs - 6.0, w + 28.0, fs + 18.0), Color(0.01, 0.04, 0.09, 0.5))
		_pan_hud.draw_string(mono, Vector2((sz.x - w) / 2.0, sz.y - 74.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(CockpitScreen.MUTED, 0.9))


## 360°-kameran suunta näytöille: (suuntima, kallistus, zoom).
func pan_vector() -> Vector3:
	return Vector3(pan_bearing, pan_tilt, pan_zoom)


## Kääntää 360°-kameraa (rad); suuntima kiertää täyden ympyrän, kallistus ±85°.
func pan_by(d_bearing: float, d_tilt: float) -> void:
	pan_bearing = fposmod(pan_bearing + d_bearing, TAU)
	pan_tilt = clampf(pan_tilt + d_tilt, -deg_to_rad(85.0), deg_to_rad(85.0))


func _camera_screen() -> CockpitScreen:
	for m: Dictionary in cabin.monitors:
		if (m.screen as CockpitScreen).kind == "camera":
			return m.screen
	return null


func is_rear() -> bool:
	return cam_mode == "taka"


## Vaihtaa kohdekameranäytön takakameraksi ja takaisin.
func toggle_rear() -> void:
	set_cam_mode("kohde" if cam_mode == "taka" else "taka")


## Seuraava kameratila (painike ja T-näppäin): kohde → taka → 360° → kohde.
func cycle_camera() -> void:
	set_cam_mode(CAM_MODES[(CAM_MODES.find(cam_mode) + 1) % CAM_MODES.size()])


func set_cam_mode(mode: String) -> void:
	var cs := _camera_screen()
	if cs == null or not CAM_MODES.has(mode):
		return
	cam_mode = mode
	if mode != "360" and pan_full:
		toggle_pan_full()
	# Kuvasuhde näytön mukaan, jotta kuvaa ei rajata (kohdekameran mittakaava ja paikka täsmäävät).
	if not pan_full:
		rear_view.size = _feed_size(cs)
	cs.set_feed(rear_view.get_texture(), mode)
	var tele := mode == "kohde"
	rear_cam.projection = Camera3D.PROJECTION_FRUSTUM if tele else Camera3D.PROJECTION_PERSPECTIVE
	rear_cam.near = camera.near
	rear_cam.fov = PAN_FOV if mode == "360" else 62.0
	rear_cam.environment = tele_env if tele else null
	rear_cam.cull_mask = 0xFFFFF & ~Cabin.INTERIOR_LAYER & ~(Space.DOT_LAYER if tele else 0)
	if not tele:
		space.focus = ""
	rear_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	if rear_button != null:
		rear_button.text = CAM_NAMES[CAM_MODES[(CAM_MODES.find(mode) + 1) % CAM_MODES.size()]]
		pan_full_button.visible = mode == "360"


## 360°-kamera koko näytölle ja takaisin: ohjaamonäkymää ei piirretä koko näytön tilassa.
func toggle_pan_full() -> void:
	if not pan_full and cam_mode != "360":
		set_cam_mode("360")
	pan_full = not pan_full
	_pan_layer.visible = pan_full
	_pan_drag = false
	if pan_full:
		zoom_out()
		_pan_rect.texture = rear_view.get_texture()
		_resize_pan_view()
	else:
		rear_view.size = _feed_size(_camera_screen())
		rear_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED if pan_full else SubViewport.UPDATE_ALWAYS
	pan_full_button.text = "Ohjaamoon" if pan_full else "Koko näyttö"


## Ulkokameran kuvan koko näytöllä: 768 px leveä, kameranäytön kuvasuhteessa.
func _feed_size(cs: CockpitScreen) -> Vector2i:
	if cs == null or cs.view_size.x <= 0.0:
		return Vector2i(768, 432)
	return Vector2i(768, roundi(768.0 * cs.view_size.y / cs.view_size.x))


func _resize_pan_view() -> void:
	if not pan_full:
		return
	var px := Vector2i(maxi(64, roundi(size.x)), maxi(64, roundi(size.y)))
	rear_view.size = px
	rear_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	(_pan_rect.material as ShaderMaterial).set_shader_parameter("aspect", float(px.x) / float(px.y))


# Takakamera aluksen perässä katsoo taaksepäin ja 50° alas (lattian suuntaan), jotta kiertoradalla ja lähdössä
# planeetta näkyy; kuva päivitetään samaan tahtiin kuin näyttö.
func _update_rear(screen_drawn: bool) -> void:
	if cam_mode == "360":
		_update_pan(screen_drawn)
		return
	if cam_mode == "kohde":
		_update_tele(screen_drawn)
		return
	if not is_rear():
		return
	var rear := ship.global_transform * Transform3D(Basis(Vector3.UP, PI) * Basis(Vector3.RIGHT, -REAR_TILT), Vector3(0.0, -0.3, 1.2))
	# Kääntyvä kamera: jos lähin kappale on takana mutta kuvan ulkopuolella (esim. poistuva planeetta lähdön jälkeen),
	# kamera kääntyy niin, että kappaleen lähin reuna tulee kuvaan.
	if not space.nearest.is_empty():
		var to_body := (space.nearest.root as Node3D).position.normalized()
		var view := -rear.basis.z
		var ang := view.angle_to(to_body)
		var rho := asin(clampf(space.nearest_size, 0.0, 1.0))
		var turn := ang - rho - deg_to_rad(12.0)
		if turn > 0.0 and ang < deg_to_rad(110.0):
			var axis := view.cross(to_body)
			if axis.length() > 1e-6:
				rear.basis = Basis(axis.normalized(), turn) * rear.basis
	rear_cam.global_transform = rear
	if screen_drawn:
		rear_view.render_target_update_mode = SubViewport.UPDATE_ONCE


## 360°-kamera aluksen katolla: suuntima ja kallistus aluksen akseleiden suhteen (nuolinäppäimet kääntävät).
func _update_pan(screen_drawn: bool) -> void:
	var keys := is_visible_in_tree() and not (get_viewport().gui_get_focus_owner() is LineEdit)
	if keys:
		var dt := get_process_delta_time() * 1.2 / pan_zoom
		var h := (1.0 if Input.is_key_pressed(KEY_RIGHT) else 0.0) - (1.0 if Input.is_key_pressed(KEY_LEFT) else 0.0)
		var v := (1.0 if Input.is_key_pressed(KEY_UP) else 0.0) - (1.0 if Input.is_key_pressed(KEY_DOWN) else 0.0)
		if h != 0.0 or v != 0.0:
			pan_by(h * dt, v * dt)
	rear_cam.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(PAN_FOV) / 2.0) / pan_zoom))
	var b := Basis.from_euler(Vector3(pan_tilt, -pan_bearing, 0.0), EULER_ORDER_YXZ)
	rear_cam.global_transform = Transform3D(_pan_frame() * b, ship.global_transform * PAN_MOUNT)
	var cs := _camera_screen()
	if cs != null:
		cs.pan = pan_vector()
	if pan_full:
		_pan_hud.queue_redraw()
	elif screen_drawn:
		rear_view.render_target_update_mode = SubViewport.UPDATE_ONCE


## Kohdekamera (#39): kaukoputki aluksen paikalla osoittaa kohteeseen (ilman kohdetta Aurinkoon), joten kuvassa on
## sama puoli, vaihe, ilmakehä ja renkaat kuin ikkunasta katsottuna. Kuvakulma valitaan niin, että kohteen säde on
## TELE_RADIUS kuvan korkeudesta (lähellä enintään TELE_MAX_FOV, jolloin kuvassa on pinta aluksen alla). Kohde on
## näytön oikealla puolella tekstipaneelin vieressä: kapea näkökenttä ja sivusiirto tehdään frustum-projektiolla,
## jonka pieni koko ei rajoitu perspektiivikameran 1°:n vähimmäiskulmaan. Kuvan yläsuunta on aluksen katto.
func _update_tele(screen_drawn: bool) -> void:
	var aim: Variant = _state.get("aim")
	var name: String = aim if aim != null else "Aurinko"
	var pos: Vector3
	var radius: float
	if name == "Aurinko":
		pos = space.sun_root.position
		radius = space.sun_mesh.scale.x
	else:
		var body: Dictionary = _bodies.get(name, {})
		if body.is_empty():
			return
		pos = (body.root as Node3D).position
		radius = (body.tilt as Node3D).scale.x
	var origin := ship.global_position
	var rel := pos - origin
	var dist := maxf(rel.length(), 1e-6)
	var dir := rel / dist
	var rho := asin(clampf(radius / dist, 0.0, 1.0))
	# Renkaat (Saturnus) mahtuvat kuvaan, kun kappale on pienempi.
	var share := TELE_RADIUS * (0.45 if name == "Saturnus" else 1.0)
	var t_max := tan(deg_to_rad(TELE_MAX_FOV) / 2.0)
	var cs := _camera_screen()
	if cs == null:
		return
	var anchor := cs.tele_anchor()
	# Säde on share sisältöalueen korkeudesta eli 2 · share · anchor.z puolikorkeudesta.
	var t_half := minf(tan(rho) / (2.0 * share * anchor.z), t_max)
	# Kuvan yläsuunta on kohteen pohjoisnapa (Auringolla ekliptikan pohjoinen), kuten planeettakuvissa.
	var north := Vector3.UP if name == "Aurinko" else (_bodies[name].tilt as Node3D).global_transform.basis.y.normalized()
	if absf(dir.dot(north)) > 0.999:
		north = ship.global_transform.basis.y.normalized()
	space.focus = name
	# Lähellä kohde ei mahtuisi kuvaan: näytetään koko pallo aluksen kohta keskellä (sama puoli kuin ikkunasta).
	if name != "Aurinko" and tan(rho) / (2.0 * share * anchor.z) > t_max:
		space.focus_px = Space.HIRES_PX - 1.0
		_tele_close(cs, name, dir, north, share)
		return
	cs.set_close(false)
	# Aurinkosuodin: Auringon pinta (reunatummennus) näkyy ilman ylivalotusta.
	tele_env.tonemap_exposure = 0.012 if name == "Aurinko" else 1.0
	tele_env.glow_enabled = name != "Aurinko"
	(cs.rear.material as ShaderMaterial).set_shader_parameter("solar", 1.0 if name == "Aurinko" else 0.0)
	rear_cam.global_transform = Transform3D(Basis.looking_at(dir, north), origin)
	var near := clampf(0.5 * (dist - radius), 0.02, 50.0)
	var height := 2.0 * near * t_half
	var aspect := float(rear_view.size.x) / float(maxi(rear_view.size.y, 1))
	# Optinen akseli (kohteen keskipiste) näytön kohtaan TELE_X: siirto on lähitason yksiköissä.
	rear_cam.set_frustum(height, Vector2(-anchor.x * height / 2.0 * aspect, -anchor.y * height / 2.0), near, camera.far)
	space.focus_px = minf(rho / t_half * rear_view.size.y, Space.HIRES_PX - 1.0)
	cs.tele = Vector2(tan(deg_to_rad(base_fov) / 2.0) / t_half, share)
	if screen_drawn:
		rear_view.render_target_update_mode = SubViewport.UPDATE_ONCE


## Kohdekameran lähinäkymä: kohde suunnattuna pallona näytöllä (globe.gdshader), keskellä kohta, jonka yllä alus on,
## pohjoinen ylhäällä, Auringon valo oikeasta suunnasta, Maalla pilvet ja yövalot.
func _tele_close(cs: CockpitScreen, name: String, dir: Vector3, north: Vector3, share: float) -> void:
	var b: Dictionary = _bodies[name]
	var z := -dir # kuvasta katsojaan (alukseen)
	var y := (north - z * north.dot(z)).normalized()
	var view := Basis(y.cross(z), y, z)
	var mesh_inv := (b.mesh as MeshInstance3D).global_transform.basis.orthonormalized().inverse()
	var to_body := mesh_inv * view
	var sun_local: Vector3 = (b.mat as ShaderMaterial).get_shader_parameter("sun_local")
	var params := {"view_to_body": to_body, "light_dir": to_body.transposed() * sun_local,
		"has_clouds": b.has("cloud_spin") and b.clouds != null, "has_night": b.has("night_path"),
		"atmo": float(Space.ATMOS[name][3]) if Space.ATMOS.has(name) else 0.0,
		"atmo_color": Space.ATMOS[name][0] if Space.ATMOS.has(name) else Color(0.35, 0.6, 1.0)}
	if params.has_clouds:
		params.view_to_cloud = (b.cloud_spin as Node3D).global_transform.basis.orthonormalized().inverse() * view
		params.cloud_tex = (b.clouds as ShaderMaterial).get_shader_parameter("cloud_tex")
	if params.has_night:
		params.night_tex = (b.mat as ShaderMaterial).get_shader_parameter("night_tex")
	cs.set_close(true, params)
	cs.tele = Vector2(0.0, share)
	var ship_r: PackedFloat64Array = _state.ship.r
	var alt := Flight.norm(Flight.sub(ship_r, Flight.body_state(name, float(_state.t)).r)) - float(Flight.orbit_of(name).radiusKm)
	cs.tele_label = "ALUKSEN KOHTA · KORKEUS %s" % Fmt.km(maxf(alt, 0.0))


## 360°-kameran perusasento: kaukana aluksen akselit, lähellä kappaletta (kulmasäde yli muutaman asteen) vakautettu
## paikalliseen pystysuuntaan kuin gimbaali: horisontti pysyy vaakasuorassa (myös pystyssä alustalla ja kallistettaessa),
## ja suuntima 0° on keulan suunta vaakatasossa (pystyssä katon suunta).
func _pan_frame() -> Basis:
	var sb := ship.global_transform.basis.orthonormalized()
	if space.nearest.is_empty():
		return sb
	var w := smoothstep(0.02, 0.08, space.nearest_size)
	if w <= 0.0:
		return sb
	var up := -(space.nearest.root as Node3D).position.normalized()
	var fwd := -sb.z - up * (-sb.z).dot(up)
	if fwd.length() < 0.3:
		fwd = sb.y - up * sb.y.dot(up)
	fwd = fwd.normalized()
	var level := Basis(up.cross(-fwd).normalized(), up, -fwd)
	return Basis(sb.get_rotation_quaternion().slerp(level.get_rotation_quaternion(), w))


## Alin sallittu katseen pystykulma (#19): näkymän alareuna ei saa mennä ohjaamokuvan alareunan alle, jotta pilotin
## kädet lähtevät aina näkymän alareunasta (kuvan alla panoraamassa olisi tyhjä istuin ja keskikonsoli). Alareunan
## säteitä verrataan kuvan alareunaan (pieni marginaali tärinää varten); sivuilla, missä kuvaa ei ole, raja ei vaikuta.
func min_pitch(p_yaw: float, fov_deg: float) -> float:
	var tan_v := tan(deg_to_rad(fov_deg) / 2.0)
	var tan_h := tan_v * size.x / maxf(1.0, size.y)
	var half_w := atan(Cabin.IMAGE_SIZE.x / 2.0 / Cabin.FOCAL) # kuvan vaakapuolikas (rad)
	var bottom := (Cabin.IMAGE_SIZE.y - 8.0 - Cabin.CENTER.y) / Cabin.FOCAL # alareuna kuvatasolla (marginaali 8 px)
	var need := -1.2
	# Näkymän alareunan sarakkeet: sarakkeen suunta ax ja korkeus ey kameran koordinaateissa; kuvan alareunan
	# korkeus suunnassa az on atan(−bottom·cos az) (kuvataso z = −1).
	for i in 9:
		var x := -1.0 + i / 4.0
		var ax := atan(x * tan_h)
		var ey := -atan(tan_v * cos(ax))
		var az := p_yaw - ax
		if absf(az) <= half_w:
			need = maxf(need, atan(-bottom * cos(az)) - ey)
	return clampf(need, -1.2, 1.05)


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


## Kääntääkö raahaus kohdassa p 360°-kameraa (koko näyttö tai kameranäyttö 360°-tilassa).
func _on_pan_screen(p: Vector2) -> bool:
	if pan_full:
		return true
	if cam_mode != "360":
		return false
	var i := monitor_at(p)
	return i >= 0 and (cabin.monitors[i].screen as CockpitScreen).kind == "camera"


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
				_pan_drag = _on_pan_screen(mb.position)
			elif _press_moved < 8.0 and not pan_full:
				_click(mb.position)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if pan_full:
				pan_zoom = clampf(pan_zoom / 0.85, 1.0, 8.0)
			else:
				zoom_by(0.85)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if pan_full:
				pan_zoom = clampf(pan_zoom * 0.85, 1.0, 8.0)
			else:
				zoom_by(1.0 / 0.85)
			accept_event()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.index == 0:
			_dragging = st.pressed
			if st.pressed:
				_press_moved = 0.0
				_pan_drag = _on_pan_screen(st.position)
			elif _press_moved < 12.0 and not pan_full:
				_click(st.position)
		accept_event()
	elif event is InputEventMagnifyGesture:
		if pan_full:
			pan_zoom = clampf(pan_zoom * (event as InputEventMagnifyGesture).factor, 1.0, 8.0)
		else:
			zoom_by(1.0 / maxf(0.01, (event as InputEventMagnifyGesture).factor))
		accept_event()
	elif (event is InputEventMouseMotion and _dragging) or event is InputEventScreenDrag:
		var rel: Vector2 = event.relative
		_press_moved += rel.length()
		if _pan_drag:
			# 360°-kamera kääntyy raahauksen mukana: koko näytöllä kuvakulman mukaan, ohjaamon näytöllä nopeammin.
			var kp := (deg_to_rad(PAN_FOV) / pan_zoom / maxf(size.y, 1.0)) if pan_full else 0.012 * camera.fov / base_fov
			pan_by(rel.x * kp, -rel.y * kp)
		elif _press_moved >= 8.0:
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
	if is_visible_in_tree() and event.is_action_pressed("ui_cancel") and pan_full:
		toggle_pan_full()
		get_viewport().set_input_as_handled()
	elif is_visible_in_tree() and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_F:
		toggle_pan_full()
		get_viewport().set_input_as_handled()
	elif is_visible_in_tree() and event.is_action_pressed("ui_cancel") and fov_target < base_fov - 0.5:
		zoom_out()
		get_viewport().set_input_as_handled()
	elif is_visible_in_tree() and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_T:
		cycle_camera()
		get_viewport().set_input_as_handled()
	elif is_visible_in_tree() and event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo \
			and (event as InputEventKey).keycode == KEY_M and not Game.state.pad:
		toggle_manual()
		get_viewport().set_input_as_handled()


# Pystykulma niin, että ohjaamon kuva täyttää näkymän (kapeassa ikkunassa katsetta käännetään sivuille).
func _fit_fov() -> void:
	_resize_pan_view()
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
	space.max_texture = [2048, 4096, 8192, 16384][level]
	space.atmo_samples = [4, 6, 10, 16][level]
	space.surface_detail = [0.0, 0.7, 1.0, 1.0][level]
	space.shadow_steps = [6, 10, 16, 24][level]


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
	tower.update(s)
	_zoom_step(delta)
	# Katse ja tärinä: nopeaa värinää, hitaampaa heiluntaa ja pientä kiertoa (zoomattuna vähemmän).
	var rumble := clampf(float(s.shake), 0.0, 1.0) * camera.fov / base_fov
	var tt := Time.get_ticks_msec() / 1000.0
	var jitter := func(k: float) -> float: return (randf() - 0.5) * k * rumble
	pitch = maxf(pitch, min_pitch(yaw, camera.fov))
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


# Aluksen asento: laukaisussa annettu suunta (nose, up); muuten nokka kohteeseen (aim) niin, että kohde näkyy ikkunan
# keskellä, ja kappaleen lähellä radan mukaan (CockpitState.body_frame). Käännös pehmeästi.
func _attitude(s: Dictionary, delta: float) -> void:
	if manual and not Game.state.pad:
		var before_m := ship.basis
		_manual_step(s, delta)
		var rot_m := (before_m.inverse() * ship.basis).get_euler()
		_steer = _steer.lerp((Vector2(-rot_m.y, -rot_m.x) / maxf(delta, 1e-3) * 40.0).limit_length(7.0), minf(1.0, delta * 5.0))
		return
	var want: Basis = ship.basis
	if s.get("nose") != null:
		var nose := _ecl_to_scene(s.nose).normalized()
		var up := _ecl_to_scene(s.up if s.get("up") != null else PackedFloat64Array([0, 0, 1])).normalized()
		want = Basis.looking_at(nose, up)
	else:
		if s.get("heading") != null:
			# Menosuunta (kartan nuoli) ikkunan keskelle.
			var dir_h := Space.to_scene(s.heading).normalized()
			want = Basis.looking_at(dir_h, Vector3.UP if absf(dir_h.y) < 0.99 else Vector3.BACK) * Basis(Vector3.RIGHT, -CockpitState.AIM_RAISE)
		elif s.get("aim") != null:
			var aim_km: PackedFloat64Array = Flight.body_state(s.aim, s.t).r
			var dir := Space.to_scene(Flight.sub(aim_km, s.ship.r)).normalized()
			want = Basis.looking_at(dir, Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK) * Basis(Vector3.RIGHT, -CockpitState.AIM_RAISE)
		var fr := _body_frame(s)
		if not fr.is_empty():
			var w: float = 1.0 if s.get("burn_frame", false) else float(fr.weight)
			if w > 0.0:
				var fb := Basis.looking_at(_ecl_to_scene(fr.nose).normalized(), _ecl_to_scene(fr.up).normalized())
				want = Basis(want.get_rotation_quaternion().slerp(fb.get_rotation_quaternion(), w))
	if not _attitude_ready:
		ship.basis = want
		_attitude_ready = true
	else:
		var before := ship.basis
		var q := ship.basis.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), minf(1.0, delta / 1.5))
		ship.basis = Basis(q)
		# Ohjainsauva kallistuu kääntymisen suuntaan: kiertymä aluksen koordinaateissa (y = sivuttain, x = nokka ylös/alas).
		var rot := (before.inverse() * ship.basis).get_euler()
		var rate := Vector2(-rot.y, -rot.x) / maxf(delta, 1e-3)
		_steer = _steer.lerp((rate * 40.0).limit_length(7.0), minf(1.0, delta * 5.0))


## Asento lähimmän (suurimman näköisen) kappaleen suhteen, tai {} jos nopeutta ei tunneta.
func _body_frame(s: Dictionary) -> Dictionary:
	if space.nearest.is_empty() or not (s.ship as Dictionary).has("v"):
		return {}
	var name: String = space.nearest.name
	var b := Flight.body_state(name, s.t)
	return CockpitState.body_frame(Flight.sub(s.ship.r, b.r), Flight.sub(s.ship.v, b.v), float(space.nearest.radius_m) / 1000.0,
		s.get("heading") != null)


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
	# Kirkas päivätaivas ylittää hehkun kynnyksen: hehku valuisi ohuiden rakenteiden (laukaisutorni) päälle harsona.
	env.glow_hdr_threshold = lerpf(1.5, 6.0, clampf(sky * 2.0, 0.0, 1.0))
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
	# Laukaisualustalla ja nousussa ohjaa kantoraketti.
	manual_button.disabled = Game.state.pad
	if manual and Game.state.pad:
		toggle_manual()
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
	# Polttoaineen varoitusvalo vilkkuu, kun polttoainetta on alle 20 %.
	var low := 1.0 if float(s.fuel) <= 0.2 else 0.0
	var blink := 1.0 if fmod(Time.get_ticks_msec() / 1000.0, 0.8) < 0.4 else 0.0
	cabin.set_light("polttoaine", low * blink)
	cabin.set_light("ilmakeha", maxf(aero, float(s.get("sky", 0.0)) * 0.6 if Game.state.pad else aero))
	var f: Variant = Game.state.flight
	cabin.set_light("vaikutuspiiri", 1.0 if f != null and float(s.t) >= float(f.soi) else 0.1)
	cabin.set_light("suunta", 1.0 if s.get("aim") != null or s.get("nose") != null else 0.1)
	overlay_mat.set_shader_parameter("indicators", cabin.indicator_values())
	# Kädet: tehovipu eteen työnnön mukaan, ohjainsauva värähtelee tärinässä ja liikkuu aluksen kääntyessä.
	_throttle = lerpf(_throttle, thrust, minf(1.0, get_process_delta_time() * 4.0))
	overlay_mat.set_shader_parameter("throttle_px", Vector2(5.0, -14.0) * _throttle)
	var shake := clampf(float(s.shake), 0.0, 1.0)
	var jitter := Vector2(randf() - 0.5, randf() - 0.5) * 3.0 * shake
	overlay_mat.set_shader_parameter("stick_px", _steer + jitter)
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
	# Kohdekamera ja hologrammi näyttävät kohteen (ilman kohdetta Auringon).
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
		var drawn := screen.tick()
		if screen.kind == "camera":
			_update_rear(drawn)
