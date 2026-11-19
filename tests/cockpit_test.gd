extends TestCase
## Ohjaamon logiikka ilman ikkunaa: ohjaamon tila pelin vaiheissa, pimennys, etäisyyksien puristus, koordinaatit,
## pintakarttojen tiedostot ja laatutasot.
##   godot --headless -- --cockpittest

const START := 1794643200000.0


func _ready() -> void:
	var G: Node = Game
	G.fake_real_ms = START
	G.new_game()
	var s := CockpitState.make()
	check("alustalla nokka ylös ja kolme näyttöä", s.get("nose") != null and s.screens.size() == 3 and s.screens[0][0] == "LAUKAISUALUSTA")
	# Laukaisutorni: alustalla aluksen vieressä, yläosa ohjaamon yläpuolella; katoaa nousussa.
	var tower := LaunchTower.new()
	add_child(tower)
	tower.update(s)
	var side := Vector2(LaunchTower.OFFSET_RIGHT, LaunchTower.OFFSET_ROOF).length()
	var tower_top := tower.position + tower.basis.y * LaunchTower.HEIGHT
	check("laukaisutorni alustan vieressä", tower.visible and absf(tower.position.length() - Vector2(side, 60.0).length()) < 1.0
		and tower_top.dot(tower.basis.y) > 50.0)
	G.start_countdown()
	G.fake_real_ms += 12000.0
	s = CockpitState.make()
	check("laukaisussa tärinä ja työntö", float(s.shake) > 0.5 and float(s.thrust) > 0.5 and s.screens[0][0] == "NOUSU")
	G.fake_real_ms += 600000.0
	G.tick()
	s = CockpitState.make()
	tower.update(s)
	check("laukaisutorni katoaa nousussa", not tower.visible)
	tower.queue_free()
	check("kiertoradalla nokka Maahan", s.aim == "Maa" and s.screens[0][0] == "KIERTORATA")
	G.begin_search("Mars")
	G.finish_search()
	G.choose(G.options[0])
	G.jump_to_window()
	G.arm()
	s = CockpitState.make()
	check("lähtöpoltto päällä: asento radan mukaan", s.get("burn_frame", false) and s.screens[0][0] == "LÄHTÖPOLTTO")
	G.burn_at = G.real_ms()
	s = CockpitState.make()
	check("polton hehku", float(s.thrust) > 0.9)
	G.launch()
	s = CockpitState.make()
	var hv := Flight.heading_velocity(G.state.flight, s.t)
	check("lennolla nokka menosuuntaan (kartan nuoli)", s.get("heading") != null and Flight.norm(Flight.sub(s.heading, hv)) < 1e-9
		and s.aim == "Mars")
	G.aero_at = G.real_ms()
	s = CockpitState.make()
	check("ilmajarrutuksen plasma ja taivaan väri", float(s.aero) > 0.9 and s.sky_color != null)
	G.burn_at = -INF
	G.aero_at = -INF
	# Näyttöjen tekstit mahtuvat leveyteen: ensin fonttia pienennetään, sitten ellipsi.
	var mono: Font = load(UiKit.FONT)
	var fit: Array = CockpitScreen.fit_text(mono, "lyhyt", 20, 300.0)
	check("lyhyt teksti ennallaan", fit[0] == "lyhyt" and fit[1] == 20)
	var long := "Ganymedes 1 234 567 890 km"
	fit = CockpitScreen.fit_text(mono, long, 26, 300.0)
	check("pitkä teksti pienemmällä fontilla", fit[0] == long and fit[1] < 26 and fit[1] >= 16
		and mono.get_string_size(fit[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fit[1]).x <= 300.0)
	fit = CockpitScreen.fit_text(mono, long + long + long, 26, 300.0)
	check("liian pitkä teksti ellipsillä", String(fit[0]).ends_with("…") and fit[1] == 16
		and mono.get_string_size(fit[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fit[1]).x <= 300.0)
	# Asento kappaleen lähellä (#20, #25, #26).
	var R := 6371.0
	var leo := CockpitState.body_frame(Flight.vec(R + 200.0, 0, 0), Flight.vec(0, 7.8, 0), R)
	var down := asin(-Flight.dot(leo.nose, Flight.vec(1, 0, 0)))
	check("matalalla radalla nokka menosuuntaan hieman alaspäin", leo.weight == 1.0 and Flight.dot(leo.nose, Flight.vec(0, 1, 0)) > 0.85
		and down > 15.0 * CockpitState.DEG and down < 30.0 * CockpitState.DEG and Flight.dot(leo.up, Flight.vec(1, 0, 0)) > 0.85)
	var far := CockpitState.body_frame(Flight.vec(R * 40.0, 0, 0), Flight.vec(-1.0, 0.1, 0), R)
	var to_c := Flight.vec(-1, 0, 0)
	var elev := asin(Flight.dot(to_c, far.up))
	check("kaukaa lähestyttäessä kappale ikkunan keskellä", far.weight < 0.05
		and absf(elev - CockpitState.AIM_RAISE) < 0.01 and Flight.dot(far.nose, to_c) > 0.95)
	var in_v := Flight.vec(-6.0, 1.0, 0)
	var appr := CockpitState.body_frame(Flight.vec(R * 4.0, 0, 0), in_v, R, true)
	var in_dir := Flight.scale(in_v, 1.0 / Flight.norm(in_v))
	check("lennolla lähestyttäessä nokka nopeuden suuntaan", Flight.dot(appr.nose, in_dir) > 0.9)
	var near_away := CockpitState.body_frame(Flight.vec(R * 1.3, -R * 0.2, 0), Flight.vec(8.0, 6.0, 0), R)
	var top := asin(Flight.dot(Flight.vec(-1, 0, 0), near_away.up)) # suunnilleen keskipisteen korkeus
	check("lähdön alussa horisontti näkyy ikkunassa", near_away.weight == 1.0 and top > -PI / 2.0 and top < 0.0)
	var away := CockpitState.body_frame(Flight.vec(R * 15.0, -R * 2.5, 0), Flight.vec(8.0, 2.0, 0), R)
	var vdir := Flight.scale(Flight.vec(8.0, 2.0, 0), 1.0 / Flight.norm(Flight.vec(8.0, 2.0, 0)))
	check("kaukana lähdöstä nokka menosuuntaan ja planeetta takana alla", Flight.dot(away.nose, vdir) > 0.9 and Flight.dot(away.up, Flight.vec(1, 0, 0)) < 0.5)
	# Pimennys
	check("ei peittoa", Space.covered(0.01, 0.01, 0.5) == 0.0)
	check("täysi peitto", Space.covered(0.01, 0.05, 0.0) == 1.0)
	check("osittainen peitto", absf(Space.covered(0.01, 0.005, 0.0) - 0.25) < 1e-9)
	var half := Space.covered(0.01, 0.01, 0.01)
	check("puolittainen peitto väliltä", half > 0.3 and half < 0.5)
	# Puristus: monotoninen, lähellä ennallaan, Neptunus kaukotason sisällä
	var ok := Space.compress(1000.0) == 1000.0
	var prev := 0.0
	for e in range(2, 14):
		var c := Space.compress(pow(10.0, e))
		ok = ok and c > prev
		prev = c
	check("puristus kasvaa ja lähellä ennallaan", ok)
	check("Neptunus kaukotason sisällä", Space.compress(4.6e12) < 1.2e5 * 0.95)
	check("koordinaatit: ekliptikan pohjoisnapa ylös", Space.to_scene(PackedFloat64Array([0, 0, 1])) == Vector3.UP)
	var eq := Space.scene_to_equatorial() * Space.to_scene(Space.equatorial(6.0, 30.0))
	check("päiväntasaajan koordinaatit edestakaisin", absf(rad_to_deg(asin(eq.z)) - 30.0) < 1e-3 and absf(fposmod(atan2(eq.y, eq.x), TAU) - PI / 2.0) < 1e-3)
	# Pintakartat
	var files := true
	for name: String in ["Merkurius", "Venus", "Maa", "Mars", "Jupiter", "Saturnus", "Uranus", "Neptunus", "Kuu", "Phobos", "Io", "Europa", "Ganymedes", "Enceladus", "Triton"]:
		files = files and BodyTextures.exists(BodyTextures.file_for(name, 2048))
		files = files and BodyTextures.exists(BodyTextures.file_for(name, BodyTextures.best_width(name, 8192)))
	check("pintakartat löytyvät", files)
	check("tarkkuuden yläraja", BodyTextures.best_width("Maa", 4096) == 4096 and BodyTextures.best_width("Uranus", 8192) == 2048)
	# Maan 16k-kartta (Ultra) on tuotu pakattuna tekstuurina, ei purettavana WebP:nä.
	var hi := BodyTextures.file_for("Maa", BodyTextures.best_width("Maa", 16384))
	check("Maan 16k-kartta pakattuna", hi.ends_with("-16k.jpg") and BodyTextures.imported(hi) and BodyTextures.exists(hi)
		and BodyTextures.best_width("Maa", 8192) == 8192)
	var tex16: Texture2D = load(hi)
	check("16k-kartta on näytönohjaimen pakkaama", tex16 != null and tex16.get_width() == 16384)
	var loader := BodyTextures.new()
	loader.threaded = false
	var clouds := loader.get_texture(BodyTextures.DIR + "maa-pilvet-8k.webp")
	check("pilvet ja yövalot 8k, yksikanavaisina", clouds != null and clouds.get_width() == 8192
		and clouds.get_image().get_format() == Image.FORMAT_L8 and BodyTextures.exists(BodyTextures.DIR + "maa-yo-8k.webp"))
	# Ohjaamonäkymä ja laatutasot
	var cv: CockpitView = get_parent().ui.cockpit_view
	check("ohjaamo luotu", cv != null and cv.cabin.screens.size() == 3 and cv.cabin.monitors.size() == 6 and cv.cabin.mini_screen != null and cv.space.bodies.size() == 16)
	var inside := true
	for m: Dictionary in cv.cabin.monitors:
		for c: Vector3 in m.corners:
			var p := Cabin.image_point(c)
			inside = inside and p.x > 0.0 and p.x < Cabin.IMAGE_SIZE.x and p.y > 0.0 and p.y < Cabin.IMAGE_SIZE.y and -c.z < 1.0
	check("näytöt ohjaamon kuvan päällä ja sen edessä", inside)
	var q: PackedVector3Array = Cabin.parallelogram(Cabin.MONITORS[0][1])
	var back := Cabin.image_point(q[2])
	check("näytön kulmat osuvat kuvan kulmiin", back.distance_to(Cabin.MONITORS[0][1][2]) < 0.01 and (q[0] + q[2] - q[1] - q[3]).length() < 1e-5)
	check("ikkunasta näkyy eteen, ei alas eikä taakse", Cabin.through_window(Vector3(0, 0.2, -1).normalized())
		and Cabin.through_window(Vector3(-0.5, 0.3, -1).normalized()) and not Cabin.through_window(Vector3(0, -0.5, -1).normalized())
		and not Cabin.through_window(Vector3(0, 0.1, 1).normalized()))
	check("panoraamat löytyvät", ResourceLoader.exists(Cabin.PANORAMA) and Cabin.panorama_path() == Cabin.PANORAMA_HIRES)
	cv.reset_view()
	check("katse ei laske ohjaamokuvan alareunan alle (kädet lähtevät näkymän alareunasta)",
		cv.min_pitch(0.0, cv.base_fov) > -0.1 and cv.min_pitch(0.0, 10.0) < cv.min_pitch(0.0, cv.base_fov)
		and cv.min_pitch(2.5, cv.base_fov) == -1.2)
	cv.zoom_to(2)
	check("zoomaus keskinäyttöön kaventaa kuvakulmaa", cv.zoom_index == 2 and cv.fov_target < cv.base_fov * 0.5)
	cv.zoom_out()
	check("loitonnus palauttaa kuvakulman", cv.zoom_index == -1 and cv.fov_target == cv.base_fov)
	# Manuaaliohjaus: tila päälle ja pois; poltto lennolla nokan suuntaan muuttaa rataa ja kuluttaa polttoainetta.
	cv.toggle_manual()
	check("manuaaliohjaus päälle", cv.manual and cv.manual_button.text == "Automaattiohjaus")
	cv.toggle_manual()
	check("manuaaliohjaus pois", not cv.manual and Game.manual_throttle == 0.0)
	cv.cabin.set_light("moottori", 2.0)
	cv.cabin.set_light("polttoaine", 0.0)
	var ind := cv.cabin.indicator_values()
	check("merkkivalot kuvan valoina", ind.size() == 6 and ind[0] == 1.0 and ind[5] == 0.0
		and ResourceLoader.exists("res://assets/cockpit/ohjaamo_valot.png"))
	var containers := 0
	for c in cv.get_children():
		if c is SubViewport:
			containers += 1
	check("ohjaamon säiliössä vain päänäkymä (muut SubViewportit piirtyisivät päälle)", containers == 1)
	cv.toggle_rear()
	check("kohdekamera takakameraksi", cv.is_rear() and cv.rear_button.text == "Kohdekamera"
		and cv.rear_view.world_3d == cv.viewport.find_world_3d())
	cv.toggle_rear()
	check("takakamera kohdekameraksi", not cv.is_rear() and cv.rear_view.render_target_update_mode == SubViewport.UPDATE_DISABLED)
	cv.zoom_by(0.5)
	cv.zoom_by(100.0)
	check("vapaa zoomaus rajoissa", cv.fov_target == cv.base_fov)
	cv.reset_view()
	cv.apply_quality(Settings.Quality.LOW)
	check("Matala: 2k-kartat, ei yksityiskohtia eikä SSAO:ta", cv.space.max_texture == 2048 and cv.space.surface_detail == 0.0 and not cv.env.ssao_enabled)
	if not Settings.is_compatibility():
		cv.apply_quality(Settings.Quality.ULTRA)
		check("Ultra: 16k, pinnan yksityiskohdat, SSAO ja SSR", cv.space.max_texture == 16384 and cv.space.surface_detail == 1.0 and cv.env.ssao_enabled and cv.env.ssr_enabled)
	cv.apply_quality(Settings.quality)
	# Läpinäkymättömät avaruusvarjostimet kirjoittavat VERTEXin, jotta syvyysesikierros käyttää niiden DEPTHiä
	# (muuten pinta piirtyy mustana laatutasoilla ilman SSAO:ta).
	var opaque_ok := true
	for shader in ["planet", "sun"]:
		var code := FileAccess.get_file_as_string("res://shaders/%s.gdshader" % shader)
		opaque_ok = opaque_ok and code.contains("DEPTH = space_depth") and code.contains("\tVERTEX = ")
	check("planeetta ja Aurinko syvyysesikierroksessa omalla varjostimella", opaque_ok)
	var detail := {}
	for b in cv.space.bodies:
		var ds: Variant = (b.mat as ShaderMaterial).get_shader_parameter("detail_strength")
		detail[b.name] = float(ds) if ds != null else 0.0
	check("kaasujättiläisillä lähikuvan pilvipyörteet, kiviplaneetoilla ei", detail.Jupiter > 0.0 and detail.Saturnus > 0.0
		and detail.Mars == 0.0 and detail.Maa == 0.0 and detail.Kuu == 0.0)
	check("aikakiihdytyksen tekstit", CockpitScreen.warp_label(1.0) == "1×" and CockpitScreen.warp_label(86400.0) == "1 vrk/s"
		and CockpitScreen.warp_label(31557600.0) == "1 v/s" and CockpitScreen.warp_label(50.0) == "50×")
	G.fake_real_ms = -1.0
	DirAccess.remove_absolute(G.TEST_SAVE_PATH)
	finish()
