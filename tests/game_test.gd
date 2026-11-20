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
	_manual_orbit(orbit_save)
	_manual_all_bodies(orbit_save)
	_manual_sound_and_fuel(orbit_save)
	_air_flight(orbit_save)
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


## Polttaa manuaalisesti suuntaan dir täsmälleen Δv:n verran (täysi kaasu lyhyin askelin; kello ei kulu).
func _burn(dir: PackedFloat64Array, dv: float) -> void:
	var steps := ceili(dv / (float(G.MANUAL_ACCEL) * 0.1))
	var dt := dv / (float(G.MANUAL_ACCEL) * steps)
	for i in steps:
		G.manual_thrust(dir, 1.0, dt)
	G.manual_thrust(dir, 0.0, 0.0)


## Manuaaliohjaus kiertoradalla (#57): ilman kaasua rata pysyy, myötäsuuntainen poltto venyttää rataa ja
## pakonopeudessa alus irtoaa Auringon kiertoradalle; poltto kohti planeettaa vie törmäykseen.
func _manual_orbit(orbit_save: String) -> void:
	_restore(orbit_save)
	G.set_warp(0)
	check("manuaalipoltto kiertoradalla mahdollinen", G.state.location == "Maa" and G.can_manual_burn())
	G.manual_thrust(PackedFloat64Array([1.0, 0.0, 0.0]), 0.0, 0.5)
	advance(2000)
	check("ilman kaasua rata ennallaan", not Flight.is_free_orbit(G.state.orbit))
	var rel: Dictionary = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
	var pro := Flight.scale(rel.v, 1.0 / Flight.norm(rel.v))
	var fuel: float = G.state.fuel
	_burn(pro, 1.0)
	var sh := Flight.orbit_shape("Maa", rel.r, Flight.add(rel.v, Flight.scale(pro, 0.0)))
	var rel2: Dictionary = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
	var sh2 := Flight.orbit_shape("Maa", rel2.r, rel2.v)
	check("myötäsuuntainen poltto venyttää rataa (apokeskus %s km)" % Fmt.num(sh2.apo), Flight.is_free_orbit(G.state.orbit)
		and float(sh2.apo) > float(sh.apo) + 4800.0 and absf(float(sh2.peri) - float(sh.peri)) < 20.0 and not sh2.escape)
	check("poltto kuluttaa polttoainetta", absf(fuel - float(G.state.fuel) - 1.0) < 0.02)
	_burn(pro, 2.4)
	rel2 = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
	check("pakonopeudessa pakorata", Flight.orbit_shape("Maa", rel2.r, rel2.v).escape)
	G.set_warp(4)
	var left := false
	for i in 3000:
		G.fake_real_ms += 100.0
		G.tick()
		if G.warp_index() < 4:
			G.set_warp(4)
		if G.state.location == null:
			left = true
			break
	check("alus irtoaa Maan vaikutuspiiristä Auringon kiertoradalle", left and G.state.drift != null and G.state.orbit == null
		and String(G.state.log[-1].text).begins_with("Pakorata"))
	G.set_warp(0)
	var d0: Dictionary = Flight.departure_state(G.state.drift, G.sim_now())
	var dh := Flight.scale(d0.v, 1.0 / Flight.norm(d0.v))
	_burn(dh, 0.5)
	var d1: Dictionary = Flight.departure_state(G.state.drift, G.sim_now())
	check("manuaalipoltto Auringon kiertoradalla", G.can_manual_burn() and absf(Flight.norm(d1.v) - Flight.norm(d0.v) - 0.5) < 0.02)
	# Nopeusmittari: myötäsuuntainen kaasu kasvattaa nopeutta, jarrutus (vastasuuntaan) pienentää.
	_restore(orbit_save)
	G.set_warp(0)
	rel = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
	var v0 := Flight.norm(rel.v)
	pro = Flight.scale(rel.v, 1.0 / v0)
	_burn(pro, 0.3)
	var v1 := Flight.norm(Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel.v)
	_burn(Flight.scale(pro, -1.0), 0.6)
	var v2 := Flight.norm(Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel.v)
	check("kaasu kasvattaa nopeutta ja jarrutus pienentää (%s → %s → %s)" % [Fmt.num(v0, 2), Fmt.num(v1, 2), Fmt.num(v2, 2)],
		absf(v1 - v0 - 0.3) < 0.02 and absf(v2 - v0 + 0.3) < 0.03)
	# Polton aikana kiihdytys enintään 10×, ja Δv lasketaan simulaation ajasta.
	_restore(orbit_save)
	G.set_warp(3)
	var f0: float = G.state.fuel
	G.manual_thrust(pro, 1.0, 0.1)
	G.manual_thrust(pro, 0.0, 0.0)
	check("polton aikana kiihdytys 10×", G.warp_index() == G.MANUAL_WARP and absf(f0 - float(G.state.fuel) - float(G.MANUAL_ACCEL) * 1.0) < 1e-9)
	# Marsin kiertoradalla nokka kohti Marsia ja täysi kaasu 10×:llä: alus laskeutuu ja törmää pintaan.
	_restore(orbit_save)
	G.state.location = "Mars"
	G.state.orbit = {"epoch": G.sim_now(), "arg": 0.0}
	G.set_warp(1)
	var mars_alt := func() -> float:
		return Flight.norm(Flight.parking_state("Mars", G.sim_now(), G.state.orbit).rel.r) - float(Flight.orbit_of("Mars").radiusKm)
	var a0: float = mars_alt.call()
	for i in 600: # 10 s oikeaa aikaa
		var rm: Dictionary = Flight.parking_state("Mars", G.sim_now(), G.state.orbit).rel
		G.manual_thrust(Flight.scale(rm.r, -1.0 / Flight.norm(rm.r)), 1.0, 1.0 / 60.0)
		G.fake_real_ms += 1000.0 / 60.0
		G.tick()
	G.manual_thrust(pro, 0.0, 0.0)
	var a1: float = mars_alt.call()
	var mars_hit := false
	for i in 1200:
		G.fake_real_ms += 100.0
		G.tick()
		if G.state.get("destroyed") != null:
			mars_hit = true
			break
	check("Marsia kohti poltettaessa korkeus laskee (%s → %s km) ja alus törmää" % [Fmt.num(a0), Fmt.num(a1)], a1 < a0 - 20.0 and mars_hit
		and String(G.state.destroyed.text).contains("Marsin"))
	# Nokka kohti Maata ja kaasua: perikeskus pinnan alle ja törmäys.
	_restore(orbit_save)
	G.set_warp(0)
	rel = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
	_burn(Flight.scale(rel.r, -1.0 / Flight.norm(rel.r)), 0.6)
	rel2 = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
	check("poltto kohti planeettaa laskee perikeskuksen pinnan alle", float(Flight.orbit_shape("Maa", rel2.r, rel2.v).peri) < 0.0)
	G.set_warp(5)
	G.tick()
	check("pinnan lähestyessä kiihdytys rajataan", G.warp_index() <= 2)
	var crashed := false
	for i in 3000:
		G.fake_real_ms += 100.0
		G.tick()
		if G.state.get("destroyed") != null:
			crashed = true
			break
	check("alus törmää Maan pintaan", crashed and String(G.state.destroyed.text).contains("pintaan"))
	_restore(orbit_save)


## Kaikki planeetat ja kuut (#57): kiertoradalla nokka kohti kappaletta ja täysi kaasu 10×:llä vie aluksen
## matalammalle kuin ilman kaasua, ja kun kaasua pidetään, kunnes rata leikkaa pinnan, alus törmää.
func _manual_all_bodies(orbit_save: String) -> void:
	var bodies: Array[String] = []
	for n: String in Planets.NAMES:
		bodies.append(n)
	for n: String in Flight.MOONS:
		bodies.append(n)
	var bad: PackedStringArray = []
	var crashed: PackedStringArray = []
	for name: String in bodies:
		_restore(orbit_save)
		G.state.location = name
		G.state.lowOrbit = null
		# Soikealla radalla (kaasujättiläiset) aloitetaan apokeskuksesta: perikeskuksessa kohti planeettaa suunnattu
		# poltto lisää energiaa mutta ei pyörimismäärää, joten rata pyöristyy ja perikeskus nousee (oikea fysiikka).
		var ob: Dictionary = Flight.orbit_of(name)
		var half := Flight.orbit_period(name) * 500.0 if float(ob.apoKm) > float(ob.periKm) * 1.5 else 0.0
		var o0 := {"epoch": G.sim_now() - half, "arg": 0.0}
		G.state.orbit = o0
		G.state.fuel = 14.0
		G.set_warp(1)
		var R: float = Flight.orbit_of(name).radiusKm
		var t0: float = G.sim_now()
		var burns := 0
		while burns < 6000 and G.state.get("destroyed") == null and G.state.location == name:
			var rel: Dictionary = Flight.parking_state(name, G.sim_now(), G.state.orbit).rel
			if Flight.is_free_orbit(G.state.orbit) and float(Flight.orbit_shape(name, rel.r, rel.v).peri) < 0.0:
				break
			# Kohti kappaletta; soikealla radalla 10 s jälkeen jarrutus (menosuuntaa vastaan), koska Jupiterin
			# painovoimakuopassa pelkkä poltto kohti planeettaa venyttää radan pakoradaksi ennen kuin se leikkaa pinnan.
			var d := Flight.scale(rel.r, -1.0 / Flight.norm(rel.r))
			if half > 0.0 and burns >= 600:
				d = Flight.scale(rel.v, -1.0 / Flight.norm(rel.v))
			G.manual_thrust(d, 1.0, 1.0 / 60.0)
			G.fake_real_ms += 1000.0 / 60.0
			G.tick()
			burns += 1
			if burns == 600 and G.state.get("destroyed") == null:
				# 10 s kaasua: korkeus ja pystynopeus pienemmät kuin samalla hetkellä ilman kaasua.
				var now: float = G.sim_now()
				var r1: Dictionary = Flight.parking_state(name, now, G.state.orbit).rel
				var r0: Dictionary = Flight.parking_state(name, now, o0).rel
				if not (Flight.norm(r1.r) < Flight.norm(r0.r) and CockpitState.vertical_speed(r1.r, r1.v) < CockpitState.vertical_speed(r0.r, r0.v)):
					bad.append(name)
		G.manual_thrust(PackedFloat64Array([1, 0, 0]), 0.0, 0.0)
		if G.state.get("destroyed") == null and G.state.location == name:
			for i in 80000:
				# Pelaaja nostaa kiihdytyksen; peli pienentää sen pinnan lähestyessä.
				if G.warp_index() < 3:
					G.set_warp(3)
				G.fake_real_ms += 100.0
				G.tick()
				if G.state.get("destroyed") != null or G.state.location != name:
					break
		if G.state.get("destroyed") != null and String(G.state.destroyed.text).contains(Fmt.gen(name)):
			crashed.append(name)

	check("kaikilla kohteilla kaasu kohti pintaa laskee korkeutta%s" % (": " + ", ".join(bad) if not bad.is_empty() else ""), bad.is_empty())
	check("törmäys kaikkiin kohteisiin (%d/%d: %s)" % [crashed.size(), bodies.size(), ", ".join(crashed)], crashed.size() == bodies.size())
	_restore(orbit_save)


## Moottoriääni ja Työntö seuraavat kaasun prosentteja, nollalla hiljaista; tyhjällä tankilla ei polttoa (#57).
func _manual_sound_and_fuel(orbit_save: String) -> void:
	_restore(orbit_save)
	G.set_warp(0)
	var dir := PackedFloat64Array([1.0, 0.0, 0.0])
	var ok := true
	for p: float in [0.25, 0.6, 1.0]:
		G.manual_thrust(dir, p, 0.1)
		var cs := CockpitState.make()
		var lv := GameSound.levels(cs, false)
		ok = ok and absf(float(cs.thrust) - p) < 1e-6 and absf(float(lv.burn) - p) < 1e-6
	G.manual_thrust(dir, 0.0, 0.0)
	var quiet := GameSound.levels(CockpitState.make(), false)
	check("polttoääni ja työntö kaasun mukaan, nollalla hiljaista", ok and float(quiet.burn) == 0.0)
	G.state.fuel = 0.0
	var log_n: int = G.state.log.size()
	var burned: bool = G.manual_thrust(dir, 1.0, 0.5)
	check("tyhjällä tankilla ei polttoa eikä polttoääntä", not burned and G.manual_throttle == 0.0
		and float(GameSound.levels(CockpitState.make(), false).burn) == 0.0)
	G.manual_thrust(dir, 0.0, 0.0)
	check("nollapolttoa ei kirjata", G.state.log.size() == log_n)
	_restore(orbit_save)


## Lento ilmakehässä (#57): 60 km:ssä laskeva alus nousee, kun nokka nostetaan 15° menosuunnan yläpuolelle
## (nostovoima), mutta ilman nostovoimaa se jatkaa putoamista. Ilmakehässä kiihdytys enintään 10×.
func _air_flight(orbit_save: String) -> void:
	var results := {}
	for mode: String in ["nokka ylös", "nokka menosuuntaan"]:
		_restore(orbit_save)
		var r := PackedFloat64Array([6371.0 + 60.0, 0.0, 0.0])
		var v := PackedFloat64Array([-0.4, 7.0, 0.0])
		G.state.orbit = {"epoch": G.sim_now(), "arg": 0.0, "rel": {"r": r, "v": v}}
		G.set_warp(1)
		var heat := 0.0
		var q := 0.0
		for i in 300: # 30 s
			var rel: Dictionary = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
			var vh := Flight.scale(rel.v, 1.0 / Flight.norm(rel.v))
			var up := Flight.scale(rel.r, 1.0 / Flight.norm(rel.r))
			G.manual_nose = Flight.add(Flight.scale(vh, cos(0.26)), Flight.scale(up, sin(0.26))) if mode == "nokka ylös" else PackedFloat64Array()
			if i == 150:
				G.set_warp(3) # pelaaja yrittää kiihdyttää: ilmakehässä enintään 10×
			G.fake_real_ms += 100.0
			G.tick()
			heat = maxf(heat, G.atmo_heat)
			q = maxf(q, G.atmo_q)
			if G.state.get("destroyed") != null:
				break
		var rel2: Dictionary = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
		results[mode] = {"vsp": CockpitState.vertical_speed(rel2.r, rel2.v), "alt": Flight.norm(rel2.r) - 6371.0, "warp": G.warp_index(),
			"heat": heat, "q": q}
	G.manual_nose = PackedFloat64Array()
	var a: Dictionary = results["nokka ylös"]
	var b: Dictionary = results["nokka menosuuntaan"]
	check("ilmakehässä nokka ylös: alus nousee (pystynopeus %s km/s)" % Fmt.num(a.vsp, 2), float(a.vsp) > 0.0)
	check("ilman nostovoimaa alus putoaa (%s km)" % Fmt.num(b.alt, 1), float(b.vsp) < 0.0 and float(b.alt) < float(a.alt))
	check("ilmakehässä kiihdytys enintään 10×, plasma ja ilmanpaine", int(a.warp) <= G.MANUAL_WARP and float(a.q) > 1000.0 and float(a.heat) > 0.0)
	# Maailman tehokkain alus (#58): 10 %:n kaasu kumoaa painovoiman, ja ilmakehässä moottori hengittää ilmaa.
	_restore(orbit_save)
	var ra := PackedFloat64Array([6371.0 + 10.0, 0.0, 0.0])
	var va := PackedFloat64Array([0.0, 0.25, 0.0])
	G.state.orbit = {"epoch": G.sim_now(), "arg": 0.0, "rel": {"r": ra, "v": va}}
	G.set_warp(0)
	G.fake_real_ms += 100.0
	G.tick()
	var fuel0: float = G.state.fuel
	check("10 %%:n kaasu vähintään 1 g (%s m/s²)" % Fmt.num(G.manual_accel() * 100.0, 1), G.manual_accel() * 0.1 >= 0.0098 - 1e-9)
	for i in 10:
		G.manual_thrust(PackedFloat64Array([1.0, 0.0, 0.0]), 1.0, 0.1)
	G.manual_thrust(PackedFloat64Array([1.0, 0.0, 0.0]), 0.0, 0.0)
	var used_air: float = fuel0 - float(G.state.fuel)
	check("ilmakehässä polttoainetta kuluu vain %d %% (%s km/s)" % [roundi(G.AIR_FUEL_FACTOR * 100.0), Fmt.num(used_air, 4)],
		absf(used_air - G.MANUAL_ACCEL * G.AIR_FUEL_FACTOR) < 1e-6)
	var rel_a: Dictionary = Flight.parking_state("Maa", G.sim_now(), G.state.orbit).rel
	check("työntö 1 s × 10 g nostaa nopeutta ylöspäin", float(rel_a.v[0]) > 0.09)
	_restore(orbit_save)
