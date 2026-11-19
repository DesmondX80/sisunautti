extends TestCase
## Aluksen häiriöt (#42) ilman käyttöliittymää: pulmien luonti ja tarkistus kaikille tyypeille, korjaus, aikasakot,
## kiihdytyksen esto, tuhoutuminen ajan loppuessa, vikojen arvonta pelatun ajan mukaan sekä tallennus ja lataus.
##   godot --headless -- --faultstest

const START_REAL := 1794614400000.0

var G: Node
var events: Array[String] = []


func _ready() -> void:
	G = Game
	G.fake_real_ms = START_REAL
	G.new_game()
	for sig: String in ["fault_started", "fault_fixed", "fault_mistake", "ship_destroyed"]:
		var name := sig
		G.connect(sig, func(_k: String) -> void: events.append(name))
	check("testeissä vikoja ei tule itsestään", not G.faults_allowed and not G.fault_possible())
	_puzzles()
	_to_orbit()
	_wires()
	_code()
	_valves()
	_random_faults()
	_save_load()
	_destroy()
	G.faults_allowed = false
	G.fake_real_ms = -1.0
	DirAccess.remove_absolute(G.TEST_SAVE_PATH)
	finish()


func _puzzles() -> void:
	var rng := RandomNumberGenerator.new()
	var ok_wires := true
	var ok_code := true
	var ok_valves := true
	for i in 200:
		rng.seed = i
		var w := Faults.make("johdot", rng)
		var sorted_l: Array = w.left.duplicate()
		var sorted_r: Array = w.right.duplicate()
		sorted_l.sort()
		sorted_r.sort()
		ok_wires = ok_wires and w.left.size() == Faults.WIRE_COUNT and sorted_l == sorted_r and w.left != w.right
		var c := Faults.code_of(Faults.make("koodi", rng))
		ok_code = ok_code and c.options.size() == 3 and c.bug >= 0 and c.bug < c.lines.size() \
			and c.options[c.right] == Faults.CODE[Faults.CODE.find_custom(func(x: Dictionary) -> bool: return x.title == c.title)].options[0]
		var p := Faults.make("paine", rng)
		ok_valves = ok_valves and not Faults.pressures_ok(p) and _solvable(p)
	check("johdot: samat värit eri järjestyksessä", ok_wires)
	check("koodi: virherivi ja oikea korjaus vaihtoehdoissa", ok_code)
	check("paine: ei valmiiksi ratkaistu ja aina ratkaistavissa", ok_valves)
	var make_same := func(seed: int) -> Dictionary:
		var r := RandomNumberGenerator.new()
		r.seed = seed
		return Faults.make("paine", r)
	check("pulma on toistettava siemenellä", make_same.call(7) == make_same.call(7))
	for kind: String in Faults.KINDS:
		check("%s: nimi, ohje, aika ja tuhon syy" % kind, Faults.INFO[kind].name != "" and Faults.INFO[kind].help != ""
			and float(Faults.INFO[kind].ms) >= 60000.0 and Faults.doom(kind) != "")


## Jokin venttiiliyhdistelmä tuo kaikki paineet vihreälle.
func _solvable(p: Dictionary) -> bool:
	var q := p.duplicate(true)
	for mask in 1 << Faults.VALVES:
		for v in Faults.VALVES:
			q.valves[v] = (mask >> v) & 1 == 1
		if Faults.pressures_ok(q):
			return true
	return false


func _to_orbit() -> void:
	G.start_countdown()
	G.fake_real_ms += 10000.0 + Flight.ASCENT_S * 1000.0 + 1000.0
	G.tick()
	check("kiertoradalla", not G.state.pad and G.state.location == "Maa")


func _wires() -> void:
	G.set_warp(4)
	G.start_fault("johdot")
	var f: Dictionary = G.state.fault
	check("vika alkaa: kiihdytys 1×, lokikirjaan ja signaali", G.warp_index() == 0 and events.has("fault_started")
		and String(G.state.log.back().text).begins_with("Vika: Sähkövika"))
	G.set_warp(3)
	check("vian aikana aikaa ei voi kiihdyttää", G.warp_index() == 0 and G.notice != "")
	var before: float = float(f.remaining)
	var wrong := -1
	for r in f.right.size():
		if not Faults.wire_ok(f, 0, r):
			wrong = r
			break
	check("väärä kytkentä hylätään ja vie aikaa", not G.fault_wire(0, wrong) and float(f.remaining) == before - Faults.PENALTY_MS
		and int(f.mistakes) == 1 and events.has("fault_mistake"))
	for l in f.left.size():
		var r: int = f.right.find(f.left[l])
		check("johto %d oikeaan liittimeen" % l, G.fault_wire(l, r))
		if l == 0:
			check("samaa johtoa ei voi kytkeä kahdesti", not G.fault_wire(0, r))
	check("johdot kytketty: vika korjattu", G.state.fault == null and events.has("fault_fixed")
		and String(G.state.log.back().text).begins_with("Sähkövika korjattu"))
	G.set_warp(3)
	check("korjauksen jälkeen kiihdytys toimii", G.warp_index() == 3)
	G.set_warp(0)


func _code() -> void:
	G.start_fault("koodi")
	var c := Faults.code_of(G.state.fault)
	check("väärä rivi vie aikaa", not G.fault_code_line((c.bug + 1) % c.lines.size()) and int(G.state.fault.mistakes) == 1)
	check("korjausta ei voi valita ennen riviä", not G.fault_code_fix(c.right) and G.state.fault != null)
	check("oikea rivi", G.fault_code_line(c.bug) and int(G.state.fault.line) == c.bug)
	check("väärä korjaus vie aikaa", not G.fault_code_fix((c.right + 1) % 3) and int(G.state.fault.mistakes) == 2)
	check("oikea korjaus korjaa vian", G.fault_code_fix(c.right) and G.state.fault == null)


func _valves() -> void:
	G.start_fault("paine")
	var f: Dictionary = G.state.fault
	var solution := -1
	for mask in 1 << Faults.VALVES:
		var q := f.duplicate(true)
		for v in Faults.VALVES:
			q.valves[v] = (mask >> v) & 1 == 1
		if Faults.pressures_ok(q):
			solution = mask
			break
	for v in Faults.VALVES:
		if (solution >> v) & 1 == 1 and G.state.fault != null:
			G.fault_valve(v)
	check("venttiileillä paineet vihreälle: vika korjattu", G.state.fault == null)


func _random_faults() -> void:
	G.faults_allowed = true
	var was: int = Settings.faults
	Settings.faults = 0
	G._fault_clock = 0.0
	for i in 100:
		G.fault_step(60000.0)
	check("asetus Pois: ei vikoja", G.state.fault == null)
	Settings.faults = 2
	G._fault_clock = 0.0
	G.fault_step(Game.FAULT_GRACE_MS * 0.5)
	G.fault_rng.seed = 1
	var n := 0
	for i in 2000:
		G.fault_step(1000.0)
		if G.state.fault != null:
			n += 1
			G.state.fault = null
			G._fault_clock = Game.FAULT_GRACE_MS
	# Usein: keskimäärin 5 min välein → 2000 s:ssa noin 6–7 vikaa.
	check("vikoja tulee pelatun ajan mukaan (usein: %d / 33 min)" % n, n >= 3 and n <= 12)
	G.faults_paused = true
	G._fault_clock = Game.FAULT_GRACE_MS
	for i in 200:
		G.fault_step(60000.0)
	check("valikossa (tauolla) ei vikoja", G.state.fault == null)
	G.faults_paused = false
	G.state.pad = true
	G._fault_clock = Game.FAULT_GRACE_MS
	for i in 200:
		G.fault_step(60000.0)
	check("laukaisualustalla ei vikoja", G.state.fault == null)
	G.state.pad = false
	Settings.faults = was
	G.faults_allowed = false


func _save_load() -> void:
	G.start_fault("paine")
	G.fault_step(5000.0)
	var left: float = float(G.state.fault.remaining)
	G.save_game()
	G.fake_real_ms += 3600000.0 # tunti suljettuna: vian aika ei kulu
	G.load_game()
	check("vika säilyy tallennuksessa ja aika ei kulu suljettuna", G.state.fault != null and G.state.fault.kind == "paine"
		and float(G.state.fault.remaining) == left)
	var p: Dictionary = G.state.fault
	G.fault_valve(0)
	check("ladatun vian venttiilit toimivat", bool(p.valves[0]) or G.state.fault == null)


func _destroy() -> void:
	if G.state.fault == null:
		G.start_fault("johdot")
	var t: float = G.sim_now()
	G.fault_step(float(G.state.fault.remaining) + 1.0)
	check("aika loppuu: alus tuhoutuu", G.state.destroyed != null and G.state.fault == null and events.has("ship_destroyed")
		and String(G.state.destroyed.text) != "")
	G.fake_real_ms += 600000.0
	check("tuhon jälkeen kello on pysähtynyt", absf(G.sim_now() - float(G.state.destroyed.t)) < 1.0 and float(G.state.destroyed.t) >= t)
	G.faults_allowed = true
	G._fault_clock = Game.FAULT_GRACE_MS
	for i in 100:
		G.fault_step(60000.0)
	check("tuhoutuneeseen alukseen ei tule vikoja", G.state.fault == null)
	G.faults_allowed = false
	G.new_game()
	check("uusi peli tuhon jälkeen", G.state.destroyed == null and G.state.pad and G.state.fault == null)
