extends TestCase
## Ratamekaniikan testit (siirretty web/test/game.test.mjs:stä). astronomy-enginen vertailuarvot ovat tiedostossa
## tests/data/orbit_reference.json (kenttä astronomy; tools/make_orbit_reference.mjs).
##   godot --headless -- --orbittest

const DAY := Flight.DAY_MS
const AU := Flight.AU_KM
const START := 1794614400000.0 # 2026-11-14T00:00:00Z
const LIFTOFF := 1798797600000.0 # 2027-01-01T10:00:00Z

var F := Flight


func _ready() -> void:
	var ref: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/orbit_reference.json"))
	_kepler()
	_positions(ref.astronomy)
	_propagation()
	_lambert()
	_hohmann_and_mars_window()
	_soi()
	_window_search()
	_cockpit_view()
	_arrival_and_drift()
	_course_corrections()
	_assists_moons_ships()
	_launch()
	_injection_and_orbits()
	_aerobrake()
	finish()


func sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return F.sub(a, b)


func close(a: PackedFloat64Array, b: PackedFloat64Array, tol: float) -> bool:
	return F.norm(sub(a, b)) / F.norm(b) < tol


func angle_gap(a: float, b: float) -> float:
	return absf(fmod(fmod(a - b + PI, 2.0 * PI) + 2.0 * PI, 2.0 * PI) - PI)


func _kepler() -> void:
	var ok := true
	for e: float in [0.0, 0.2, 0.9]:
		for M: float in [0.1, 1.0, 3.0, 5.0]:
			var E := Planets.eccentric_anomaly(M, e)
			var d := E - e * sin(E) - M
			ok = ok and absf(atan2(sin(d), cos(d))) < 1e-10
	check("ratkaisee Keplerin yhtälön", ok)


func _positions(astro: Array) -> void:
	# Standishin pitkän aikavälin alkiot pitävät sijainnit alle 15 kaariminuutin tarkkuudella vuosina 1850–2150.
	var worst := 0.0
	var vel_ok := true
	for c: Dictionary in astro:
		var p := Planets.helio(c.name, c.time)
		var want: PackedFloat64Array = c.pos
		worst = maxf(worst, F.norm(sub(p, want)) / F.norm(want) * 180.0 / PI * 60.0)
		if int(c.time) == 1794614400000:
			vel_ok = vel_ok and close(Planets.helio_state(c.name, c.time).vel, c.vel, 0.01)
	check("sijainnit vastaavat astronomy-enginen laskemia (suurin ero %.2f′)" % worst, worst < 15.0)
	check("nopeusvektorit vastaavat astronomy-enginen laskemia", vel_ok)
	check("Maan ratanopeus noin 29,8 km/s", absf(F.norm(F.planet_state("Maa", START).v) - 29.8) < 0.5)


func _propagation() -> void:
	var r0 := F.vec(AU, 0, 0)
	var ok := true
	for c: Array in [
		[F.vec(0, 30, 1), 200 * 86400.0], # lähes ympyrärata
		[F.vec(5, 38, 2), 3 * 365 * 86400.0], # venynyt ellipsi
		[F.vec(0, 38, 0), 40 * 365 * 86400.0], # monta kierrosta
		[F.vec(10, 45, 3), 5 * 365 * 86400.0], # hyperbeli
		[F.vec(0, 30, 0), -150 * 86400.0], # taaksepäin
	]:
		var a := F.invariants(r0, c[0])
		var s := F.propagate(r0, c[0], c[1])
		var b := F.invariants(s.r, s.v)
		ok = ok and absf(b.energy / a.energy - 1.0) < 1e-9 and close(b.h, a.h, 1e-9)
		# Eteneminen takaisin palauttaa alkutilan.
		ok = ok and close(F.propagate(s.r, s.v, -c[1]).r, r0, 1e-8)
	check("radan eteneminen säilyttää energian ja liikemäärämomentin", ok)
	var vc := sqrt(F.MU_SUN / AU)
	var period := 2.0 * PI * sqrt(AU * AU * AU / F.MU_SUN)
	check("ympyrärata neljänneskierroksen jälkeen", close(F.propagate(r0, F.vec(0, vc, 0), period / 4.0).r, F.vec(0, AU, 0), 1e-9))


func _lambert() -> void:
	var r1 := F.vec(AU, 0, 0)
	var ok := true
	for c: Array in [
		[F.vec(0, 1.5 * AU, 0.05 * AU), 150.0],
		[F.vec(-1.2 * AU, 0.3 * AU, 0), 300.0],
		[F.vec(0.2 * AU, -1.4 * AU, 0), 400.0], # pitkä kaari
		[F.vec(0.5 * AU, 0.5 * AU, 0), 20.0], # hyperbolinen pikalento
		[F.vec(-5 * AU, 1 * AU, 0.1 * AU), 1000.0],
	]:
		var sol := F.lambert(r1, c[0], c[1] * 86400.0)
		if sol.is_empty():
			ok = false
			continue
		var end := F.propagate(r1, sol.v1, c[1] * 86400.0)
		ok = ok and close(end.r, c[0], 1e-7) and close(end.v, sol.v2, 1e-7)
		# Rata kulkee planeettojen suuntaan.
		ok = ok and F.cross(r1, sol.v1)[2] > 0.0
	check("Lambertin ratkaisu toistaa annetun loppupisteen", ok)


func _hohmann_and_mars_window() -> void:
	var h := F.hohmann(AU, 1.524 * AU)
	check("Maa→Mars Hohmann noin 259 vrk", absf(h.tof / 86400.0 - 259.0) < 0.5)
	check("lähtö LEO:sta noin 3,6 km/s", absf(F.burn_dv("Maa", h.vinfDep) - 3.6) < 0.05)
	var sol := F.lambert(F.vec(AU, 0, 0), F.vec(-1.524 * AU, 1e-3 * AU, 0), h.tof)
	check("lähes 180° Lambert vastaa Hohmannia", absf(F.norm(sol.v1) - sqrt(F.MU_SUN / AU) - h.vinfDep) < 0.005)
	var best := {}
	var d := 1788220800000.0 # 2026-09-01
	while d < 1803859200000.0: # 2027-03-01
		var tof := 150.0
		while tof <= 400.0:
			var tr := F.transfer("Maa", "Mars", d, tof)
			if not tr.is_empty() and (best.is_empty() or tr.dvDep < best.dvDep):
				best = tr
			tof += 10.0
		d += 5 * DAY
	check("vuoden 2026 Mars-ikkunan Δv LEO:sta 3,4–4 km/s", best.dvDep > 3.4 and best.dvDep < 4.0)
	check("halvin lähtö loka–tammikuussa", best.depart > 1790812800000.0 and best.depart < 1801440000000.0)
	var end := F.ship_state(best, best.arrive)
	check("alus saapuu Marsin luo siirtoradan päässä", F.norm(sub(end.r, best.r2)) < 1000.0)


func _soi() -> void:
	check("Maan vaikutuspiiri", absf(F.body("Maa").soiKm / 1e6 - 0.925) < 0.05)
	check("Jupiterin vaikutuspiiri", absf(F.body("Jupiter").soiKm / 1e6 - 48.2) < 0.5)
	check("Marsin vaikutuspiiri", absf(F.body("Mars").soiKm / 1e6 - 0.577) < 0.05)


func _window_search() -> void:
	var search := WindowSearch.new("Maa", "Mars", START)
	var last := -1.0
	var increasing := true
	while not search.done:
		var p := search.step()
		increasing = increasing and p >= last
		last = p
	check("haun edistyminen kasvaa ja päättyy 1:een", increasing and last == 1.0)
	var r := search.result
	var cheapest: Dictionary = r[0]
	var faster: Dictionary = r[1]
	check("halvin vaihtoehto", cheapest.kind == "cheapest" and cheapest.dvTotal < 6.5 and cheapest.fuelOk)
	check("nopeampi vaihtoehto", faster.kind == "faster" and faster.arrive - faster.depart <= 0.7 * (cheapest.arrive - cheapest.depart) + DAY
		and faster.dvTotal > cheapest.dvTotal)
	var in_range := true
	for o: Dictionary in r:
		in_range = in_range and o.depart >= START and o.depart <= START + 731 * DAY
	check("lähdöt hakuvälillä", in_range)
	var nep: Dictionary = F.find_windows("Maa", "Neptunus", START)[0]
	check("Neptunuksen lentoaika alle 36 v ja polttoaine riittää", (nep.arrive - nep.depart) / DAY / 365.25 < 36.0 and nep.fuelOk)
	var poor := F.find_windows("Maa", "Jupiter", START, {"fuel": 5.0})
	check("vähällä polttoaineella yksikään ei riitä", poor.all(func(o: Dictionary) -> bool: return not o.fuelOk))
	check("lentoaika kellona", F.fmt_duration(123 * DAY + 4 * 3600000 + 12 * 60000 + 33500) == "123 vrk 04:12:33")
	check("negatiivinen kesto", F.fmt_duration(-5) == "0 vrk 00:00:00")
	# Haku ruutubudjetilla: yksi run()-kutsu ei laske koko hakua.
	var framed := WindowSearch.new("Maa", "Mars", START, {"assists": false})
	var p1 := framed.run(5.0)
	check("ruutubudjetilla haku etenee osissa", p1 > 0.0 and not framed.done)


func _mars_flight() -> Dictionary:
	return F.find_windows("Maa", "Mars", START)[0]


func _cockpit_view() -> void:
	var tr := _mars_flight()
	var dep := F.norm(sub(F.ship_view(tr, tr.depart).r, F.planet_state("Maa", tr.depart).r))
	var arr := F.norm(sub(F.ship_view(tr, tr.arrive).r, F.planet_state("Mars", tr.arrive).r))
	check("lähtöpoltto pysäköintiradan korkeudella", absf(dep - F.body("Maa").periKm) < 1.0)
	check("jarrutuspoltto pysäköintiradan korkeudella", absf(arr - F.body("Mars").periKm) < 1.0)
	# Lähtö- ja saapumishyperbelit: perikeskuksessa nopeus kohtisuorassa säteeseen ja suuruus √(v∞² + 2μ/r).
	var vinf_dep := sub(tr.v1, F.planet_state("Maa", tr.depart).v)
	var dv := F.ship_view(tr, tr.depart)
	var rel := sub(dv.r, F.planet_state("Maa", tr.depart).r)
	var rel_v := sub(dv.v, F.planet_state("Maa", tr.depart).v)
	var mu: float = F.body("Maa").mu
	var peri: float = F.body("Maa").periKm
	check("lähtöperikeskuksen nopeus", absf(F.norm(rel_v) - sqrt(F.dot(vinf_dep, vinf_dep) + 2.0 * mu / peri)) < 1e-6
		and absf(F.dot(rel, rel_v)) < 1e-3 * F.norm(rel) * F.norm(rel_v))
	var e := 1.0 + peri * F.dot(vinf_dep, vinf_dep) / mu
	var want := atan2(vinf_dep[1], vinf_dep[0]) - acos(-1.0 / e)
	check("lähtöpoltto samassa kohdassa kuin pysäköintiradan ruiskutushetki", absf(angle_difference(atan2(rel[1], rel[0]), want)) < 1e-6)
	var out := F.ship_view(tr, tr.depart + DAY)
	var out_rel := sub(out.v, F.planet_state("Maa", tr.depart + DAY).v)
	check("lähdön jälkeen alus etääntyy menosuuntaan", F.dot(sub(out.r, F.planet_state("Maa", tr.depart + DAY).r), out_rel) > 0.0)
	var near := F.norm(sub(F.ship_view(tr, tr.arrive - 60000.0).r, F.planet_state("Mars", tr.arrive - 60000.0).r))
	check("saapuminen on jatkuva", near > arr and near - arr < 50.0)
	var before := F.ship_view(tr, tr.depart - 30 * DAY)
	check("ennen laukaisua alus kulkee Maan mukana", absf(F.norm(sub(before.r, F.planet_state("Maa", tr.depart - 30 * DAY).r)) - dep) < 0.5)
	var mid: float = (tr.depart + tr.arrive) / 2.0
	check("keskellä lentoa näkymä on siirtorata", F.norm(sub(F.ship_view(tr, mid).r, F.ship_state(tr, mid).r)) == 0.0)
	# #41: lukemat näkymän paikasta kohteen pintaan; perillä pysäköintiradan korkeus, ei nolla.
	var alt: float = F.body("Mars").periKm - F.body("Mars").radiusKm
	check("pintaetäisyys perillä on pysäköintiradan korkeus", absf(F.surface_distance(F.ship_view(tr, tr.arrive).r, "Mars", tr.arrive) - alt) < 1.0)
	var mono := true
	var prev_d := INF
	for i in 200:
		var ti: float = tr.arrive - 3.0 * DAY * pow(1.0 - i / 200.0, 2.0)
		var di := F.surface_distance(F.ship_view(tr, ti).r, "Mars", ti)
		mono = mono and di <= prev_d + 1e-6 and di >= alt - 1.0
		prev_d = di
	check("kohde lähestyy näkymässä koko ajan pysäköintiradalle asti", mono)
	# Korjattu rata (useampi osa), joka osuu kohteeseen: saapumishyperbeli, näkymä ei pysähdy pysäköintiradan etäisyydelle.
	var mid_t: float = (tr.depart + tr.arrive) / 2.0
	var leg := F.ship_state(tr, mid_t)
	var fixed := tr.duplicate()
	fixed.legs = [{"t": tr.depart, "r": tr.r1, "v": tr.v1}, {"t": mid_t, "r": leg.r, "v": leg.v}]
	fixed = F.predict(fixed, mid_t)
	var fixed_mono := true
	prev_d = INF
	for i in 200:
		var ti: float = fixed.arrive - 3.0 * DAY * pow(1.0 - i / 200.0, 2.0)
		var di := F.surface_distance(F.ship_view(fixed, ti).r, "Mars", ti)
		fixed_mono = fixed_mono and di <= prev_d + 1e-6
		prev_d = di
	var t10: float = fixed.arrive - 600000.0
	check("korjatulla osuvalla radalla kohde lähestyy pysäköintiradalle", not fixed.miss and fixed_mono
		and F.surface_distance(F.ship_view(fixed, t10).r, "Mars", t10) > alt + 500.0
		and absf(F.surface_distance(F.ship_view(fixed, fixed.arrive).r, "Mars", fixed.arrive) - alt) < 1.0)
	check("pintaetäisyys ei ole negatiivinen", F.surface_distance(F.planet_state("Mars", mid_t).r, "Mars", mid_t) == 0.0)
	var days: float = (F.soi_exit(tr) - tr.depart) / DAY
	check("vaikutuspiiristä poistutaan 1–10 vrk:ssa", days > 1.0 and days < 10.0)
	check("vaikutuspiiriin saavutaan poistumisen jälkeen", F.soi_entry(tr) > F.soi_exit(tr))


func _arrival_and_drift() -> void:
	var s := F.parking_state("Maa", START)
	var r := F.norm(sub(s.r, F.planet_state("Maa", START).r))
	check("pysäköintiradan korkeus", r >= F.body("Maa").periKm - 1 and r <= F.body("Maa").apoKm + 1)
	check("matalan Maan kiertoradan nopeus noin 7,8 km/s", absf(F.norm(s.rel.v) - 7.79) < 0.05)
	var tr := _mars_flight()
	var e := F.ship_state(tr, tr.arrive)
	var drift := {"r": e.r, "v": e.v, "t": tr.arrive}
	check("Auringon kiertorata ei ole planeetta", not F.is_planet(drift))
	check("lähtötila Auringon kiertoradalta", F.norm(sub(F.departure_state(drift, tr.arrive).r, e.r)) < 1e-3)
	var options := F.find_windows(drift, "Jupiter", tr.arrive, {"fuel": 20.0})
	check("lentää Auringon kiertoradalta uuteen kohteeseen", options.size() > 0)
	var o: Dictionary = options[0]
	check("Auringon kiertoradalta lähtö on nopeuksien erotus", absf(o.dvDep - o.vinfDep) < 1e-10)
	check("Auringon kiertoradalta ei vaikutuspiiriä", F.soi_exit(o) == o.depart)
	check("näkymä ennen lähtöä Auringon kiertoradalla",
		F.norm(sub(F.ship_view(o, o.depart - DAY).r, F.departure_state(drift, o.depart - DAY).r)) < 1.0)
	var stats := F.flight_stats(tr)
	check("lennon pituus 350–650 milj. km", stats.km / 1e6 > 350 and stats.km / 1e6 < 650)
	check("huippunopeus lähdössä", absf(stats.maxSpeed - F.norm(tr.v1)) < 0.05)


func _course_corrections() -> void:
	var tr := _mars_flight()
	var mid: float = tr.depart + 60 * DAY
	var p := F.predict(tr, mid)
	check("ennuste vastaa suunniteltua lentoa", not p.miss and p.missKm < 1000 and absf(p.arrive - tr.arrive) < DAY / 4
		and absf(p.dvArr - tr.dvArr) < 0.05)
	var burned := F.apply_burn(tr, mid, "prograde", 0.5)
	var before := F.ship_state(tr, mid)
	var after := F.ship_state(burned, mid + 1)
	check("poltto kasvattaa nopeutta 0,5 km/s", absf(F.norm(after.v) - F.norm(before.v) - 0.5) < 0.005)
	check("poltto vie ohi kohteesta", burned.miss and burned.missKm > F.body("Mars").soiKm)
	var fix := F.auto_correct(burned, mid + 5 * DAY)
	check("automaattinen korjaus palauttaa kohteeseen", not fix.flight.miss and fix.dv > 0.1 and fix.dv < 2)
	check("ennen poltto-osuutta rata on ennallaan",
		F.norm(sub(F.ship_state(fix.flight, mid - DAY).r, F.ship_state(tr, mid - DAY).r)) < 1e-3)
	var s := F.ship_state(tr, mid)
	var pro := F.burn_vector(s, "prograde", 1)
	check("polton suunnat kohtisuorassa", absf(F.dot(pro, F.burn_vector(s, "outward", 1))) < 1e-10)
	check("polton suuruus", absf(F.norm(F.burn_vector(s, "inward", 0.3)) - 0.3) < 1e-10)
	check("taakse on vastakkainen", absf(F.dot(F.burn_vector(s, "retrograde", 1), pro) + 1) < 1e-10)


func _assists_moons_ships() -> void:
	var ok := F.flyby_dv("Jupiter", F.vec(10, 0, 0), F.vec(10 * cos(0.5), 10 * sin(0.5), 0))
	check("pieni käännös ilman polttoa", absf(ok.dv) < 1e-10 and ok.rp > F.body("Jupiter").radiusKm)
	check("täyskäännös on mahdoton", F.flyby_dv("Mars", F.vec(5, 0, 0), F.vec(-5, 0, 0)).is_empty())
	check("nopeuden muutos poltetaan perikeskuksessa", F.flyby_dv("Jupiter", F.vec(10, 0, 0), F.vec(11, 0.1, 0)).dv > 0)
	var options := F.find_windows("Maa", "Merkurius", START)
	var assist: Array = options.filter(func(o: Dictionary) -> bool: return o.kind == "assist")
	check("Merkuriukseen ehdotetaan Venus-linkousta", assist.size() == 1 and assist[0].via == "Venus")
	if assist.size() == 1:
		var tr: Dictionary = assist[0]
		check("linkous on suoraa lentoa halvempi", tr.dvTotal < options[0].dvTotal)
		check("linkouksen Δv on osien summa", absf(tr.dvTotal - (tr.dvDep + tr.dvFlyby + tr.dvArr)) < 1e-10)
		var venus := F.planet_state("Venus", tr.flyby.t)
		check("osuudet kohtaavat Venuksella", F.norm(sub(F.ship_state(tr, tr.flyby.t).r, venus.r)) < 10)
		check("rata päättyy Merkuriukseen", F.norm(sub(F.ship_state(tr, tr.arrive).r, F.planet_state("Merkurius", tr.arrive).r)) < 10)
		check("ohjaamossa alus ohittaa Venuksen sen ulkopuolelta", F.norm(sub(F.ship_view(tr, tr.flyby.t).r, venus.r)) > F.body("Venus").radiusKm)
	var go := F.local_transfer("Maa", "Kuu", START)
	check("kuulento noin 5 vrk", absf((go.arrive - go.depart) / DAY - 5) < 0.5)
	check("kuulennon lähtö noin 3,1 ja jarrutus 0,8 km/s", absf(go.dvDep - 3.1) < 0.05 and absf(go.dvArr - 0.8) < 0.05)
	check("alus saapuu Kuuhun", F.norm(sub(F.ship_state(go, go.arrive).r, F.body_state("Kuu", go.arrive).r)) < 1)
	var back := F.local_transfer("Kuu", "Maa", START)
	check("paluu lähtee Kuusta", F.norm(sub(F.ship_state(back, back.depart).r, F.body_state("Kuu", back.depart).r)) < 1)
	check("meno ja paluu maksavat saman", absf(back.dvTotal - go.dvTotal) < 1e-6)
	check("Kuun kiertoradalle asettuminen 100 km:n korkeudella",
		absf(F.norm(sub(F.ship_view(go, go.arrive).r, F.body_state("Kuu", go.arrive).r)) - F.orbit_of("Kuu").periKm) < 1.0)
	var moon_d := func(h: float) -> float: return F.norm(sub(F.ship_view(go, go.arrive - h * 3600000.0).r, F.body_state("Kuu", go.arrive - h * 3600000.0).r))
	check("Kuu lähestyy koko ajan", moon_d.call(12.0) > moon_d.call(6.0) and moon_d.call(6.0) > moon_d.call(1.0)
		and moon_d.call(1.0) > moon_d.call(0.1) and moon_d.call(0.1) > F.orbit_of("Kuu").periKm)
	var park := F.parking_state("Maa", START, {"epoch": START, "arg": 0.0})
	var t_go := F.angle_time("Maa", float(go.apoAngle) + PI, START, {"epoch": START, "arg": 0.0})
	var go2 := F.local_transfer("Maa", "Kuu", t_go)
	t_go = F.angle_time("Maa", float(go2.apoAngle) + PI, START, {"epoch": START, "arg": 0.0})
	go2 = F.local_transfer("Maa", "Kuu", t_go)
	check("kuulennon lähtöpoltto pysäköintiradan kohdassa", park.r.size() == 3
		and F.norm(sub(F.ship_view(go2, go2.depart).r, F.parking_state("Maa", go2.depart, {"epoch": START, "arg": 0.0}).r)) < 50.0)
	check("paluu lähtee Kuun kiertoradalta",
		absf(F.norm(sub(F.ship_view(back, back.depart).r, F.body_state("Kuu", back.depart).r)) - F.orbit_of("Kuu").periKm) < 1.0)
	check("Marsin kuu", F.moons_of("Mars") == PackedStringArray(["Phobos"]) and F.is_moon("Titan") and not F.is_moon("Mars"))
	var ion := F.find_windows("Maa", "Mars", START, {"ship": "ioni", "fuel": F.SHIPS.ioni.fuel})
	var spiral_ok := ion.size() > 0
	for o: Dictionary in ion:
		spiral_ok = spiral_ok and o.kind != "assist" and o.spiralOut > 30 * DAY and o.depart - o.spiralOut >= START
	check("ionialuksen lähtö on spiraali, joka ehtii ennen lähtöä", spiral_ok)
	check("tankkaus", not F.can_refuel("ydin", "Mars") and F.can_refuel("ydin", "Jupiter") and F.can_refuel("kemiallinen", "Mars"))


func _launch() -> void:
	var seco := LIFTOFF + F.ASCENT_S * 1000
	var pad_ok := true
	for s: Dictionary in [F.launch_state(null, LIFTOFF), F.launch_state(LIFTOFF, LIFTOFF - 5000)]:
		pad_ok = pad_ok and s.alt < 0.1 and s.speed == 0.0 and absf(F.dot(s.nose, s.rel.r) / F.norm(s.rel.r) - 1) < 1e-6
	check("alus seisoo alustalla ja nokka osoittaa ylös", pad_ok)
	check("vaiheet ennen laukaisua", F.launch_state(null, LIFTOFF).phase == "Laukaisualusta"
		and F.launch_state(LIFTOFF, LIFTOFF - 5000).phase == "Lähtölaskenta" and F.launch_state(LIFTOFF, LIFTOFF - 1000).shake > 0)
	var end := F.launch_state(LIFTOFF, seco)
	var orbit := F.parking_state("Maa", seco, F.launch_orbit(LIFTOFF))
	check("nousu päättyy 200 km:iin ja 7,79 km/s:iin", absf(end.alt - 200) < 1e-6 and absf(end.speed - 7.79) < 0.05)
	check("nousu päättyy täsmälleen kiertoradan tilaan", F.norm(sub(end.r, orbit.r)) < 1e-3 and F.norm(sub(end.v, orbit.v)) < 1e-6)
	check("lopussa nokka menosuuntaan ja katto poispäin Maasta",
		absf(F.dot(end.nose, end.rel.v) / F.norm(end.rel.v) - 1) < 1e-6 and absf(F.dot(end.up, end.rel.r) / F.norm(end.rel.r) - 1) < 1e-6)
	var prev := F.launch_state(LIFTOFF, LIFTOFF)
	var grows := true
	var tau := 5.0
	while tau <= F.ASCENT_S:
		var s := F.launch_state(LIFTOFF, LIFTOFF + tau * 1000)
		grows = grows and s.alt > prev.alt and s.speed > prev.speed
		prev = s
		tau += 5.0
	check("korkeus ja nopeus kasvavat koko nousun ajan", grows)
	var at := func(t: float) -> Dictionary: return F.launch_state(LIFTOFF, LIFTOFF + t * 1000)
	var ev := F.ASCENT_EVENTS
	check("vaiheet oikeilla hetkillä", at.call(2).phase == "Laukaisu" and at.call(ev.maxQ).phase == "Max Q"
		and at.call(ev.meco + 2).phase == "Vaiheen erotus" and at.call(ev.meco + 2).g == 0.0 and at.call(300).phase == "Vaihe 2")
	check("tärinä kovimmillaan laukaisussa ja Max Q:ssa", at.call(2).shake == 1.0
		and at.call(ev.maxQ).shake > at.call(40).shake and at.call(300).shake < 0.2)


func _injection_and_orbits() -> void:
	var seco := LIFTOFF + F.ASCENT_S * 1000
	var orbit := F.launch_orbit(LIFTOFF)
	var now := seco + 60000
	var tr := F.transfer("Maa", "Mars", now, 259)
	var vinf := sub(tr.v1, F.planet_state("Maa", now).v)
	var t := F.injection_time("Maa", vinf, now, orbit)
	check("lähtöpoltto enintään kierroksen päässä", t >= now and t - now <= F.orbit_period("Maa") * 1000 + 1)
	var E := F.body("Maa")
	var e: float = 1 + E.periKm * F.dot(vinf, vinf) / E.mu
	var rel: PackedFloat64Array = F.parking_state("Maa", t, orbit).rel.r
	check("hyperbelin asymptootti osoittaa lähtösuuntaan",
		angle_gap(atan2(rel[1], rel[0]), atan2(vinf[1], vinf[0]) - acos(-1 / e)) < 1e-6)
	var jo := {"epoch": LIFTOFF, "arg": 1.0}
	var period := F.orbit_period("Jupiter") * 1000
	var tj := F.injection_time("Jupiter", F.vec(3, 4, 0), LIFTOFF + 0.3 * period, jo)
	check("venyneellä radalla poltto seuraavassa perikeskuksessa", absf(tj - (LIFTOFF + period)) < 5)
	check("perikeskuksen etäisyys", absf(F.norm(F.parking_state("Jupiter", tj, jo).rel.r) - F.body("Jupiter").periKm) < 0.5)
	var p := F.planet_state("Mars", LIFTOFF)
	var r := F.add(p.r, F.scale(F.vec(cos(2.2), sin(2.2), 0), F.body("Mars").periKm))
	var s := F.parking_state("Mars", LIFTOFF, F.orbit_at("Mars", r, LIFTOFF))
	check("jarrutuksen jälkeen alus jatkaa radalla saapumiskohdastaan", F.norm(sub(s.r, r)) < 1e-3)


func _aerobrake() -> void:
	var ok := true
	for name: String in ["Jupiter", "Saturnus", "Uranus", "Neptunus"]:
		var b := F.body(name)
		var high := F.burn_dv(name, 5.5)
		ok = ok and F.has_low_orbit(name) and F.aerobrake_dv(name) > 0.1 and F.aerobrake_dv(name) < 1
		F.set_low_orbit(name, true)
		ok = ok and b.apoKm == b.periKm and b.periKm - b.radiusKm <= 5000
		var low := F.burn_dv(name, 5.5)
		ok = ok and F.orbit_period(name) < 6 * 3600
		F.set_low_orbit(name, false)
		ok = ok and low > high + 5 and absf(F.burn_dv(name, 5.5) - high) < 1e-12 and F.orbit_period(name) > 86400
	check("ilmajarrutus vie matalalle ympyräradalle, jolta lähtö on kallis", ok)
	F.set_low_orbit("Jupiter", true)
	check("kemiallinen raketti ei pääse Jupiterin matalalta radalta", F.burn_dv("Jupiter", 5.5) > F.SHIPS.kemiallinen.fuel)
	F.set_low_orbit("Jupiter", false)
	F.set_low_orbit("Mars", true)
	check("Marsilla ei matalaa ilmajarrutusrataa", not F.has_low_orbit("Mars") and F.body("Mars").periKm - F.body("Mars").radiusKm == 500)
	var alt := func(n: String) -> float: return F.body(n).periKm - F.body(n).radiusKm
	var low_ok: bool = alt.call("Maa") == 200
	for n: String in ["Merkurius", "Venus", "Mars"]:
		low_ok = low_ok and alt.call(n) == 500 and F.body(n).apoKm == F.body(n).periKm
	for n: String in ["Jupiter", "Saturnus", "Uranus", "Neptunus"]:
		low_ok = low_ok and alt.call(n) <= 5000
	check("saapumisradat ovat matalia", low_ok)
	check("Mars- ja Jupiter-saapuminen mahtuu budjettiin", F.burn_dv("Mars", 2.6) < 2.5 and F.burn_dv("Jupiter", 5.6) < 2)
