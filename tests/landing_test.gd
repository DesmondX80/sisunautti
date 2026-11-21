extends TestCase
## Laskeutuminen Kuuhun ja nousu takaisin (#45) ilman käyttöliittymää: pintakoordinaatit, automaattilaskun
## suunnitelma ja Δv (Apollo-luokkaa, napa-alue kallis), vaiheet (laskupoltto, liuku, laskeutumispoltto, kosketus)
## ja niiden jatkuvuus, pinnalla oleminen ja tallennus, nousu kiertoradalle, käsin laskeutuminen (pehmeä ja kova
## kosketus), nousu käsin ja ohjauksen otto laskeutumispolton aikana.
##   godot --headless -- --landingtest

const START_REAL := 1794614400000.0

var G: Node
var events: Array[String] = []


func _ready() -> void:
	G = Game
	G.fake_real_ms = START_REAL
	for sig: String in ["landing_burn", "powered_descent", "touchdown", "surface_liftoff", "orbit_reached", "ship_destroyed"]:
		var name := sig
		G.connect(sig, func(_a: Variant = null) -> void: events.append(name))
	_coordinates()
	_plans()
	_auto_landing()
	_save_load()
	_ascent()
	_manual()
	_take_control()
	G.fake_real_ms = -1.0
	DirAccess.remove_absolute(G.TEST_SAVE_PATH)
	finish()


## Kuun kiertoradalla (pysäköintirata) hetkellä START_REAL + 1 vrk.
func _in_moon_orbit() -> void:
	G.new_game()
	var t: float = START_REAL + 86400000.0
	G.fake_real_ms = t
	G.state.pad = false
	G.state.location = "Kuu"
	G.state.orbit = {"epoch": t, "arg": 0.3}
	G.state.simTime = t
	G.state.realTime = t
	G.state.explored.append("Kuu")
	G.load_game_from_state()


func advance(ms: float, step: float = 100.0) -> void:
	var end: float = G.fake_real_ms + ms
	while G.fake_real_ms < end:
		G.fake_real_ms = minf(end, G.fake_real_ms + step)
		G.tick()


## Ajaa kelloa kiihdyttäen (peli pienentää kiihdytyksen ennen tapahtumia), kunnes ehto täyttyy.
func run_until(cond: Callable, max_steps: int = 200000) -> bool:
	var n := 0
	while not cond.call() and n < max_steps:
		# 100×: 0,1 s:n askel on 10 s pelin aikaa (pelissä kiihdytys pienenee ennen tapahtumia ruutu kerrallaan).
		if G.warp_index() < 2:
			G.set_warp(2)
		G.fake_real_ms += 100.0
		G.tick()
		n += 1
	return cond.call()


func _coordinates() -> void:
	var t := START_REAL
	var d := Landing.site_dir("Kuu", 20.0, 30.0, t)
	var ll := Landing.lat_lon("Kuu", Flight.scale(d, 1737.4), t)
	check("leveys ja pituus säilyvät", absf(ll.x - 20.0) < 1e-6 and absf(ll.y - 30.0) < 1e-6)
	var to_earth := Flight.scale(PackedFloat64Array(Flight.moon_rel("Kuu", t).r), -1.0)
	var near := Landing.site_dir("Kuu", 0.0, 0.0, t)
	check("pituusaste 0 osoittaa Maahan", Flight.dot(near, Flight.scale(to_earth, 1.0 / Flight.norm(to_earth))) > 0.9999)
	var s := Landing.surface_rel("Kuu", 0.0, 0.0, t)
	check("pinta pyörii kuun mukana (noin 4,6 m/s)", absf(Flight.norm(s.v) * 1000.0 - 4.6) < 0.2)
	var later := Landing.site_dir("Kuu", 0.0, 0.0, t + 86400000.0)
	check("lähipuoli pysyy Maahan päin", Flight.dot(later, Flight.scale(PackedFloat64Array(Flight.moon_rel("Kuu", t + 86400000.0).r), -1.0 / 384400.0)) > 0.9999)


func _plans() -> void:
	var t := START_REAL
	var orbit := {"epoch": t, "arg": 0.0}
	var a11 := Landing.plan_descent("Kuu", orbit, 0.674, 23.473, t)
	check("Apollo 11 -laskeutuminen: Δv %s (Apollo noin 2,1 km/s)" % Fmt.dv(a11.dvTotal), float(a11.dvTotal) > 1.9 and float(a11.dvTotal) < 2.3)
	check("laskupoltto pieni (%s)" % Fmt.dv(a11.dvDoi), float(a11.dvDoi) > 0.015 and float(a11.dvDoi) < 0.03)
	check("vaiheet järjestyksessä", float(a11.tDoi) >= t + Landing.LEAD_MS and float(a11.tPdi) > float(a11.tDoi) and float(a11.tHover) > float(a11.tPdi) and float(a11.tLand) > float(a11.tHover))
	var coast_min := (float(a11.tPdi) - float(a11.tDoi)) / 60000.0
	var pd_min := (float(a11.tLand) - float(a11.tPdi)) / 60000.0
	check("liuku noin tunti (%s min), laskeutumispoltto 8–15 min (%s min)" % [Fmt.num(coast_min), Fmt.num(pd_min, 1)], coast_min > 50.0 and coast_min < 65.0 and pd_min > 8.0 and pd_min < 15.0)
	var pole := Landing.plan_descent("Kuu", orbit, -89.54, 0.0, t)
	check("napa-alue kallis: Δv %s (ratatason muutos %d°)" % [Fmt.dv(pole.dvTotal), roundi(pole.planeDeg)], float(pole.dvTotal) > float(a11.dvTotal) + 1.0)
	check("vapaalta radalta ei automaattilaskua", Landing.plan_descent("Kuu", {"epoch": t, "rel": {"r": [1837.4, 0, 0], "v": [0, 1.63, 0]}}, 0.0, 0.0, t).is_empty())
	check("Marsiin ei vielä laskeuduta", Landing.plan_descent("Mars", null, 0.0, 0.0, t).is_empty())
	var asc := Landing.plan_ascent("Kuu", 0.674, 23.473, t)
	check("nousu: Δv %s (Apollo noin 1,9 km/s), kesto %s min" % [Fmt.dv(asc.dv), Fmt.num((float(asc.t1) - float(asc.t0)) / 60000.0, 1)],
		float(asc.dv) > 1.7 and float(asc.dv) < 2.1 and float(asc.t1) - float(asc.t0) > 300000.0 and float(asc.t1) - float(asc.t0) < 600000.0)


func _auto_landing() -> void:
	_in_moon_orbit()
	var fuel0: float = G.state.fuel
	check("automaattilasku alkaa", G.begin_landing(0) and G.state.landing != null)
	var l: Dictionary = G.state.landing
	check("reittihaku estetty laskeutumisen aikana", (func() -> bool:
		G.begin_search("Mars")
		return G.target == "").call())
	check("laskupoltto", run_until(func() -> bool: return events.has("landing_burn")) and Flight.is_free_orbit(G.state.orbit))
	check("laskupoltto kulutti polttoainetta", absf(float(G.state.fuel) - (fuel0 - float(l.dvDoi))) < 1e-9)
	var rel: Dictionary = Flight.parking_state("Kuu", G.sim_now(), G.state.orbit).rel
	var shape := Flight.orbit_shape("Kuu", rel.r, rel.v)
	check("ellipsin perikeskus 15 km (%s km)" % Fmt.num(shape.peri, 2), absf(float(shape.peri) - Landing.PDI_ALT_KM) < 0.05)
	check("laskeutumispoltto alkaa perikeskuksessa", run_until(func() -> bool: return events.has("powered_descent")))
	var t_pdi: float = l.tPdi
	var coast: Dictionary = Flight.parking_state("Kuu", t_pdi, Landing.doi_orbit("Kuu", l)).rel
	var desc := Landing.rel_state("Kuu", {"descent": l}, t_pdi)
	check("paikka jatkuu laskeutumispolttoon (ero %s km)" % Fmt.num(Flight.norm(Flight.sub(coast.r, desc.r)), 3), Flight.norm(Flight.sub(coast.r, desc.r)) < 0.5)
	check("nopeus jatkuu (ero %s m/s)" % Fmt.num(absf(Flight.norm(coast.v) - Flight.norm(desc.v)) * 1000.0), absf(Flight.norm(coast.v) - Flight.norm(desc.v)) < 0.03)
	var alts := []
	var fuel_mid := 0.0
	while G.state.location == "Kuu" and not G.is_landed() and alts.size() < 100000:
		advance(500)
		if G.is_landed():
			break
		var r: Dictionary = Flight.parking_state("Kuu", G.sim_now(), G.state.orbit).rel
		alts.append(Flight.norm(r.r) - 1737.4)
		if fuel_mid == 0.0 and G.sim_now() > (float(l.tPdi) + float(l.tLand)) / 2.0:
			fuel_mid = G.state.fuel
	var falling := true
	for i in range(1, alts.size()):
		falling = falling and float(alts[i]) <= float(alts[i - 1]) + 1e-6
	check("korkeus laskee tasaisesti pintaan (%d näytettä)" % alts.size(), falling and alts.size() > 10)
	check("polttoaine kuluu polton aikana", fuel_mid < fuel0 - float(l.dvDoi) and fuel_mid > fuel0 - float(l.dvTotal))
	check("kosketus pintaan", G.is_landed() and events.has("touchdown"))
	check("polttoainetta kului laskeutumisen Δv", absf(float(G.state.fuel) - (fuel0 - float(l.dvTotal))) < 1e-6)
	var sf: Dictionary = G.state.orbit.surface
	check("oikea paikka (%s)" % sf.site, absf(float(sf.lat) - 0.674) < 1e-9 and absf(float(sf.lon) - 23.473) < 1e-9)
	var rs: Dictionary = Flight.parking_state("Kuu", G.sim_now(), G.state.orbit).rel
	check("alus pinnalla", absf(Flight.norm(rs.r) - 1737.4) < 1e-6)
	check("lokikirjassa laskeutuminen", String(G.state.log.filter(func(e: Dictionary) -> bool: return String(e.text).begins_with("Laskeutuminen:"))[-1].text).contains("Apollo 11"))
	check("kello pysähtyi kosketukseen", G.warp_index() == 0)
	G.begin_search("Mars")
	check("pinnalta ei haeta reittejä, mutta kaasulla voi nousta", G.target == "" and G.can_manual_burn())


func _save_load() -> void:
	G.save_game()
	G.state = {}
	G.load_game()
	check("pinnalla oleminen tallentuu", G.is_landed() and G.state.orbit.surface.site == Landing.SITES[0][0])


func _ascent() -> void:
	var fuel0: float = G.state.fuel
	events.clear()
	check("nousu alkaa", G.start_surface_ascent() and events.has("surface_liftoff"))
	var a: Dictionary = G.state.orbit.ascent
	check("nousu kulutti Δv:n", absf(float(G.state.fuel) - (fuel0 - float(a.dv))) < 1e-9)
	check("kiertoradalla nousun jälkeen", run_until(func() -> bool: return events.has("orbit_reached")))
	var rel: Dictionary = Flight.parking_state("Kuu", G.sim_now(), G.state.orbit).rel
	check("100 km:n pysäköintiradalla", not Landing.is_special(G.state.orbit) and absf(Flight.norm(rel.r) - Flight.orbit_of("Kuu").periKm) < 0.5)
	check("lähtö pinnalta jatkuu radalle (nopeus %s km/s)" % Fmt.num(Flight.norm(rel.v), 3), absf(Flight.norm(rel.v) - sqrt(4902.8 / 1837.4)) < 0.01)


## Vapaa rata aivan pinnan yllä annetulla pysty- ja vaakanopeudella (m/s).
func _drop(vs_ms: float, vh_ms: float) -> void:
	_in_moon_orbit()
	var t: float = G.sim_now()
	var s := Landing.surface_rel("Kuu", 10.0, 20.0, t, 0.001)
	var up := Flight.scale(s.r, 1.0 / Flight.norm(s.r))
	var east := Flight.cross(Flight.vec(0, 0, 1), up)
	east = Flight.scale(east, 1.0 / Flight.norm(east))
	var v := Flight.add(s.v, Flight.add(Flight.scale(up, -vs_ms / 1000.0), Flight.scale(east, vh_ms / 1000.0)))
	G.state.orbit = {"epoch": t, "arg": 0.0, "rel": {"r": s.r, "v": v}}
	G._free_prev = {}
	events.clear()
	advance(3000, 20.0)


func _manual() -> void:
	_drop(1.5, 0.5)
	check("pehmeä kosketus käsin: laskeutuminen", G.is_landed() and events.has("touchdown"))
	check("lokikirjaan käsin laskeutuminen", String(G.state.log[-1].text).begins_with("Laskeutuminen käsin") or G.state.log.any(func(e: Dictionary) -> bool: return String(e.text).begins_with("Laskeutuminen käsin")))
	# Nousu käsin: kaasu ylöspäin nostaa aluksen vapaalle radalle.
	var rel: Dictionary = Flight.parking_state("Kuu", G.sim_now(), G.state.orbit).rel
	var up := Flight.scale(rel.r, 1.0 / Flight.norm(rel.r))
	for i in 20:
		G.manual_thrust(up, 0.3, 0.05)
		advance(50, 50.0)
	G.manual_thrust(up, 0.0, 0.05)
	check("nousu käsin pinnalta", Flight.is_free_orbit(G.state.orbit) and events.has("surface_liftoff"))
	var r2: Dictionary = Flight.parking_state("Kuu", G.sim_now(), G.state.orbit).rel
	check("alus nousee", Flight.norm(r2.r) - 1737.4 > 0.002)
	_drop(9.0, 0.0)
	check("kova kosketus tuhoaa aluksen", G.state.destroyed != null and events.has("ship_destroyed") and String(G.state.destroyed.text).contains("pystynopeudella"))
	_drop(1.0, 8.0)
	check("liian suuri vaakanopeus tuhoaa aluksen", G.state.destroyed != null)


func _take_control() -> void:
	_in_moon_orbit()
	G.begin_landing(0)
	run_until(func() -> bool: return G.state.landing != null and G.state.landing.phase == "descent")
	G.set_warp(0)
	advance(60000)
	var before: Dictionary = Flight.parking_state("Kuu", G.sim_now(), G.state.orbit).rel
	G.take_landing_control()
	var after: Dictionary = Flight.parking_state("Kuu", G.sim_now(), G.state.orbit).rel
	check("ohjaus käsiin: vapaa rata samasta tilasta", G.state.landing == null and Flight.is_free_orbit(G.state.orbit)
		and Flight.norm(Flight.sub(before.r, after.r)) < 1e-6 and G.can_manual_burn())
