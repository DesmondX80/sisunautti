extends TestCase
## Kuvakaappaukset ohjaamosta (vaatii ikkunan, ei mukana tools/run_tests.sh:ssa):
##   godot -- --cockpitshotstest=/polku/kuviin [--size=1600x900] [--quality=2] [--only=nimi] [--state=tallennus.json]
## --state: kuva annetusta tallennuksesta (pelaajan näkymä sellaisenaan ja katse alas), muut näkymät ohitetaan.
## Näkymät: laukaisualusta päivällä, Max Q, kiertorata Maan päivä- ja yöpuolen yllä, Mars lähellä, Jupiterin
## ilmajarrutus, Saturnus renkaineen, Aurinko kohti katsottaessa, planeetan varjo ja zoomaus näyttöihin. Lopuksi mitataan ruutunopeus.

const START := 1794614400000.0 # 2026-11-14T00:00:00Z

var dir := ""
var only := ""
var state_path := ""
var G: Node
var ui: VoyageUI
var cv: CockpitView
var tag := ""
var report: PackedStringArray = []


func _ready() -> void:
	G = Game
	ui = get_parent().ui
	cv = ui.cockpit_view
	var win := Vector2i(1600, 900)
	var q := 2
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--cockpitshotstest="):
			dir = arg.split("=")[1]
		elif arg.begins_with("--size="):
			var p := arg.split("=")[1].split("x")
			win = Vector2i(int(p[0]), int(p[1]))
		elif arg.begins_with("--quality="):
			q = int(arg.split("=")[1])
		elif arg.begins_with("--only="):
			only = arg.split("=")[1]
		elif arg.begins_with("--state="):
			state_path = arg.split("=")[1]
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().content_scale_factor = 1.0
	DisplayServer.window_set_size(win)
	Settings.set_quality(q)
	Settings.set_view("cockpit")
	ui._refresh_overlays()
	if not Settings.panel_hidden:
		ui.toggle_panel()
	tag = "%s-q%d" % ["web" if Settings.is_compatibility() else "fwd", Settings.quality]
	await _frames(5)
	await _run()
	if Settings.panel_hidden:
		ui.toggle_panel()
	var f := FileAccess.open(dir.path_join("raportti-%s.txt" % tag), FileAccess.WRITE)
	f.store_string("\n".join(report) + "\n")
	G.fake_real_ms = -1.0
	DirAccess.remove_absolute(G.TEST_SAVE_PATH)
	finish()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func shot(name: String, settle: int = 40) -> void:
	await _frames(settle)
	var path := dir.path_join("%s-%s.png" % [tag, name])
	get_viewport().get_texture().get_image().save_png(path)
	report.append("%s: sunlit %.2f, aurinko %.3f AU, lähin %s" % [name, cv.space.sunlit, cv.space.sun_distance / Space.AU_M, cv.space.nearest.get("name", "-")])
	check("kuva " + name, FileAccess.file_exists(path))


func want(name: String) -> bool:
	return only == "" or only == name


## Tila suoraan: alus kappaleen kiertoradalla; arg = perikeskuksen suunta (rad), epoch = nyt.
func orbit_at(body: String, t: float, arg: float, low: bool = false) -> void:
	var s: Dictionary = G.fresh()
	s.pad = false
	s.location = body
	s.orbit = {"epoch": t, "arg": arg}
	s.lowOrbit = body if low else null
	s.simTime = t
	s.realTime = t
	s.explored = ["Maa"]
	G.state = s
	G.fake_real_ms = t
	G.aero_at = -INF
	G.burn_at = -INF
	G.load_game_from_state()
	cv.snap_attitude()


## Auringon kiertoradalla (ei kohdetta) paikassa r (km), nokka suuntaan dir.
func drift_at(r: PackedFloat64Array, t: float) -> void:
	orbit_at("Maa", t, 0.0)
	G.state.location = null
	G.state.orbit = null
	G.state.drift = {"r": r, "v": Flight.planet_state("Maa", t).v, "t": t}
	G.load_game_from_state()


## Kiertoradan kulma, jossa alus on kappaleen ja Auringon välissä (päiväpuoli) tai takana (yöpuoli).
func sun_angle(body: String, t: float, behind: bool) -> float:
	var p: PackedFloat64Array = Flight.body_state(body, t).r
	var a := atan2(-p[1], -p[0])
	return a + PI if behind else a


func _run() -> void:
	if state_path != "":
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(state_path))
		check("tallennus luettu", saved is Dictionary)
		if saved is Dictionary:
			G.state = saved
			G.fake_real_ms = float(saved.realTime)
			G.load_game_from_state()
			cv.snap_attitude()
			await shot("tallennus", 120)
			cv.reset_view()
			await shot("tallennus-alas", 120)
		return
	# Laukaisualusta päivällä: haetaan hetki, jolloin Aurinko on korkealla laukaisupaikan yllä.
	var best := START
	var best_day := -2.0
	for i in 144:
		var t := START + i * 600000.0
		var L := Flight.launch_state(null, t)
		var sun := Flight.scale(L.r, -1.0 / Flight.norm(L.r))
		var up := Flight.scale(L.rel.r, 1.0 / Flight.norm(L.rel.r))
		var d := Flight.dot(sun, up)
		if d > best_day and d < 0.8:
			best_day = d
			best = t
	G.fake_real_ms = best
	G.new_game()
	cv.reset_view()
	if want("alusta"):
		await shot("alusta-paiva", 60)
	G.start_countdown()
	G.fake_real_ms += 10000.0 + 68000.0
	G.tick()
	if want("maxq"):
		await shot("max-q", 30)
	# Kiertorata Maan päiväpuolella ja yöpuolella: katse alas Maahan.
	var t0 := best + 86400000.0
	if want("paiva"):
		orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
		await _frames(2)
		cv.reset_view()
		await shot("kiertorata-paiva", 80)
	if want("yo"):
		orbit_at("Maa", t0, sun_angle("Maa", t0, true) + 0.25)
		await _frames(3)
		cv.reset_view()
		await shot("kiertorata-yo", 80)
	# Planeetan varjo: yöpuolelta katse kohti Aurinkoa, joka on Maan takana.
	if want("varjo"):
		# Maan varjossa 8 000 km:n päässä Maan keskipisteestä: Aurinko juuri Maan reunan takana, ilmakehä hehkuu.
		var e: PackedFloat64Array = Flight.planet_state("Maa", t0).r
		var away := Flight.scale(e, 1.0 / Flight.norm(e)) # Auringosta poispäin
		var side := Flight.cross(away, PackedFloat64Array([0, 0, 1]))
		side = Flight.scale(side, 1.0 / Flight.norm(side))
		var ang := asin(6371.0 / 8000.0) - deg_to_rad(1.5)
		var off := Flight.add(Flight.scale(away, 8000.0 * cos(ang)), Flight.scale(side, 8000.0 * sin(ang)))
		drift_at(Flight.add(e, off), t0)
		await _frames(3)
		cv.face(cv.direction_to("Aurinko").rotated(Vector3.UP, 0.12))
		cv.reset_view()
		await shot("varjo", 80)
	# Aurinko kohti katsottaessa Maan kiertoradalla.
	if want("aurinko"):
		# Auringon kiertoradalla (ei kohdetta) Venuksen radan tuntumassa: nokka lähes kohti Aurinkoa.
		var ve: PackedFloat64Array = Flight.planet_state("Venus", t0).r
		drift_at(Flight.add(ve, PackedFloat64Array([3.0e6, 2.0e6, 0.0])), t0)
		await _frames(3)
		cv.face(cv.direction_to("Aurinko").rotated(Vector3.UP, 0.25).rotated(Vector3.RIGHT, -0.12))
		cv.reset_view()
		await shot("aurinko", 80)
	# Mars lähellä: matala rata päiväpuolella.
	if want("mars"):
		orbit_at("Mars", t0, sun_angle("Mars", t0, false) + 0.6)
		await _frames(2)
		cv.reset_view()
		await shot("mars", 120)
	# Jupiterin ilmajarrutus: matala rata ja plasma.
	if want("jupiter"):
		orbit_at("Jupiter", t0, sun_angle("Jupiter", t0, false) + 0.4, true)
		G.aero_at = G.real_ms() if not OS.get_cmdline_user_args().has("--no-aero") else -INF
		await _frames(2)
		cv.reset_view()
		await shot("jupiter-ilmajarrutus", 60)
	# Saturnus renkaineen Titanin kiertoradalta.
	if want("saturnus"):
		# Saturnuksen venyneellä radalla noin 600 000 km:n päässä, Aurinko takana.
		orbit_at("Saturnus", t0, sun_angle("Saturnus", t0, false) + 0.5)
		var period := Flight.orbit_period("Saturnus") * 1000.0
		var best_dt := 0.0
		for i in 200:
			var dt := period * i / 400.0
			var r: float = Flight.norm(Flight.parking_state("Saturnus", t0 + dt, G.state.orbit).rel.r)
			if absf(r - 6.0e5) < absf(Flight.norm(Flight.parking_state("Saturnus", t0 + best_dt, G.state.orbit).rel.r) - 6.0e5):
				best_dt = dt
		G.state.orbit.epoch = t0 - best_dt
		# Rata käännetään niin, että alus on Saturnuksen päiväpuolella (Aurinko aluksen takana sivussa).
		var rel: PackedFloat64Array = Flight.parking_state("Saturnus", t0, G.state.orbit).rel.r
		G.state.orbit.arg = float(G.state.orbit.arg) + sun_angle("Saturnus", t0, false) + 0.45 - atan2(rel[1], rel[0])
		cv.snap_attitude()
		await _frames(3)
		cv.reset_view()
		await shot("saturnus", 120)
	# Zoomaus näyttöihin: keskinäyttö, tutka ja etukamera.
	if want("zoom"):
		orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
		await _frames(2)
		cv.reset_view()
		for i: int in [2, 0, 4]:
			cv.zoom_to(i)
			await shot("zoom-%d" % i, 60)
		cv.reset_view()
	# Ruutunopeus: kiertorata Maan yllä, katse Maahan, 5 s.
	orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
	cv.reset_view()
	await _frames(30)
	var frames := 0
	var t_start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_start < 5000:
		await get_tree().process_frame
		frames += 1
	var fps := frames * 1000.0 / (Time.get_ticks_msec() - t_start)
	report.append("ruutunopeus: %.1f fps (%s, %s, laatu %s, ikkuna %s)" % [fps, RenderingServer.get_video_adapter_name(),
		RenderingServer.get_current_rendering_method(), Settings.quality_name(), DisplayServer.window_get_size()])
	print(report[-1])
