extends TestCase
## Kuvakaappaukset ohjaamosta (vaatii ikkunan, ei mukana tools/run_tests.sh:ssa):
##   godot -- --cockpitshotstest=/polku/kuviin [--size=1600x900] [--quality=2] [--only=nimi] [--state=tallennus.json]
## --state: kuva annetusta tallennuksesta (pelaajan näkymä sellaisenaan ja katse alas), muut näkymät ohitetaan.
## Näkymät: manuaaliohjaus (--only=manuaali), aloitusvalikko (--only=valikko), radio (--only=radio), takakamera (--only=taka), 360°-kamera (--only=360), laukaisualusta päivällä, laukaisutorni (nousu ja yö, --only=torni), Max Q, kiertorata Maan päivä- ja yöpuolen yllä, Kuun ja Marsin pinta kiertoradalta (--only=kuupinta, --only=marspinta), Mars lähellä, Jupiterin
## ilmajarrutus, Saturnus renkaineen, Aurinko kohti katsottaessa, planeetan varjo, zoomaus näyttöihin ja kaikki
## näytöt lähtölaskennassa, pitkällä lennolla ja kuun kiertoradalla (--only=naytot). Lopuksi mitataan ruutunopeus.

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
		elif arg.begins_with("--pano-gain="): # panoraaman kirkkauden kokeilu
			cv.overlay_mat.set_shader_parameter("pano_gain", float(arg.split("=")[1]))
		elif arg.begins_with("--pano-tint="):
			var tt := arg.split("=")[1].split(",")
			cv.overlay_mat.set_shader_parameter("pano_tint", Vector3(float(tt[0]), float(tt[1]), float(tt[2])))
		elif arg.begins_with("--pano-side="): # panoraaman jatkokohta sivukuvan reunalla (asteina)
			cv.overlay_mat.set_shader_parameter("pano_side", deg_to_rad(float(arg.split("=")[1])))
		elif arg.begins_with("--pano-side-left="):
			cv.overlay_mat.set_shader_parameter("pano_side_left", deg_to_rad(float(arg.split("=")[1])))
		elif arg.begins_with("--side-tint="):
			var st := arg.split("=")[1].split(",")
			cv.overlay_mat.set_shader_parameter("side_tint", Vector3(float(st[0]), float(st[1]), float(st[2])))
		elif arg.begins_with("--pano-edge="): # panoraaman sovituksen kokeilu (asteina)
			cv.overlay_mat.set_shader_parameter("pano_edge", deg_to_rad(float(arg.split("=")[1])))
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


## Hetki, jolloin Aurinko on korkealla laukaisupaikan yllä (ensimmäisen vuorokauden aikana).
func pad_day() -> float:
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
	return best


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
	var best := pad_day()
	G.fake_real_ms = best
	G.new_game()
	cv.reset_view()
	if want("alusta"):
		await shot("alusta-paiva", 60)
	# Laukaisutorni nousun alussa ja yöllä (#27).
	if want("torni"):
		G.start_countdown()
		G.fake_real_ms += 10000.0 + 3000.0
		G.tick()
		await shot("torni-nousu-3s", 20)
		G.fake_real_ms += 5000.0
		G.tick()
		await shot("torni-nousu-8s", 20)
		G.fake_real_ms = best + 43200000.0
		G.new_game()
		cv.reset_view()
		await shot("torni-yo", 60)
		G.fake_real_ms = best
		G.new_game()
		cv.reset_view()
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
	# Kuun (#36) ja Marsin (#43) pinta kiertoradalta: Aurinko korkealla, terminaattorin lähellä (pitkät varjot) ja yöpuoli.
	if want("kuupinta"):
		await _surface_shots("Kuu", "kuupinta", t0)
	if want("marspinta"):
		var dt := 18.0 * 3600000.0 # Mars kääntynyt: alla kraatterista ylänköä eikä Amazoniksen tasankoa
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--mars-h="):
				dt = float(arg.split("=")[1]) * 3600000.0
		await _surface_shots("Mars", "marspinta", t0 + dt, 1.2)
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
	# Zoomaus näyttöihin: keskinäyttö, tutka ja kohdekamera.
	if only == "sivut":
		orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
		for v: Array in [["eteen", 0.0, 0.0], ["vasen", 0.9, 0.1], ["oikea", -0.8, 0.2], ["vasen-alas", 0.75, -0.35], ["oikea-alas", -0.75, -0.35],
				["oikea-reuna", -1.25, 0.05], ["vasen-reuna", 1.25, 0.05], ["oikea-ylos", -0.8, 0.55], ["vasen-ylos", 0.8, 0.55]]:
			cv.yaw = v[1]
			cv.pitch = v[2]
			await shot("katse-" + v[0], 20)
		cv.reset_view()
	if want("zoom"):
		orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
		await _frames(2)
		cv.reset_view()
		for i: int in [2, 0, 4]:
			cv.zoom_to(i)
			await shot("zoom-%d" % i, 60)
		cv.reset_view()
		# Katse käännettynä: kuvan reunan yli jatkuva sisätila (sivut, katto, taakse).
		for v: Array in [["vasen", 0.9, 0.1], ["oikea", -0.8, 0.2], ["katto", 0.0, 0.95], ["taakse", 2.5, -0.1], ["alas", 0.0, -0.8], ["alas-vasen", 0.5, -0.6]]:
			cv.yaw = v[1]
			cv.pitch = v[2]
			await shot("katse-" + v[0], 20)
		cv.reset_view()
	# Näyttöjen tekstit eri vaiheissa (#21): lähtölaskenta, lento kaukana (pitkät luvut) ja kuun kiertorata.
	if want("naytot"):
		await _screens_shots()
	# Lähestyminen Kuuhun ja saapuminen kiertoradalle (#20).
	if want("kuu"):
		await _moon_approach()
	# Aloitusvalikko (#29) ja sen asetukset.
	if want("valikko"):
		var menu: StartMenu = get_parent().menu
		menu.open()
		await shot("valikko", 90)
		menu.toggle_settings()
		await shot("valikko-asetukset", 30)
		menu.toggle_settings()
		menu.visible = false
	# Manuaaliohjaus (#30): lento Marsiin, alus käännetty kohti Maata, kaasu päällä.
	if want("manuaali"):
		orbit_at("Maa", t0, 0.0)
		G.begin_search("Mars")
		G.finish_search()
		G.choose(G.options[0])
		G.jump_to_window()
		G.arm()
		G.launch()
		G.burn_at = -INF
		G.anchor(float(G.state.flight.depart) + 40.0 * 60000.0, 0)
		cv.snap_attitude()
		await _frames(3)
		cv.toggle_manual()
		cv.face(cv.direction_to("Maa").rotated(Vector3.UP, 0.35))
		cv.manual_throttle = 0.8
		await shot("manuaali", 40)
		cv.toggle_manual()
	# Manuaaliohjaus kiertoradalla (#57): pakorata myötäsuuntaisella poltolla ja syöksy kohti pintaa.
	if want("manuaali") or want("manuaali-rata"):
		orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
		var rel: Dictionary = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
		G.state.orbit = {"epoch": G.sim_now(), "arg": 0.0, "rel": {"r": rel.r, "v": Flight.scale(rel.v, 1.42)}}
		cv.snap_attitude()
		await _frames(3)
		cv.toggle_manual()
		cv.manual_throttle = 0.6
		await shot("manuaali-pakorata", 40)
		cv.toggle_manual()
		var r0: PackedFloat64Array = Flight.scale(rel.r, (6378.0 + 45.0) / Flight.norm(rel.r))
		var v0 := Flight.add(Flight.scale(rel.v, 1.0), Flight.scale(r0, -0.6 / Flight.norm(r0)))
		G.state.orbit = {"epoch": G.sim_now(), "arg": 0.0, "rel": {"r": r0, "v": v0}}
		cv.snap_attitude()
		await _frames(3)
		cv.toggle_manual()
		cv.face(cv.direction_to("Maa").rotated(Vector3.UP, 0.5))
		cv.manual_throttle = 1.0
		await shot("manuaali-syoksy", 40)
		cv.toggle_manual()
		# Ilmakehälento Marsissa 12 km:n korkeudessa: nokka hieman menosuunnan yläpuolella (#57).
		orbit_at("Mars", t0, sun_angle("Mars", t0, false) + 0.2)
		var rm: Dictionary = Flight.parking_state("Mars", G.sim_now(), G.state.orbit).rel
		var rmr: PackedFloat64Array = Flight.scale(rm.r, (3389.5 + 12.0) / Flight.norm(rm.r))
		var rmv: PackedFloat64Array = Flight.scale(rm.v, 0.9 / Flight.norm(rm.v))
		G.state.orbit = {"epoch": G.sim_now(), "arg": 0.0, "rel": {"r": rmr, "v": rmv}}
		cv.snap_attitude()
		await _frames(3)
		cv.toggle_manual()
		var up_m := Space.to_scene(rmr).normalized()
		cv.ship.basis = Basis.looking_at(Space.to_scene(rmv).normalized().rotated(Space.to_scene(Flight.cross(rmr, rmv)).normalized(), 0.12), up_m)
		cv.manual_throttle = 0.5
		await shot("manuaali-mars-ilmakeha", 30)
		cv.toggle_manual()
	# Lentoavut (#58): vaakalento Maan ilmakehässä 10 km:ssä, horisonttiristikko ja korkeudenvakain päällä.
	if want("lentoavut"):
		orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
		var re: Dictionary = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
		var rer: PackedFloat64Array = Flight.scale(re.r, (6371.0 + 10.0) / Flight.norm(re.r))
		var rev: PackedFloat64Array = Flight.scale(re.v, 0.25 / Flight.norm(re.v))
		G.state.orbit = {"epoch": G.sim_now(), "arg": 0.0, "rel": {"r": rer, "v": rev}}
		cv.snap_attitude()
		await _frames(3)
		cv.toggle_manual()
		var up_e := Space.to_scene(rer).normalized()
		cv.ship.basis = Basis.looking_at(Space.to_scene(rev).normalized().rotated(Space.to_scene(Flight.cross(rer, rev)).normalized(), 0.05), up_e) \
			* Basis(Vector3(0, 0, 1), 0.25)
		cv.manual_throttle = 0.1
		await shot("lentoavut-ristikko", 30)
		cv.set_alt_hold(true)
		cv.adjust_alt(2.0)
		Settings.speed_unit = "kmh"
		await shot("lentoavut-vakain", 40)
		Settings.speed_unit = "kms"
		cv.toggle_manual()
		# Vakain laskeutuu 200 km:n radalta: avaruudessa nokka alas ja automaattikaasu.
		orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
		cv.snap_attitude()
		await _frames(3)
		cv.toggle_manual()
		cv.set_alt_hold(true, 30.0)
		for i in 60:
			cv._manual_step(CockpitState.make(), 0.1)
		await shot("lentoavut-laskeutuminen", 30)
		cv.toggle_manual()
	# Radiopaneeli (#31).
	if want("radio"):
		var radio: Radio = get_parent().radio
		var was: int = Settings.radio_channel
		radio.tune(4, false)
		ui.show_radio()
		await shot("radio", 40)
		ui._radio_popup.hide()
		radio.tune(-1, false)
		Settings.set_radio_channel(was)
	# Takakamera kohdekameranäytöllä (#24): alustalla, kiertoradalla ja lähdön jälkeen poistuva Maa.
	if want("taka"):
		await _rear_shots()
	# Aluksen vika (#42): punainen hälytysvalo ja näyttöjen VIKA-palkit; tuhon jälkeen kohina.
	if only == "vika":
		orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
		G.start_fault("johdot")
		ui.fault_panel._hidden = true
		ui.fault_panel._sync()
		for k in 3:
			await shot("vika-%d" % k, 13 + k * 7)
		G.destroy_ship()
		ui.game_over.visible = false
		ui.game_over.set_process(false)
		await shot("vika-tuho", 20)
		ui.game_over.set_process(true)
		G.new_game()
	# Kohdekamera (#39): kaukoputki aluksen paikalta.
	if want("kohde"):
		await _tele_shots()
	if only == "kohdeaurinko":
		await _tele_sun(START + 86400000.0)
	# 360°-kamera (#38): näytöllä ja koko näytöllä.
	if want("360"):
		await _pan_shots()
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


## Kiertoradalta kappaleen pinta kolmella Auringon korkeudella; raporttiin Auringon korkeus aluksen alla.
## low_sun: aluksen paikka subsolaaripisteestä (rad) terminaattorikuvassa; korkealta radalta katse ulottuu kauemmas.
func _surface_shots(body: String, prefix: String, t0: float, low_sun: float = 1.35) -> void:
	for v: Array in [["paiva", 0.3], ["terminaattori", low_sun], ["yo", PI - 0.5]]:
		orbit_at(body, t0, sun_angle(body, t0, false) + v[1])
		await _frames(2)
		cv.reset_view()
		await shot(prefix + "-" + v[0], 150)
		var down: Vector3 = (cv.space.nearest.root as Node3D).position.normalized()
		var fwd := -cv.camera.global_transform.basis.z
		report.append("  Auringon korkeus alla %.1f°, katseen suuntaan (Aurinko·eteen) %.2f" % [rad_to_deg(asin(-cv.space.sun_dir.dot(down))), cv.space.sun_dir.dot(fwd)])


## Zoomaus jokaiseen näyttöön (0–5) eri vaiheissa.
func _screens_shots() -> void:
	G.fake_real_ms = START
	G.new_game()
	G.start_countdown()
	G.fake_real_ms += 4000.0
	await _zoom_all("alusta")
	# Lento Neptunukselle puolivälissä: pitkä lentoaika, suuret etäisyydet ja nopeudet.
	var t0 := START + 86400000.0
	orbit_at("Maa", t0, 0.0)
	G.change_ship("ydin")
	G.state.fuel = G.fuel_max()
	G.begin_search("Neptunus")
	G.finish_search()
	if not G.options.is_empty() and G.choose(G.options[0]):
		G.jump_to_window()
		if G.arm():
			G.launch()
			var f: Dictionary = G.state.flight
			G.anchor(float(f.depart) + (float(f.arrive) - float(f.depart)) * 0.6, 7)
			await _zoom_all("lento")
	orbit_at("Ganymedes", t0, 0.5)
	await _zoom_all("ganymedes")
	cv.reset_view()


func _zoom_all(phase: String) -> void:
	cv.snap_attitude()
	await _frames(2)
	for i in 6:
		cv.zoom_to(i)
		await shot("naytto-%s-%d" % [phase, i], 30)
	cv.reset_view()


## Kuu-lento: kuvat ennen saapumista (h) ja kiertoradalla saapumisen jälkeen.
func _moon_approach() -> void:
	var t0 := START + 86400000.0
	orbit_at("Maa", t0, 0.0)
	G.local_option("Kuu")
	if G.options.is_empty() or not G.choose(G.options[0]):
		check("Kuu-lento", false)
		return
	G.jump_to_window()
	G.arm()
	cv.snap_attitude()
	cv.reset_view()
	await shot("kuu-lahtopoltto", 40)
	G.launch()
	G.burn_at = -INF
	var f: Dictionary = G.state.flight
	var arrive := float(f.arrive)
	# Irtautuminen kiertoradalta (#26): Maa jää hiljalleen alle ja taakse.
	for m: float in [5.0, 30.0, 120.0, 600.0]:
		G.anchor(float(f.depart) + m * 60000.0, 0)
		cv.snap_attitude()
		await shot("kuu-lahto-%dmin" % roundi(m), 30)
	for h: float in [48.0, 24.0, 12.0, 6.0, 3.0, 1.0, 0.25]:
		var t := arrive - h * 3600000.0
		if t < float(f.depart):
			continue
		G.anchor(t, 0)
		cv.snap_attitude()
		cv.reset_view()
		var d := Flight.norm(Flight.sub(Flight.ship_view(f, t).r, Flight.body_state("Kuu", t).r))
		report.append("kuu -%s h: etäisyys %d km" % [h, roundi(d)])
		await shot("kuu-%sh" % str(h).replace(".", "_"), 30)
	G.anchor(arrive, 0)
	G.tick()
	G.burn_at = -INF
	await _frames(5)
	cv.reset_view()
	await shot("kuu-saapuminen", 60)
	G.capture()
	G.burn_at = -INF
	G.anchor(arrive + 600000.0, 0)
	await shot("kuu-kiertorata", 60)


func _tele_shots() -> void:
	G.fake_real_ms = pad_day()
	G.new_game()
	cv.zoom_to(4)
	await shot("kohde-alusta", 60)
	var t0 := START + 86400000.0
	orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
	cv.snap_attitude()
	cv.zoom_to(4)
	await shot("kohde-kiertorata", 60)
	G.local_option("Kuu")
	G.choose(G.options[0])
	G.jump_to_window()
	G.arm()
	G.launch()
	G.burn_at = -INF
	var f: Dictionary = G.state.flight
	for frac: float in [0.02, 0.5, 0.97, 0.98, 0.99]:
		G.anchor(float(f.depart) + (float(f.arrive) - float(f.depart)) * frac, 0)
		cv.snap_attitude()
		cv.zoom_to(4)
		await shot("kohde-kuulento-%d" % roundi(frac * 100.0), 60)
		report.append("kohde %d %%: %s" % [roundi(frac * 100.0), cv._camera_screen().tele])
	orbit_at("Kuu", t0, sun_angle("Kuu", t0, false) + 0.3)
	cv.snap_attitude()
	cv.zoom_to(4)
	await shot("kohde-kuu-kiertorata", 60)
	# Kaukaiset kohteet: Neptunus ja Saturnus lennolla, Aurinko ilman kohdetta.
	for target: String in ["Neptunus", "Saturnus"]:
		orbit_at("Maa", t0, 0.0)
		G.change_ship("ydin")
		G.state.fuel = G.fuel_max()
		G.begin_search(target)
		G.finish_search()
		if not G.options.is_empty() and G.choose(G.options[0]):
			G.jump_to_window()
			if G.arm():
				G.launch()
				var ft: Dictionary = G.state.flight
				G.anchor(float(ft.depart) + (float(ft.arrive) - float(ft.depart)) * 0.6, 0)
				cv.snap_attitude()
				cv.zoom_to(4)
				await shot("kohde-" + target.to_lower(), 60)
	await _tele_sun(t0)
	cv.reset_view()


func _tele_sun(t0: float) -> void:
	var ve: PackedFloat64Array = Flight.planet_state("Venus", t0).r
	drift_at(Flight.add(ve, PackedFloat64Array([3.0e6, 2.0e6, 0.0])), t0)
	await _frames(3)
	cv.zoom_to(4)
	await shot("kohde-aurinko", 90)


func _pan_shots() -> void:
	var best := pad_day()
	G.fake_real_ms = best
	G.new_game()
	cv.set_cam_mode("360")
	cv.pan_bearing = deg_to_rad(20.0)
	cv.pan_tilt = 0.0
	cv.zoom_to(4)
	await shot("360-alusta", 60)
	cv.toggle_pan_full()
	# Alustalla alus on pystyssä: suuntima 90° katsoo vaakasuoraan torniin päin.
	cv.pan_bearing = deg_to_rad(90.0)
	cv.pan_tilt = 0.0
	await shot("360-alusta-koko", 40)
	var t0 := START + 86400000.0
	orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
	cv.snap_attitude()
	cv.pan_bearing = deg_to_rad(90.0)
	cv.pan_tilt = -0.5
	await shot("360-kiertorata-koko", 40)
	cv.pan_bearing = deg_to_rad(180.0)
	cv.pan_tilt = -0.75
	cv.pan_zoom = 2.0
	await shot("360-kiertorata-koko-taakse", 40)
	cv.pan_zoom = 1.0
	cv.toggle_pan_full()
	cv.zoom_to(4)
	await shot("360-kiertorata", 60)
	cv.set_cam_mode("kohde")
	cv.reset_view()
	check("360° pois", cv.cam_mode == "kohde" and not cv.pan_full)


func _rear_shots() -> void:
	G.fake_real_ms = START
	G.new_game()
	cv.toggle_rear()
	check("takakamera päällä", cv.is_rear())
	cv.zoom_to(4)
	await shot("taka-alusta", 60)
	var t0 := START + 86400000.0
	orbit_at("Maa", t0, sun_angle("Maa", t0, false) + 0.3)
	cv.zoom_to(4)
	await shot("taka-kiertorata", 60)
	G.local_option("Kuu")
	G.choose(G.options[0])
	G.jump_to_window()
	G.arm()
	G.launch()
	G.burn_at = -INF
	var f: Dictionary = G.state.flight
	for m: float in [20.0, 180.0]:
		G.anchor(float(f.depart) + m * 60000.0, 0)
		cv.snap_attitude()
		cv.zoom_to(4)
		await shot("taka-lahto-%dmin" % roundi(m), 60)
	cv.reset_view()
	await shot("taka-ohjaamo", 30)
	cv.toggle_rear()
	check("kohdekamera palaa", not cv.is_rear())
