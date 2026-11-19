extends TestCase
## Pelin tila, kello ja tapahtumat ilman käyttöliittymää: laukaisu kiertoradalle, lento Marsiin aikakiihdytyksellä,
## kartoitus ja tankkaus, ohilento ilman polttoainetta, ilmajarrutus, tallennus ja lataus sekä selainversion
## tallennuksen lataus (tests/data/web_save.json). Kello on testissä käsin asetettu (Game.fake_real_ms).
##   godot --headless -- --gametest

const START_REAL := 1794614400000.0 # 2026-11-14T00:00:00Z

var G: Node
var events: Array[String] = []


func _ready() -> void:
	G = Game
	check("testi käyttää omaa tallennusta", G.save_path == G.TEST_SAVE_PATH)
	for sig: String in ["liftoff", "orbit_reached", "departure_burn", "flyby", "soi_entered", "arrived", "capture_done", "survey_finished", "countdown_started"]:
		var name := sig
		G.connect(sig, func(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void: events.append(name))
	G.fake_real_ms = START_REAL
	G.new_game()
	_launch_to_orbit()
	var orbit_save: String = G.to_json()
	_fly_to_mars()
	_survey_and_refuel()
	_save_and_load()
	_flyby_without_fuel(orbit_save)
	_aerobrake(orbit_save)
	_web_save()
	G.fake_real_ms = -1.0
	DirAccess.remove_absolute(G.TEST_SAVE_PATH)
	finish()


## Kuluttaa oikeaa aikaa askelin ja ajaa pelisilmukan joka askeleella.
func advance(ms: float, step: float = 100.0) -> void:
	var end: float = G.fake_real_ms + ms
	while G.fake_real_ms < end:
		G.fake_real_ms = minf(end, G.fake_real_ms + step)
		G.tick()


## Ajaa kelloa suurimmalla kiihdytyksellä, kunnes ehto täyttyy tai oikeaa aikaa on kulunut max_ms.
func run_until(cond: Callable, max_ms: float = 600000.0) -> bool:
	var spent := 0.0
	while not cond.call() and spent < max_ms:
		if G.warp_index() == 0 and G.state.flight != null and G.sim_now() < float(G.state.flight.arrive) - 60000.0:
			# Pelaaja nostaa kiihdytyksen uudelleen; peli pienentää sen taas ennen seuraavaa tapahtumaa. Lähellä
			# saapumista enintään 1 vrk/s, jotta 100 ms:n askel ei hyppää tapahtuman yli.
			var left: float = float(G.state.flight.arrive) - G.sim_now()
			G.set_warp(G.WARPS.size() - 1 if left > 400.0 * G.DAY else 4)
		G.fake_real_ms += 100.0
		spent += 100.0
		G.tick()
	return cond.call()


func _launch_to_orbit() -> void:
	var s: Dictionary = G.state
	check("uusi peli laukaisualustalla", s.pad and s.location == "Maa" and s.fuel == 14.0 and s.explored == ["Maa"])
	G.set_warp(5)
	check("alustalla kiihdytys enintään 10×", G.warp_index() == 1)
	G.set_warp(0)
	G.start_countdown()
	check("lähtölaskenta 10 s", float(G.state.ascent.liftoff) == G.sim_now() + 10000.0 and events.has("countdown_started"))
	advance(10500)
	check("laukaisu (signaali)", events.has("liftoff") and Flight.launch_state(G.state.ascent.liftoff, G.sim_now()).phase == "Laukaisu")
	G.set_warp(1)
	advance(52000)
	s = G.state
	check("kiertoradalla nousun jälkeen", not s.pad and s.ascent == null and s.orbit != null and events.has("orbit_reached"))
	check("kello pysähtyi kiertoradalle nousun loppuun", G.warp_index() == 0)
	check("lokikirjaan laukaisu", s.log.size() == 1 and String(s.log[0].text).begins_with("Laukaisu Maan pinnalta"))
	var rel: PackedFloat64Array = Flight.parking_state("Maa", G.sim_now(), s.orbit).rel.r
	check("200 km:n radalla", absf(Flight.norm(rel) - Flight.body("Maa").periKm) < 1.0)


func _fly_to_mars() -> void:
	G.begin_search("Mars")
	check("haku käynnissä", G.search != null and not G.options_ready)
	G._process(0.0)
	check("haku etenee ruutu kerrallaan", G.progress > 0.0 and G.progress < 1.0)
	G.finish_search()
	check("reittivaihtoehdot", G.options_ready and G.options.size() >= 2 and G.options[0].kind == "cheapest")
	check("halvin riittää", G.options[0].fuelOk)
	check("valinta", G.choose(G.options[0]) and G.state.plan != null)
	G.jump_to_window()
	check("ikkunan alussa", G.sim_now() == float(G.state.plan.depart))
	check("lähtöpoltto päälle", G.arm() and G.state.plan.armed)
	var fuel_before: float = G.state.fuel
	G.set_warp(3)
	run_until(func() -> bool: return G.state.flight != null, 120000)
	var f: Variant = G.state.flight
	check("lähtöpoltto: lento alkoi", f != null and events.has("departure_burn"))
	if f == null:
		return
	check("polttoainetta kului lähtöön", absf(float(G.state.fuel) - (fuel_before - float(f.dvDep))) < 1e-9)
	check("lokikirjaan lähtöpoltto", String(G.state.log[-1].text).begins_with("Lähtöpoltto Maan kiertoradalta kohti Marsia"))
	_manual_burn()
	G.set_warp(G.WARPS.size() - 1)
	var notices: Array[String] = []
	G.notice_changed.connect(func(t: String) -> void: notices.append(t))
	run_until(func() -> bool: return G.sim_now() >= float(G.state.flight.arrive))
	check("kiihdytys pieneni ennen vaikutuspiiriä", notices.any(func(t: String) -> bool: return t.contains("Marsin vaikutuspiiri lähestyy")))
	check("kiihdytys pieneni ennen saapumista", notices.any(func(t: String) -> bool: return t.contains("saapuminen lähestyy")))
	check("vaikutuspiiri ja saapuminen (signaalit)", events.has("soi_entered") and events.has("arrived"))
	check("kello pysähtyi saapumiseen", G.warp_index() == 0 and G.sim_now() == float(G.state.flight.arrive))
	advance(5000)
	check("kello pysyy saapumisessa", G.sim_now() == float(G.state.flight.arrive))
	var fuel_at_arrival: float = G.state.fuel
	var dv_arr: float = G.state.flight.dvArr
	G.capture()
	var s: Dictionary = G.state
	check("Marsin kiertoradalla", s.location == "Mars" and s.flight == null and s.orbit != null and events.has("capture_done"))
	check("jarrutus kulutti polttoainetta", absf(float(s.fuel) - (fuel_at_arrival - dv_arr)) < 1e-9)
	check("lento lokikirjassa", s.flights.size() == 1 and s.flights[0].captured and s.flights[0].to == "Mars")
	var rel: PackedFloat64Array = Flight.parking_state("Mars", G.sim_now(), s.orbit).rel.r
	check("matalalla Marsin radalla", absf(Flight.norm(rel) - Flight.body("Mars").periKm) < 1.0)


func _survey_and_refuel() -> void:
	G.start_survey()
	check("kartoitus alkoi", G.state.survey != null and G.state.survey.kind == "survey")
	G.set_warp(4) # 1 vrk/s
	advance(1500)
	check("kartoitus valmis", G.state.survey == null and G.state.explored.has("Mars") and events.has("survey_finished"))
	check("polttoaine täydennetty", G.state.fuel == 14.0)
	check("lokikirjaan kartoitus", String(G.state.log[-1].text) == "Mars tutkittu (2/8 planeettaa), polttoaine täydennetty")


func _save_and_load() -> void:
	G.set_warp(3)
	advance(1000)
	# Suljettaessa (park) kello ankkuroidaan ja kiihdytys palaa 1×:ään.
	G.park()
	var before: float = G.sim_now()
	var saved_text := FileAccess.get_file_as_string(G.save_path)
	check("tallennus tiedostoon", saved_text == G.to_json())
	var parsed: Dictionary = JSON.parse_string(saved_text)
	for k: String in ["v", "location", "pad", "ascent", "orbit", "lowOrbit", "drift", "ship", "fuel", "simTime", "realTime", "warp", "plan", "flight", "survey", "explored", "flights", "log"]:
		if not parsed.has(k):
			check("tallennuksessa avain " + k, false)
	G.state = {}
	G.load_game()
	check("lataus palauttaa tilan", G.state.location == "Mars" and G.state.explored.has("Mars") and G.state.flights.size() == 1)
	check("ladattaessa kiihdytys 1×", G.warp_index() == 0)
	check("kello jatkuu ladatusta kohdasta", absf(G.sim_now() - before) < 1.0)


func _restore(json: String) -> void:
	check("tilan palautus", G.load_json(json))
	G.state.realTime = G.real_ms()
	G.load_game_from_state()


func _fly(to: String, pick: String = "cheapest") -> bool:
	G.begin_search(to)
	G.finish_search()
	var o: Array = G.options.filter(func(x: Dictionary) -> bool: return x.kind == pick)
	if o.is_empty() or not G.choose(o[0]):
		return false
	G.jump_to_window()
	if not G.arm():
		return false
	G.set_warp(3)
	run_until(func() -> bool: return G.state.flight != null, 120000)
	if G.state.flight == null:
		return false
	G.set_warp(G.WARPS.size() - 1)
	return run_until(func() -> bool: return G.sim_now() >= float(G.state.flight.arrive))


func _flyby_without_fuel(orbit_save: String) -> void:
	_restore(orbit_save)
	check("palautettu Maan kiertoradalle", G.state.location == "Maa" and not G.state.pad)
	check("lento Venukseen", _fly("Venus"))
	G.state.fuel = 0.0
	G.capture()
	var s: Dictionary = G.state
	check("ohilento: Auringon kiertoradalla", s.location == null and s.drift != null and s.flight == null)
	check("ohilento lokikirjassa", not s.flights[-1].captured and String(s.log[-1].text).begins_with("Ohilento: polttoaine ei riittänyt"))
	check("lähtöpaikka on Auringon kiertorata", not Flight.is_planet(G.here()))


func _aerobrake(orbit_save: String) -> void:
	_restore(orbit_save)
	check("lento Jupiteriin", _fly("Jupiter"))
	check("ilmajarrutus mahdollinen", G.can_aerobrake())
	var fuel: float = G.state.fuel
	G.capture(true)
	var s: Dictionary = G.state
	var b := Flight.body("Jupiter")
	check("matalalla Jupiterin radalla", s.location == "Jupiter" and s.lowOrbit == "Jupiter" and b.periKm == b.low.periKm and b.apoKm == b.periKm)
	check("ilmajarrutus kulutti vain radan noston", absf(float(s.fuel) - (fuel - Flight.aerobrake_dv("Jupiter"))) < 1e-9)
	check("lokikirjaan ilmajarrutus", String(s.log[-1].text).begins_with("Ilmajarrutus Jupiterin kaasukehässä"))
	var text: String = G.to_json()
	G.new_game()
	check("uusi peli palauttaa kaappausradan", b.periKm == b.capture.periKm)
	G.load_json(text)
	G.load_game_from_state()
	check("ladattu matala rata", b.periKm == b.low.periKm)
	G.new_game()


func _web_save() -> void:
	var text := FileAccess.get_file_as_string("res://tests/data/web_save.json")
	var web: Dictionary = JSON.parse_string(text)
	check("selaintallennuksen tuonti", G.import_web_save(text))
	var s: Dictionary = G.state
	check("tuotu tila", s.ship == web.ship and s.fuel == web.fuel and s.log.size() == web.log.size() + 1 and String(s.log[-1].text) == "Peli tuotiin selainversiosta")
	var f: Variant = s.flight
	check("tuodussa pelissä lento käynnissä", f != null and f.to == "Mars")
	if f == null:
		return
	# Kello jatkuu selaintallennuksen ankkurista: simTime + (nyt − realTime).
	G.fake_real_ms = float(web.realTime) + 3600000.0
	check("kello jatkuu samasta kohdasta", absf(G.sim_now() - (float(web.simTime) + 3600000.0)) < 1.0)
	var st := Flight.ship_state(f, G.sim_now())
	check("aluksen paikka lasketaan tuodusta lennosta", Flight.norm(st.r) > 1e8)
	G.set_warp(G.WARPS.size() - 1)
	check("tuotu lento jatkuu perille", run_until(func() -> bool: return G.sim_now() >= float(G.state.flight.arrive)))
	G.capture()
	check("perillä Marsin kiertoradalla", G.state.location == "Mars")


## Manuaaliohjaus (#30): kaasu nokan suuntaan muuttaa rataa ja kuluttaa polttoainetta; polton loppu lokikirjaan.
func _manual_burn() -> void:
	G.set_warp(0)
	advance(60000)
	var f: Dictionary = G.state.flight
	var fuel: float = G.state.fuel
	var t: float = G.sim_now()
	var v: PackedFloat64Array = Flight.ship_state(f, t).v
	var dir := Flight.scale(v, 1.0 / Flight.norm(v))
	check("manuaalipoltto lennolla", G.can_manual_burn() and G.manual_thrust(dir, 1.0, 0.3) and G.manual_thrust(dir, 1.0, 0.3))
	G.manual_thrust(dir, 0.0, 0.0)
	var used: float = fuel - float(G.state.fuel)
	check("manuaalipoltto kuluttaa polttoainetta", absf(used - float(G.MANUAL_ACCEL) * 0.6) < 1e-6)
	var after: PackedFloat64Array = Flight.ship_state(G.state.flight, G.sim_now() + 1000.0).v
	check("manuaalipoltto kiihdyttää menosuuntaan", Flight.norm(after) > Flight.norm(v))
	check("manuaalipoltto lokikirjaan", String(G.state.log[-1].text).begins_with("Manuaalipoltto"))
	# Palautetaan alkuperäinen lento, jotta muu testi kulkee ennallaan.
	G.state.flight = f
	G.state.fuel = fuel
