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
	G.start_countdown()
	G.fake_real_ms += 12000.0
	s = CockpitState.make()
	check("laukaisussa tärinä ja työntö", float(s.shake) > 0.5 and float(s.thrust) > 0.5 and s.screens[0][0] == "NOUSU")
	G.fake_real_ms += 600000.0
	G.tick()
	s = CockpitState.make()
	check("kiertoradalla nokka Maahan", s.aim == "Maa" and s.screens[0][0] == "KIERTORATA")
	G.begin_search("Mars")
	G.finish_search()
	G.choose(G.options[0])
	G.jump_to_window()
	G.arm()
	s = CockpitState.make()
	check("lähtöpoltto päällä: nokka menosuuntaan", s.get("nose") != null and s.screens[0][0] == "LÄHTÖPOLTTO")
	G.burn_at = G.real_ms()
	s = CockpitState.make()
	check("polton hehku", float(s.thrust) > 0.9)
	G.aero_at = G.real_ms()
	s = CockpitState.make()
	check("ilmajarrutuksen plasma ja taivaan väri", float(s.aero) > 0.9 and s.sky_color != null)
	G.burn_at = -INF
	G.aero_at = -INF
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
	# Ohjaamonäkymä ja laatutasot
	var cv: CockpitView = get_parent().ui.cockpit_view
	check("ohjaamo luotu", cv != null and cv.cabin.screens.size() == 3 and cv.cabin.monitors.size() == 6 and cv.space.bodies.size() == 16)
	var facing := true
	for m: Dictionary in cv.cabin.monitors:
		var n: Node3D = m.node
		facing = facing and n.basis.z.dot(-n.position.normalized()) > 0.99
	check("näytöt katsovat silmään", facing)
	check("ikkunasta näkyy eteen ja sivulle, ei alas eikä taakse", Cabin.through_window(Vector3(0, 0.2, -1).normalized())
		and Cabin.through_window(Vector3(-1, 0.2, -0.5).normalized()) and not Cabin.through_window(Vector3(0, -0.5, -1).normalized())
		and not Cabin.through_window(Vector3(0, 0.1, 1).normalized()))
	cv.reset_view()
	cv.zoom_to(2)
	check("zoomaus keskinäyttöön kaventaa kuvakulmaa", cv.zoom_index == 2 and cv.fov_target < cv.base_fov * 0.5)
	cv.zoom_out()
	check("loitonnus palauttaa kuvakulman", cv.zoom_index == -1 and cv.fov_target == cv.base_fov)
	cv.zoom_by(0.5)
	cv.zoom_by(100.0)
	check("vapaa zoomaus rajoissa", cv.fov_target == cv.base_fov)
	cv.reset_view()
	cv.apply_quality(Settings.Quality.LOW)
	check("Matala: 2k-kartat, ei SSAO:ta", cv.space.max_texture == 2048 and not cv.env.ssao_enabled)
	if not Settings.is_compatibility():
		cv.apply_quality(Settings.Quality.ULTRA)
		check("Ultra: 8k, SSAO ja SSR", cv.space.max_texture == 8192 and cv.env.ssao_enabled and cv.env.ssr_enabled)
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
