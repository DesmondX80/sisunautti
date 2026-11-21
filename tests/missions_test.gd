extends TestCase
## Lennonjohdon tehtävät (#44) ilman käyttöliittymää: arvonta (toistettava, portaat, ei päällekkäisiä), ehdot kaikille
## lajeille, pisteet, tilalle annettavat tehtävät, luopuminen, Δv-kulutus lennolla sekä tallennus ja vanha tallennus
## ilman tehtäviä.
##   godot --headless -- --missionstest

const START_REAL := 1794614400000.0

var G: Node
var issued: Array = []
var completed: Array = []


func _ready() -> void:
	G = Game
	G.fake_real_ms = START_REAL
	G.mission_issued.connect(func(m: Dictionary) -> void: issued.append(m))
	G.mission_completed.connect(func(m: Dictionary) -> void: completed.append(m))
	_generation()
	_conditions()
	_game_flow()
	_save_load()
	_old_save()
	G.fake_real_ms = -1.0
	DirAccess.remove_absolute(G.TEST_SAVE_PATH)
	finish()


func _state() -> Dictionary:
	return {"location": "Maa", "explored": ["Maa"], "flights": []}


func _generation() -> void:
	var s := _state()
	var a := Missions.fresh()
	var b := Missions.fresh()
	Missions.refill(a, s, true, 0.0)
	Missions.refill(b, s, true, 0.0)
	check("kolme aktiivista tehtävää", a.active.size() == Missions.ACTIVE)
	check("ensimmäinen tehtävä: Kuun kiertorata", a.active[0].kind == "orbit" and a.active[0].body == "Kuu")
	check("arvonta on toistettava", JSON.stringify(a) == JSON.stringify(b))
	check("aluksi vain ensimmäisen portaan kohteita", a.active.all(func(m: Dictionary) -> bool: return m.body == "" or Missions.tier_of(m.body) == 0))
	var keys := {}
	var dup := false
	for i in 40:
		var m := Missions.generate(a, s, true, 0.0)
		if m.is_empty():
			break
		var k := "%s %s" % [m.kind, m.body]
		dup = dup or (keys.has(k) and m.kind != "fault")
		keys[k] = true
		a.active.append(m)
	check("sama tehtävä ei toistu", not dup)
	check("ilman vikoja ei vikatehtäviä", Missions.candidates(Missions.fresh(), s, false).all(func(c: Array) -> bool: return c[0] != "fault"))
	check("tutkittua kohdetta ei kartoiteta", Missions.candidates(Missions.fresh(), {"location": "Maa", "explored": ["Maa", "Kuu"], "flights": []}, false)
		.all(func(c: Array) -> bool: return not (c[0] == "survey" and c[1] == "Kuu")))
	var ms := Missions.fresh()
	check("porras 1 aukeaa kahdella tehtävällä", Missions.tiers_open(1) == 1 and Missions.tiers_open(2) == 2 and Missions.tiers_open(5) == 3)
	ms.done = [{"kind": "x"}, {"kind": "y"}]
	check("toisen portaan kohteet avautuvat", Missions.candidates(ms, s, false).any(func(c: Array) -> bool: return c[1] == "Jupiter"))
	check("kolmas porras vielä kiinni", Missions.candidates(ms, s, false).all(func(c: Array) -> bool: return c[1] != "Saturnus"))
	var h := Missions.hohmann_estimate("Maa", "Mars")
	check("Hohmann Maa–Mars noin 259 vrk", absf(float(h.days) - 259.0) < 3.0)
	check("Hohmann Maa–Mars Δv noin 5,6 km/s", float(h.dv) > 5.0 and float(h.dv) < 6.2)
	var fast := Missions.candidates(Missions.fresh(), s, false).filter(func(c: Array) -> bool: return c[0] == "fast" and c[1] == "Mars")
	check("pikalennon raja 80 % Hohmannista", not fast.is_empty() and fast[0][3].limit == ceilf(float(h.days) * 0.8) and fast[0][3].from == "Maa")
	for kind: String in ["orbit", "survey", "flyby", "aero", "fast", "frugal", "fault"]:
		var m := {"kind": kind, "body": "Mars" if kind != "aero" else "Jupiter", "from": "Maa", "limit": 6.0}
		check("teksti: " + kind, Missions.title(m) != "" and Missions.text(m).ends_with("."))


func _conditions() -> void:
	var cap := {"type": "capture", "body": "Mars", "aero": false, "from": "Maa", "days": 200.0, "dv": 6.0}
	check("kiertorata", Missions.matches({"kind": "orbit", "body": "Mars"}, cap))
	check("kiertorata väärä kohde", not Missions.matches({"kind": "orbit", "body": "Venus"}, cap))
	check("kartoitus", Missions.matches({"kind": "survey", "body": "Mars"}, {"type": "survey", "body": "Mars"}))
	check("kartoitus ei kiertoradasta", not Missions.matches({"kind": "survey", "body": "Mars"}, cap))
	check("linkous", Missions.matches({"kind": "flyby", "body": "Venus"}, {"type": "flyby", "body": "Venus"}))
	check("ilmajarrutus", Missions.matches({"kind": "aero", "body": "Jupiter"}, {"type": "capture", "body": "Jupiter", "aero": true}))
	check("moottorijarrutus ei ole ilmajarrutus", not Missions.matches({"kind": "aero", "body": "Jupiter"}, {"type": "capture", "body": "Jupiter", "aero": false}))
	var fast := {"kind": "fast", "body": "Mars", "from": "Maa", "limit": 207.0}
	check("pikalento ajassa", Missions.matches(fast, cap))
	cap.days = 210.0
	check("pikalento myöhässä", not Missions.matches(fast, cap))
	cap.from = "Venus"
	cap.days = 100.0
	check("pikalento väärästä lähtöpaikasta", not Missions.matches(fast, cap))
	cap.from = "Maa"
	check("säästölento rajalla", Missions.matches({"kind": "frugal", "body": "Mars", "from": "Maa", "limit": 6.0}, cap))
	cap.dv = 6.05
	check("säästölento yli rajan", not Missions.matches({"kind": "frugal", "body": "Mars", "from": "Maa", "limit": 6.0}, cap))
	check("vika ajoissa", Missions.matches({"kind": "fault", "limit": 30.0}, {"type": "fault", "left": 41.0}))
	check("vika myöhässä", not Missions.matches({"kind": "fault", "limit": 30.0}, {"type": "fault", "left": 12.0}))
	var opt := {"depart": 0.0, "arrive": 200.0 * Flight.DAY_MS, "dvTotal": 5.9, "via": "Venus"}
	check("reitti täyttää pikalennon", Missions.fits_option({"kind": "fast", "body": "Mars", "from": "Maa", "limit": 207.0}, opt, "Maa", "Mars"))
	check("reitti ei täytä säästölentoa", not Missions.fits_option({"kind": "frugal", "body": "Mars", "from": "Maa", "limit": 5.8}, opt, "Maa", "Mars"))
	check("reitti täyttää linkouksen", Missions.fits_option({"kind": "flyby", "body": "Venus"}, opt, "Maa", "Mars"))
	check("Auringon kiertoradalta ei pikalentoa", not Missions.fits_option({"kind": "fast", "body": "Mars", "from": "Maa", "limit": 207.0}, opt, {"r": []}, "Mars"))
	var ms := Missions.fresh()
	ms.active = [{"kind": "orbit", "body": "Mars", "points": 10}, {"kind": "survey", "body": "Mars", "points": 15}]
	var done := Missions.complete(ms, {"type": "capture", "body": "Mars"}, 5.0)
	check("suoritus siirtää ja antaa pisteet", done.size() == 1 and ms.points == 10 and ms.done.size() == 1 and ms.active.size() == 1 and ms.done[0].doneAt == 5.0)


## Pelissä: uusi peli antaa tehtävät hiljaa, Kuun kiertoradalle saapuminen suorittaa tehtävän ja tilalle tulee uusi.
func _game_flow() -> void:
	G.new_game()
	var ms: Dictionary = G.missions()
	check("uudessa pelissä tehtävät", ms.active.size() == Missions.ACTIVE and issued.is_empty())
	check("lokikirja tyhjä", G.state.log.is_empty())
	G.state.pad = false
	G.state.orbit = Flight.launch_orbit(G.sim_now())
	G.local_option("Kuu")
	check("siirto Kuuhun", not G.options.is_empty() and G.choose(G.options[0]))
	G.jump_to_window()
	G.arm()
	var t0: float = G.state.fuel
	G.launch()
	check("lähtöpolttoaine talteen", absf(float(G.state.flight.fuel0) - t0) < 1e-9)
	G.anchor(float(G.state.flight.arrive), 0)
	G.capture()
	check("Kuun kiertoradalla", G.state.location == "Kuu")
	check("Kuu-tehtävä suoritettu", completed.size() >= 1 and completed[0].body == "Kuu" and ms.points >= 10)
	check("tilalle uusi tehtävä", ms.active.size() == Missions.ACTIVE and issued.size() == completed.size())
	check("lokikirjassa suoritus ja uusi tehtävä", G.state.log.any(func(e: Dictionary) -> bool: return String(e.text).begins_with("Tehtävä suoritettu: Kiertoradalle: Kuu"))
		and G.state.log.any(func(e: Dictionary) -> bool: return String(e.text).begins_with("Uusi tehtävä:")))
	var id: int = ms.active[0].id
	var dropped: Dictionary = ms.active[0]
	G.discard_mission(id)
	check("luopuminen antaa uuden", ms.active.size() == Missions.ACTIVE and ms.active.all(func(m: Dictionary) -> bool: return int(m.id) != id))
	check("luovuttua ei anneta uudelleen", dropped.kind == "fault" or Missions.candidates(ms, G.state, true).all(func(c: Array) -> bool: return not (c[0] == dropped.kind and c[1] == dropped.body)))


func _save_load() -> void:
	var sig := func(ms: Dictionary) -> String:
		return "%d %d %d %s" % [ms.points, ms.seq, ms.done.size(), ",".join(ms.active.map(func(m: Dictionary) -> String:
			return "%d %s %s %d" % [int(m.id), m.kind, m.body, int(m.points)]))]
	var before: String = sig.call(G.missions())
	G.save_game()
	G.state = {}
	G.load_game()
	check("tehtävät tallentuvat", sig.call(G.missions()) == before and G.missions().points > 0)


## Vanha tallennus ilman tehtäviä: tehtävät annetaan latauksessa, ja tutkitut kohteet jäävät pois.
func _old_save() -> void:
	var text := FileAccess.get_file_as_string("res://tests/data/web_save.json")
	check("vanha tallennus latautuu", G.load_json(text))
	var explored: Array = G.state.explored
	G.state.realTime = G.real_ms()
	G.load_game_from_state()
	var ms: Dictionary = G.missions()
	check("vanhaan tallennukseen tehtävät", ms.active.size() == Missions.ACTIVE and ms.points == 0)
	check("ei kartoitusta tutkitusta kohteesta", ms.active.all(func(m: Dictionary) -> bool: return not (m.kind == "survey" and explored.has(m.body))))
