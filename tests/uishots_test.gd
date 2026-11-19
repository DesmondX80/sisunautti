extends TestCase
## Kuvakaappaukset käyttöliittymän tiloista (vaatii ikkunan, ei mukana tools/run_tests.sh:ssa):
##   godot -- --uishotstest=/polku/kuviin [--size=1600x900]
## Kuvat: <hakemisto>/<leveys>x<korkeus>-<nn>-<tila>.png

const START_REAL := 1794643200000.0 # 2026-11-14T08:00:00Z

var dir := ""
var G: Node
var ui: VoyageUI
var n := 0
var tag := ""


func _ready() -> void:
	G = Game
	ui = get_parent().ui
	var win_size := Vector2i(1600, 900)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--uishotstest="):
			dir = arg.split("=")[1]
		elif arg.begins_with("--size="):
			var p := arg.split("=")[1].split("x")
			win_size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(dir)
	get_window().content_scale_factor = 1.0
	DisplayServer.window_set_size(win_size)
	tag = "%dx%d" % [win_size.x, win_size.y]
	await _frames(5)
	await _run()
	G.fake_real_ms = -1.0
	DirAccess.remove_absolute(G.TEST_SAVE_PATH)
	finish()


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func shot(name: String, to_end: bool = false) -> void:
	await _frames(4)
	if to_end:
		ui.scroll_panel_to_end()
		await _frames(2)
	n += 1
	var path := dir.path_join("%s-%02d-%s.png" % [tag, n, name])
	get_viewport().get_texture().get_image().save_png(path)
	check("kuva " + name, FileAccess.file_exists(path))


func advance(ms: float, step: float = 100.0) -> void:
	var end: float = G.fake_real_ms + ms
	while G.fake_real_ms < end:
		G.fake_real_ms = minf(end, G.fake_real_ms + step)
		G.tick()


func fly_until_arrival() -> void:
	G.set_warp(3)
	var guard := 0
	while G.state.flight == null and guard < 3000:
		advance(100)
		guard += 1
	guard = 0
	while G.sim_now() < float(G.state.flight.arrive) and guard < 20000:
		if G.warp_index() == 0:
			var left: float = float(G.state.flight.arrive) - G.sim_now()
			G.set_warp(G.WARPS.size() - 1 if left > 400.0 * G.DAY else 4)
		advance(100)
		guard += 1


func choose_and_arm(kind: String = "cheapest") -> void:
	G.finish_search()
	var o: Array = G.options.filter(func(x: Dictionary) -> bool: return x.kind == kind)
	G.choose(o[0])
	G.jump_to_window()
	G.arm()


func _run() -> void:
	G.fake_real_ms = START_REAL
	G.new_game()
	await shot("alusta")
	G.start_countdown()
	advance(3000)
	await shot("lahtolaskenta")
	advance(7000 + 70000)
	await shot("max-q")
	G.set_warp(1)
	advance(45000)
	var orbit_json: String = G.to_json()
	await shot("kiertorata-maa")
	G.begin_search("Mars")
	G._process(0.0)
	G._process(0.0)
	await shot("haku", true)
	G.finish_search()
	await shot("vaihtoehdot", true)
	ui._log_open = true
	ui._dirty = true
	await shot("vaihtoehdot-loki", true)
	ui._log_open = false
	G.choose(G.options[0])
	await shot("odotus", true)
	G.jump_to_window()
	await shot("ikkuna-auki", true)
	G.arm()
	await shot("lahtopoltto-paalla", true)
	G.set_warp(3)
	while G.state.flight == null:
		advance(100)
	G.set_warp(5)
	advance(2000)
	await shot("lento")
	ui._burn_open = true
	ui._dirty = true
	await shot("kurssikorjaus", true)
	ui._burn_open = false
	ui._dirty = true
	ui.map.set_follow(true)
	await shot("lento-seuranta")
	ui.map.set_follow(false)
	fly_until_arrival()
	await shot("saapuminen-mars", true)
	G.capture()
	await shot("kiertorata-mars")
	G.start_survey()
	G.set_warp(3)
	advance(1000)
	await shot("kartoitus")
	G.set_warp(4)
	advance(2000)
	await shot("tutkittu-mars", true)
	G.local_option("Phobos")
	await shot("kuu-vaihtoehto", true)
	# Jupiter ja ilmajarrutus
	G.load_json(orbit_json)
	G.load_game_from_state()
	G.begin_search("Jupiter")
	choose_and_arm()
	fly_until_arrival()
	await shot("saapuminen-jupiter-ilmajarrutus", true)
	# Ohilento ilman polttoainetta
	G.load_json(orbit_json)
	G.load_game_from_state()
	G.begin_search("Venus")
	choose_and_arm()
	fly_until_arrival()
	G.state.fuel = 0.0
	G.changed.emit()
	await shot("saapuminen-ei-polttoainetta", true)
	G.capture()
	await shot("auringon-kiertorata", true)
	# Telakka: ionialus Maan kiertoradalla ja spiraali
	G.load_json(orbit_json)
	G.load_game_from_state()
	G.change_ship("ioni")
	G.begin_search("Mars")
	G.finish_search()
	G.choose(G.options[0])
	G.jump_to_window()
	await shot("ioni-spiraali-valmis", true)
	G.start_spiral()
	G.set_warp(4)
	advance(3000)
	await shot("ioni-spiraali")
	ui.show_about()
	await _frames(2)
	await shot("tietoa")
	ui._about.hide()
	ui.show_restart()
	await shot("aloita-alusta")
	ui._confirm.hide()
	if ui.size.x >= VoyageUI.WIDE_MIN:
		ui.toggle_panel()
		await shot("paneeli-piilossa")
		ui.toggle_panel()
	# Aluksen viat (#42): johdotus kesken, koodi rivi valittuna, venttiilit, piilotettu banneri ja tuhoutuminen.
	G.load_json(orbit_json)
	G.load_game_from_state()
	G.start_fault("johdot")
	var f: Dictionary = G.state.fault
	G.fault_wire(0, f.right.find(f.left[0]))
	G.fault_wire(1, f.right.find(f.left[1]))
	await _frames(10)
	await shot("vika-johdot")
	G.state.fault = null
	G.start_fault("koodi")
	await shot("vika-koodi")
	G.fault_code_line(int(Faults.code_of(G.state.fault).bug))
	await _frames(3)
	await shot("vika-koodi-rivi")
	G.state.fault = null
	G.start_fault("paine")
	for v in Faults.VALVES:
		var q: Dictionary = G.state.fault.duplicate(true)
		q.valves[v] = true
		if not Faults.pressures_ok(q):
			G.fault_valve(v)
			break
	await _frames(30)
	await shot("vika-paine")
	ui.fault_panel._hidden = true
	ui.fault_panel._sync()
	G.state.fault.remaining = 14000.0
	await shot("vika-banneri")
	ui.fault_panel._hidden = false
	G.destroy_ship()
	await _frames(80)
	await shot("tuhoutui")
	G.new_game()
	await _frames(3)
	check("uusi peli tuhon jälkeen", not ui.game_over.visible and not ui.fault_panel.visible)
