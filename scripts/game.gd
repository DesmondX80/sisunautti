extends Node
## Pelin tila, kello ja tapahtumat ilman käyttöliittymää (web/js/voyage.js). Autoload Game.
##
## Kello: simulaatioaika = ankkuri + (oikea aika − ankkurin oikea aika) × kiihdytys. Kun peli on suljettuna, aika
## kulkee oikeaa vauhtia (1×), joten alus lentää myös pelin ollessa kiinni. Kello pysähtyy laukaisuhetkeen,
## laukaisuikkunaan ja saapumiseen, jotta ne eivät mene ohi, ja kiihdytys pienenee ennen tapahtumia.
##
## Tila (state) on sanakirja samassa muodossa kuin selainversion tallennus (avain avaruuslento):
##   v, location (kappale tai null), pad, ascent {liftoff}, orbit {epoch, arg}, lowOrbit, drift {r, v, t}, ship, fuel,
##   simTime, realTime, warp, plan, flight, survey {kind, body, start, dur?}, explored, flights, log [{t, text}].
## Tallennus tiedostoon user://save.json 5 s välein ja suljettaessa.
## Käyttöliittymä ja ohjaamo kuuntelevat signaaleja eivätkä kutsu toisiaan.

## Tila muuttui (piirrä paneeli uudelleen).
signal changed
## Ilmoitus pelaajalle (esim. kiihdytyksen pienennys), tyhjä = ei ilmoitusta.
signal notice_changed(text: String)
signal search_progress(progress: float)
signal search_finished(options: Array)
signal countdown_started(liftoff: float)
## Kantoraketti nousee alustalta.
signal liftoff
## Alus on kiertoradalla nousun jälkeen.
signal orbit_reached(body: String)
## Lähtöpoltto: siirtorata alkoi.
signal departure_burn(flight: Dictionary)
## Linkous ohilentoplaneetan ohi.
signal flyby(body: String)
## Alus saapui kohteen vaikutuspiiriin.
signal soi_entered(body: String)
## Alus on perillä (kello pysähtyi saapumiseen).
signal arrived(body: String)
## Jarrutus kiertoradalle (captured = true) tai ohilento Auringon kiertoradalle.
signal capture_done(body: String, captured: bool, aero: bool)
## Kurssikorjauspoltto lennon aikana.
signal course_burn(dv: float)
## Kartoitus tai ionialuksen spiraalilasku valmis.
signal survey_finished(body: String, first: bool)

## Tallennusavaimet ovat peräisin OmaAvaruuden Avaruuslennosta; niitä ei nimetä uudelleen (selaintallennusten tuonti).
const KEY := "avaruuslento"
const VIEW_KEY := "avaruuslento.view"
const PANEL_KEY := "avaruuslento.panel"
const SAVE_PATH := "user://save.json"
const TEST_SAVE_PATH := "user://test_save.json"
const DAY := 86400000.0
## Aikakiihdytykset: kerroin ja nimi.
const WARPS := [[1.0, "1×"], [10.0, "10×"], [100.0, "100×"], [3600.0, "1 h/s"], [86400.0, "1 vrk/s"],
	[604800.0, "1 vk/s"], [2592000.0, "1 kk/s"], [31557600.0, "1 v/s"]]
## Kiihdytys pienenee, kun seuraavaan tapahtumaan on alle näin monta oikeaa millisekuntia.
const WARP_LEAD := 2500.0
## Lähtölaskennan pituus (s) ja aika lähtöpolton virityksestä aikaisimpaan polttoon (ms).
const PAD_COUNT_S := 10.0
const ARM_LEAD := 10000.0
## Ilmajarrutuksen ja polton tärinän kesto ohjaamossa (ms oikeaa aikaa).
const AERO_MS := 10000.0
const BURN_SHAKE_MS := 7000.0
## Planeetan tutkiminen (ja tankkaus) kestää vuorokauden pelin aikaa.
const SURVEY_MS := DAY
## Laukaisuikkunoiden haun aikabudjetti ruutua kohden (ms).
const SEARCH_BUDGET_MS := 12.0
const AUTOSAVE_MS := 5000.0
const KINDS := {"cheapest": ["Halvin", "Vähiten polttoainetta"], "faster": ["Nopeampi", "Lyhyempi lento, enemmän polttoainetta"],
	"earliest": ["Aikaisin perillä", "Nopein reitti, johon polttoaine riittää"],
	"assist": ["Linkous", "Ohilento toisen planeetan ohi kääntää rataa lähes ilmaiseksi"],
	"local": ["Siirtorata", "Hohmannin siirto planeetan ympärillä"]}

## Oliko tallennettu peli olemassa (aloitusvalikon Jatka peliä); uusi peli tallentuu heti.
var has_saved_game := false
var state: Dictionary = {}
var save_path := SAVE_PATH
## Testit asettavat oikean ajan (ms) käsin; < 0 = järjestelmän kello.
var fake_real_ms := -1.0
## Reittihaku: kohde, käynnissä oleva haku, edistyminen ja valmiit vaihtoehdot (options_ready).
var target := ""
var search: WindowSearch = null
var progress := 0.0
var options: Array = []
var options_ready := false
var notice := ""
## Ohjaamon tehosteiden alkuhetket (oikeaa aikaa, ms).
var burn_at := -INF
var aero_at := -INF

var _last_save := 0.0
var _emitted := {} # kerran lähetetyt tapahtumat: liftoff, soi, arrived (avain sisältää hetken)


func _ready() -> void:
	if TestFlags.find(OS.get_cmdline_user_args()) != "":
		save_path = TEST_SAVE_PATH
	load_game()


func _process(_delta: float) -> void:
	if state.is_empty():
		return
	if search != null:
		var p := search.run(SEARCH_BUDGET_MS)
		progress = p
		search_progress.emit(p)
		if search.done:
			options = search.result
			options_ready = true
			search = null
			search_finished.emit(options)
			changed.emit()
	tick()


func _notification(what: int) -> void:
	# Suljettaessa ja taustalle mentäessä kiihdytys palaa 1×:ään: suljettuna aika kulkee oikeaa vauhtia.
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		park()


# --- Kello ---

func real_ms() -> float:
	return fake_real_ms if fake_real_ms >= 0.0 else Time.get_unix_time_from_system() * 1000.0


func warp_index() -> int:
	return int(state.warp)


func _raw_time() -> float:
	return float(state.simTime) + (real_ms() - float(state.realTime)) * float(WARPS[warp_index()][0])


## Hetki, johon kello pysähtyy: nousun loppu, laukaisuikkuna (ionialuksella spiraalin alku) tai saapuminen.
func hold_at() -> float:
	if state.ascent != null:
		return float(state.ascent.liftoff) + Flight.ASCENT_S * 1000.0
	var p: Variant = state.plan
	if p != null:
		if float(p.get("spiralOut", 0.0)) > 0.0 and not p.get("spiralStarted", false):
			return float(p.depart) - float(p.spiralOut)
		return p.depart
	if state.flight != null:
		return state.flight.arrive
	return INF


func anchor(t: float, warp: int) -> void:
	state.simTime = t
	state.realTime = real_ms()
	state.warp = warp
	save_game()


## Simulaation hetki (ms). Kello pysähtyy laukaisuhetkeen ja saapumiseen.
func sim_now() -> float:
	var t := _raw_time()
	var stop := hold_at()
	if t >= stop:
		if warp_index() > 0 or float(state.simTime) < stop:
			anchor(stop, 0)
		return stop
	return t


## Kiihdytys: lähtölaskennassa ja nousussa enintään 10×.
func set_warp(i: int) -> void:
	_set_notice("")
	anchor(sim_now(), mini(i, 1) if state.pad else clampi(i, 0, WARPS.size() - 1))
	changed.emit()


## Ennen vaikutuspiirin rajaa, ohilentoa, lähtöpolttoa ja saapumista kiihdytys pienenee portaittain.
func limit_warp(t: float) -> void:
	var plan: Variant = state.plan
	var f: Variant = state.flight
	if warp_index() == 0 or not (f != null or (plan != null and plan.get("armed", false))):
		return
	var events: Array[float] = []
	if f != null:
		var fb: Variant = f.get("flyby")
		events = [fb.t if fb is Dictionary and not fb.get("done", false) else INF, float(f.soi), float(f.arrive)]
	else:
		events = [float(plan.depart)]
	var next := INF
	for s in events:
		if s > t and s < next:
			next = s
	if is_inf(next):
		return
	var i := warp_index()
	while i > 0 and float(WARPS[i][0]) * WARP_LEAD > next - t:
		i -= 1
	if i == warp_index():
		return
	var what := "lähtöpoltto"
	if f != null:
		var fb: Variant = f.get("flyby")
		if fb is Dictionary and next == float(fb.t):
			what = "ohilento %s ohi" % Fmt.gen(fb.body)
		elif next == float(f.soi) and next != float(f.arrive):
			what = "%s vaikutuspiiri" % Fmt.gen(f.to)
		else:
			what = "saapuminen"
	_set_notice("Kiihdytys pienennettiin (%s): %s lähestyy." % [WARPS[i][1], what])
	anchor(t, i)
	changed.emit()


func _set_notice(text: String) -> void:
	if text == notice:
		return
	notice = text
	notice_changed.emit(text)


# --- Tila ja tallennus ---

## Uusi peli laukaisualustalla Maan pinnalla.
func fresh() -> Dictionary:
	var now := real_ms()
	return {"v": 1, "location": "Maa", "pad": true, "ascent": null, "orbit": null, "lowOrbit": null, "drift": null,
		"ship": "kemiallinen", "fuel": Flight.FUEL_KMS, "simTime": now, "realTime": now, "warp": 0,
		"plan": null, "flight": null, "survey": null, "explored": ["Maa"], "flights": [], "log": []}


func new_game() -> void:
	has_saved_game = true
	state = fresh()
	_reset_runtime()
	_sync_low_orbit()
	save_game()
	changed.emit()


## Aloita alusta (käyttöliittymä kysyy vahvistuksen).
func restart() -> void:
	new_game()


func _reset_runtime() -> void:
	target = ""
	search = null
	options = []
	options_ready = false
	progress = 0.0
	_emitted.clear()
	_set_notice("")


func save_game() -> void:
	_last_save = real_ms()
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		push_warning("Tallennus epäonnistui: " + save_path)
		return
	f.store_string(to_json())


## Tila JSON-muodossa (sama kuin selainversion localStorage-avaimen avaruuslento sisältö).
func to_json() -> String:
	return JSON.stringify(_finite(state), "", false, true)


# JSON ei tunne äärettömiä eikä NaN:ia (JS kirjoittaa ne null-arvoina).
func _finite(v: Variant) -> Variant:
	if v is float:
		return v if is_finite(v) else null
	if v is Dictionary:
		var d := {}
		for k: Variant in v:
			d[k] = _finite(v[k])
		return d
	if v is Array:
		return v.map(_finite)
	if v is PackedFloat64Array:
		return Array(v).map(_finite)
	return v


func load_game() -> void:
	var text := FileAccess.get_file_as_string(save_path) if FileAccess.file_exists(save_path) else ""
	if text == "" and save_path == SAVE_PATH and _import_browser_save():
		has_saved_game = true
		return
	has_saved_game = load_json(text)
	if not has_saved_game:
		state = fresh()
	load_game_from_state()


## Selaimessa: jos omaa tallennusta ei vielä ole, tuodaan vanhan selainversion peli localStoragesta (sama
## alkuperä desmondx80.github.io) sekä näkymän ja sivupaneelin valinnat. Palauttaa true, jos peli tuotiin.
func _import_browser_save() -> bool:
	if not OS.has_feature("web"):
		return false
	var read := func(key: String) -> String:
		var v: Variant = JavaScriptBridge.eval("(function(){try{return localStorage.getItem('%s')||''}catch(e){return ''}})()" % key, true)
		return v if v is String else ""
	var parse := func(key: String) -> Variant:
		var text: String = read.call(key)
		return JSON.parse_string(text) if text != "" else null
	var view: Variant = parse.call(VIEW_KEY)
	if view is String and (view == "cockpit" or view == "map"):
		Settings.set_view(view)
	var panel: Variant = parse.call(PANEL_KEY)
	if panel is String:
		Settings.set_panel_hidden(panel == "hidden")
	var game: String = read.call(KEY)
	return game != "" and import_web_save(game)


## Ottaa käyttöön load_json():lla asetetun tilan.
func load_game_from_state() -> void:
	_reset_runtime()
	# Jos tallennus jäi kiihdytykselle (peli suljettiin kesken), suljettu aika lasketaan silti 1×:nä.
	state.warp = 0
	_sync_low_orbit()
	sim_now()
	changed.emit()


## Lataa tilan JSON-tekstistä (oma tallennus tai selainversion avaruuslento-avaimen sisältö). Palauttaa false,
## jos teksti ei ole kelvollinen tallennus.
func load_json(text: String) -> bool:
	if text.strip_edges() == "":
		return false
	var s: Variant = JSON.parse_string(text)
	if not (s is Dictionary) or int(s.get("v", 0)) != 1:
		return false
	# Ennen laukaisualustaa tallennetussa pelissä alus on jo kiertoradalla tai matkalla.
	var g := fresh()
	g.pad = false
	g.merge(s, true)
	g.warp = int(g.warp)
	state = g
	return true


## Selainversion tallennuksen tuonti (#12: localStorage → JavaScriptBridge). Kirjataan lokikirjaan.
func import_web_save(text: String) -> bool:
	if not load_json(text):
		return false
	_reset_runtime()
	state.warp = 0
	_sync_low_orbit()
	state.log.append({"t": sim_now(), "text": "Peli tuotiin selainversiosta"})
	save_game()
	changed.emit()
	return true


## Taustalle tai suljettaessa: kiihdytys 1×:ään ja tallennus.
func park() -> void:
	if state.is_empty():
		return
	if warp_index() != 0:
		anchor(sim_now(), 0)
	else:
		save_game()


# Ratamalli laskee lähdön siltä radalta, jolla alus on: matala rata vain sillä planeetalla.
func _sync_low_orbit() -> void:
	for name in Planets.NAMES:
		Flight.set_low_orbit(name, state.get("lowOrbit") == name)


func fuel_max() -> float:
	return Flight.SHIPS[state.ship].fuel


func is_ion() -> bool:
	return Flight.ship_accel(state.ship) > 0.0


## Lähtöpaikka: kappale, jonka kiertoradalla alus on, tai Auringon kiertorata {r, v, t}.
func here() -> Variant:
	return state.location if state.location != null else state.drift


func log_event(t: float, text: String) -> void:
	state.log.append({"t": t, "text": text})


# --- Laukaisualusta ---

func start_countdown() -> void:
	if not state.pad or state.ascent != null:
		return
	var now := sim_now()
	state.ascent = {"liftoff": now + PAD_COUNT_S * 1000.0}
	anchor(now, 0)
	countdown_started.emit(state.ascent.liftoff)
	changed.emit()


func abort_countdown() -> void:
	if state.ascent == null or sim_now() >= float(state.ascent.liftoff):
		return
	state.ascent = null
	save_game()
	changed.emit()


## Nousu päättyy: alus on 200 km:n kiertoradalla siinä kohdassa, johon nousu sen vei.
func reach_orbit() -> void:
	var lift: float = state.ascent.liftoff
	var end := lift + Flight.ASCENT_S * 1000.0
	state.orbit = Flight.launch_orbit(lift)
	state.pad = false
	state.ascent = null
	log_event(end, "Laukaisu Maan pinnalta: kiertoradalla 200 km korkeudella 8 min 30 s nousun jälkeen")
	_set_notice("")
	anchor(end, 0)
	orbit_reached.emit("Maa")
	changed.emit()


# --- Reitit ---

## Laukaisuikkunoiden haku kohteeseen; haku etenee ruutu kerrallaan (_process).
func begin_search(to: String) -> void:
	target = to
	options = []
	options_ready = false
	progress = 0.0
	search = WindowSearch.new(here(), to, sim_now(), {"fuel": state.fuel, "ship": state.ship})
	changed.emit()


## Ajaa käynnissä olevan haun loppuun heti (testit).
func finish_search() -> void:
	while search != null and not search.done:
		search.step()
	_process(0.0)


## Kuu tai paluu emoplaneetalle: paikallinen siirto lähtee heti, joten vaihtoehtoja on yksi.
func local_option(to: String) -> void:
	search = null
	target = to
	var tr := Flight.local_transfer(state.location, to, sim_now() + 60000.0)
	var o := {"kind": "local"}
	o.merge(tr)
	o.fuelOk = float(tr.dvTotal) <= float(state.fuel)
	options = [o]
	options_ready = true
	changed.emit()


func _plan_from(tr: Dictionary) -> Dictionary:
	var plan := tr.duplicate()
	for k: String in ["kind", "fuelOk", "r2", "v2"]:
		plan.erase(k)
	return plan


## Valitsee reittivaihtoehdon. Haun aikana kello on edennyt: jo mennyt lähtö siirretään tähän hetkeen samalla
## lentoajalla. Palauttaa false, jos ikkuna ehti mennä ohi.
func choose(o: Dictionary) -> bool:
	var now := sim_now()
	var late: bool = float(o.depart) - float(o.get("spiralOut", 0.0)) < now
	var tr := o
	if o.get("local", false):
		tr = Flight.local_transfer(o.from, o.to, now + 60000.0)
	elif late and o.get("kind") == "assist":
		tr = Flight.assist_transfer(o.from, o.via, o.to, now, (float(o.flyby.t) - float(o.depart)) / DAY,
			(float(o.arrive) - float(o.flyby.t)) / DAY, o.ship)
	elif late:
		tr = Flight.transfer(o.from, o.to, now + float(o.get("spiralOut", 0.0)), (float(o.arrive) - float(o.depart)) / DAY, o.ship)
	if tr.is_empty() or float(tr.dvTotal) > float(state.fuel):
		_set_notice("Ikkuna ehti mennä ohi. Hae reitit uudelleen.")
		options = []
		options_ready = false
		target = ""
		changed.emit()
		return false
	state.plan = _plan_from(tr)
	save_game()
	changed.emit()
	return true


# Suunnitelma uudella lähtöhetkellä: saapuminen (ja mahdollinen ohilento) pysyvät samoina, lähtö siirtyy.
func _replan(p: Dictionary, depart: float) -> Dictionary:
	if p.get("local", false):
		return Flight.local_transfer(p.from, p.to, depart)
	var fb: Variant = p.get("flyby")
	if fb is Dictionary:
		return Flight.assist_transfer(p.from, fb.body, p.to, depart, (float(fb.t) - depart) / DAY, (float(p.arrive) - float(fb.t)) / DAY, p.ship)
	return Flight.transfer(p.from, p.to, depart, (float(p.arrive) - depart) / DAY, p.ship)


## Lähtöpoltto päälle: lasketaan hetki, jolloin alus on pysäköintiradalla polttokohdassa, ja siirtorata ratkaistaan
## uudelleen sille hetkelle (kahdesti, koska polttokohta riippuu lähtösuunnasta). Auringon kiertoradalta ja kuiden
## väleillä poltto tehdään heti lyhyen lähtölaskennan jälkeen. Palauttaa false, jos polttoaine ei riitä.
func arm() -> bool:
	var p: Dictionary = state.plan
	var now := sim_now()
	var orbital: bool = Flight.is_planet(p.from) and not p.get("local", false)
	var depart := now + ARM_LEAD
	var tr: Dictionary = p if orbital else _replan(p, depart)
	# Kuuhun tai kuusta: poltto siinä pysäköintiradan kohdassa, josta siirtorata (tai lähtöhyperbeli) alkaa.
	if p.get("local", false) and state.orbit != null:
		for i in 2:
			var from: String = p.from
			var want: float
			if tr.toMoon:
				want = float(tr.apoAngle) + PI
			else:
				var vinf := Flight.sub(Flight.ship_state(tr, tr.depart).v, Flight.body_state(from, tr.depart).v)
				var o := Flight.orbit_of(from)
				var e: float = 1.0 + float(o.periKm) * Flight.dot(vinf, vinf) / float(o.mu)
				want = atan2(vinf[1], vinf[0]) - acos(-1.0 / e)
			depart = Flight.angle_time(from, want, now + ARM_LEAD, state.orbit)
			tr = _replan(p, depart)
	if orbital:
		for i in 2:
			if tr.is_empty():
				break
			var vinf := Flight.sub(tr.v1, Flight.body_state(p.from, tr.depart).v)
			depart = Flight.injection_time(p.from, vinf, now + ARM_LEAD, state.orbit)
			tr = _replan(p, depart)
	# Lähdön siirtyminen muuttaa Δv:tä hieman; pieni ylitys (alle 0,05 km/s) pyöristetään polttoaineen mukaan.
	if tr.is_empty() or float(tr.dvTotal) > float(state.fuel) + 0.05:
		_set_notice("Polttoaine ei riitä lähtöön tästä kohdasta rataa. Peru lento ja hae reitit uudelleen.")
		changed.emit()
		return false
	var over := maxf(0.0, float(tr.dvTotal) - float(state.fuel))
	var plan := _plan_from(tr)
	plan.dvDep = float(tr.dvDep) - over
	plan.dvTotal = float(tr.dvTotal) - over
	plan.armed = true
	plan.window = p
	state.plan = plan
	_set_notice("")
	anchor(now, 0)
	changed.emit()
	return true


func disarm() -> void:
	state.plan = state.plan.window
	_set_notice("")
	save_game()
	changed.emit()


func cancel_plan() -> void:
	state.plan = null
	options = []
	options_ready = false
	target = ""
	save_game()
	changed.emit()


## Siirtyy laukaisuikkunan (tai ionialuksen spiraalin) alkuun.
func jump_to_window() -> void:
	anchor(hold_at(), 0)
	changed.emit()


func start_spiral() -> void:
	var p: Dictionary = state.plan
	p.spiralStarted = true
	state.fuel = maxf(0.0, float(state.fuel) - float(p.dvDep))
	log_event(sim_now(), "Spiraalinousu alkoi %s kohti %s (Δv %s)" % [Fmt.from_text(p.from), Fmt.par(p.to), Fmt.dv(p.dvDep)])
	save_game()
	changed.emit()


## Lähtöpoltto tai ionialuksen spiraalin päättyminen: siirtorata alkaa.
func launch() -> void:
	var p: Dictionary = state.plan.duplicate()
	p.erase("armed")
	p.erase("window")
	_set_notice("")
	# Ionialuksen polttoaine kului jo spiraalinousussa, eikä hiljainen ionimoottori täräytä ohjaamoa.
	if not p.get("spiralStarted", false):
		state.fuel = maxf(0.0, float(state.fuel) - float(p.dvDep))
		burn_at = real_ms()
	var f := p.duplicate()
	if p.get("local", false):
		f.soi = p.arrive
		f.exit = p.depart
	else:
		f.soi = Flight.soi_entry(p)
		f.exit = Flight.soi_exit(p)
	state.flight = f
	state.plan = null
	state.drift = null
	state.location = null
	state.orbit = null
	state.lowOrbit = null
	_sync_low_orbit()
	var text: String
	if p.get("spiralStarted", false):
		text = "Spiraalinousu valmis, siirtorata kohti %s alkoi" % Fmt.par(p.to)
	else:
		var fb: Variant = p.get("flyby")
		text = "Lähtöpoltto %s kohti %s%s (Δv %s)" % [Fmt.from_text(p.from), Fmt.par(p.to),
			" %s kautta" % Fmt.gen(fb.body) if fb is Dictionary else "", Fmt.dv(p.dvDep)]
	log_event(p.depart, text)
	anchor(p.depart, 0)
	departure_burn.emit(f)
	changed.emit()


# --- Lento ---

## Linkous: ohilennon poltto (jos tarvitaan) tehdään perikeskuksessa.
func flyby_done() -> void:
	var f: Dictionary = state.flight
	var fb: Dictionary = f.flyby.duplicate()
	fb.done = true
	f.flyby = fb
	if float(fb.dv) > 0.005:
		burn_at = real_ms()
	state.fuel = maxf(0.0, float(state.fuel) - float(fb.dv))
	log_event(fb.t, "Linkous %s ohi %s korkeudelta%s" % [Fmt.gen(fb.body), Fmt.km(float(fb.rpKm) - float(Flight.body(fb.body).radiusKm)),
		" (Δv %s)" % Fmt.dv(fb.dv) if float(fb.dv) > 0.005 else ""])
	_set_notice("")
	save_game()
	flyby.emit(fb.body)
	changed.emit()


## Kurssikorjaus valittuun suuntaan. Palauttaa false, jos polttoaine ei riitä.
func burn(direction: String, dv_kms: float, label: String = "") -> bool:
	if state.flight == null or float(state.fuel) < dv_kms:
		return false
	var now := sim_now()
	state.fuel = float(state.fuel) - dv_kms
	state.flight = Flight.apply_burn(state.flight, now, direction, dv_kms)
	var names := {"prograde": "eteen", "retrograde": "taakse", "inward": "sisään", "outward": "ulos"}
	log_event(now, "Kurssikorjaus: %s %s" % [label if label != "" else Fmt.dv(dv_kms), names.get(direction, direction)])
	# Lyhyt tärinä polton merkiksi: polton tärinän viimeinen sekunti.
	burn_at = real_ms() - (BURN_SHAKE_MS - 1000.0)
	_set_notice("")
	save_game()
	course_burn.emit(dv_kms)
	changed.emit()
	return true


## Automaattisen kurssikorjauksen ehdotus {flight, dv} tai tyhjä, jos korjausta ei tarvita (rata osuu ja on
## alkuperäinen) tai sitä ei löydy.
func auto_correction() -> Dictionary:
	var f: Variant = state.flight
	if f == null or f.get("local", false):
		return {}
	var legs: Variant = f.get("legs")
	if not ((legs is Array and legs.size() > 1) or f.get("miss", false)):
		return {}
	var fix := Flight.auto_correct(f, sim_now())
	return fix if not fix.is_empty() and float(fix.dv) > 0.0005 else {}


func auto_correct() -> bool:
	var fix := auto_correction()
	if fix.is_empty() or float(state.fuel) < float(fix.dv):
		return false
	state.fuel = float(state.fuel) - float(fix.dv)
	state.flight = fix.flight
	log_event(sim_now(), "Automaattinen kurssikorjaus kohti %s (Δv %s)" % [Fmt.par(state.flight.to), Fmt.dv(fix.dv)])
	save_game()
	course_burn.emit(fix.dv)
	changed.emit()
	return true


## Ilmajarrutus on mahdollinen: jättiläisplaneetta, ei ionialusta, rata osuu ja polttoaine riittää radan nostoon.
func can_aerobrake() -> bool:
	var f: Variant = state.flight
	if f == null or not Flight.has_low_orbit(f.to) or float(f.get("spiralIn", 0.0)) > 0.0 or f.get("miss", false) or f.get("local", false):
		return false
	return float(state.fuel) >= Flight.aerobrake_dv(f.to)


## Saapuminen: jarrutus kiertoradalle moottorilla tai ilmajarrutuksella (aero), tai ohilento, jos polttoaine ei
## riitä. Lento kirjataan lokikirjaan.
func capture(aero: bool = false) -> void:
	var f: Dictionary = state.flight
	var to: String = f.to
	var cost: float = Flight.aerobrake_dv(to) if aero else float(f.dvArr)
	var captured: bool = not f.get("miss", false) and float(state.fuel) >= cost - 1e-9
	var stats := Flight.flight_stats(f)
	state.flights.append({"fromName": f.from if Flight.is_planet(f.from) else "Auringon kiertorata", "to": to,
		"depart": f.depart, "arrive": f.arrive, "km": stats.km, "maxSpeed": stats.maxSpeed, "captured": captured})
	var arrive: float = f.arrive
	if captured:
		state.fuel = maxf(0.0, float(state.fuel) - cost)
		state.location = to
		state.drift = null
		state.lowOrbit = to if aero else null
		_sync_low_orbit()
		# Alus jää radalle siihen kohtaan, johon se saapui: jarrutuspoltto tehdään perikeskuksessa.
		state.orbit = Flight.orbit_at(to, Flight.ship_view(f, arrive).r, arrive)
		if aero:
			aero_at = real_ms()
		elif float(f.get("spiralIn", 0.0)) <= 0.0:
			burn_at = real_ms()
		var span := arrive - float(f.depart)
		var took := Fmt.short_duration(span) if span < 2.0 * DAY else Fmt.days(span / DAY)
		if aero:
			log_event(arrive, "Ilmajarrutus %s kaasukehässä %s lennon jälkeen: matalalla radalla %s (Δv %s)" % [Fmt.gen(to), took, Fmt.orbit_text(to), Fmt.dv(cost)])
		else:
			log_event(arrive, "Saapuminen %s kiertoradalle %s lennon jälkeen (Δv %s)" % [Fmt.gen(to), took, Fmt.dv(cost)])
		# Ionialus laskeutuu kiertoradalle spiraalina, joka kestää kuten kartoitus.
		if float(f.get("spiralIn", 0.0)) > 0.0:
			state.survey = {"kind": "spiral", "body": to, "start": arrive, "dur": f.spiralIn}
	else:
		var s := Flight.ship_state(f, arrive)
		state.location = null
		state.drift = {"r": s.r, "v": s.v, "t": arrive}
		if f.get("miss", false):
			log_event(arrive, "Ohilento: %s ohitettiin %s etäisyydeltä" % [to, Fmt.km(f.missKm)])
		else:
			log_event(arrive, "Ohilento: polttoaine ei riittänyt jarrutukseen %s kiertoradalle" % Fmt.gen(to))
	state.flight = null
	options = []
	options_ready = false
	target = ""
	_set_notice("")
	anchor(arrive, 0)
	capture_done.emit(to, captured, aero and captured)
	changed.emit()


# --- Perillä ---

func start_survey() -> void:
	if state.location == null or state.survey != null:
		return
	state.survey = {"kind": "survey", "body": state.location, "start": sim_now()}
	save_game()
	changed.emit()


func finish_survey() -> void:
	var sv: Dictionary = state.survey
	var name: String = sv.body
	var end: float = float(sv.start) + float(sv.get("dur", SURVEY_MS) if sv.get("dur") != null else SURVEY_MS)
	state.survey = null
	_set_notice("")
	if sv.kind == "spiral":
		log_event(end, "Spiraalilasku valmis: %s kiertoradalla" % Fmt.gen(name))
		save_game()
		survey_finished.emit(name, false)
		changed.emit()
		return
	var explored: Array = state.explored
	var first := not explored.has(name)
	var refuel := Flight.can_refuel(state.ship, name)
	if first:
		explored.append(name)
	if refuel:
		state.fuel = fuel_max()
	var planets := explored.filter(func(n: String) -> bool: return not Flight.is_moon(n)).size()
	var moons := explored.filter(func(n: String) -> bool: return Flight.is_moon(n)).size()
	var count := "%d/%d kuuta" % [moons, Flight.MOONS.size()] if Flight.is_moon(name) else "%d/8 planeettaa" % planets
	if first:
		log_event(end, "%s tutkittu (%s)%s" % [name, count, ", polttoaine täydennetty" if refuel else ""])
	else:
		log_event(end, "Tankkaus %s kiertoradalla" % Fmt.gen(name))
	if first and not Flight.is_moon(name) and planets == 8:
		log_event(end, "Kaikki aurinkokunnan planeetat on tutkittu!")
	save_game()
	survey_finished.emit(name, first)
	changed.emit()


## Aluksen vaihto Maan kiertoradalla tai laukaisualustalla. Uusi alus on täyteen tankattu.
func change_ship(id: String) -> void:
	if id == state.ship or not Flight.SHIPS.has(id) or state.location != "Maa":
		return
	var ship: Dictionary = Flight.SHIPS[id]
	state.ship = id
	state.fuel = ship.fuel
	options = []
	options_ready = false
	target = ""
	log_event(sim_now(), "Vaihdettiin alukseen: %s (%s km/s)" % [ship.name, Fmt.num(ship.fuel)])
	save_game()
	changed.emit()


# --- Pelisilmukka ---

func _once(key: String) -> bool:
	if _emitted.has(key):
		return false
	_emitted[key] = true
	return true


## Tapahtumien käsittely kellon mukaan (joka ruutu).
func tick() -> void:
	var t := sim_now()
	var a: Variant = state.ascent
	if a != null and t >= float(a.liftoff) and _once("liftoff %s" % a.liftoff):
		liftoff.emit()
	if a != null and t >= float(a.liftoff) + Flight.ASCENT_S * 1000.0:
		reach_orbit()
	var plan: Variant = state.plan
	if plan != null and plan.get("armed", false) and t >= float(plan.depart):
		launch()
	limit_warp(t)
	var f: Variant = state.flight
	if f != null:
		var fb: Variant = f.get("flyby")
		if fb is Dictionary and not fb.get("done", false) and t >= float(fb.t):
			flyby_done()
		if not f.get("local", false) and t >= float(f.soi) and not f.get("miss", false) and _once("soi %s %s" % [f.depart, f.soi]):
			soi_entered.emit(f.to)
		if t >= float(f.arrive) and _once("arrived %s %s" % [f.depart, f.arrive]):
			arrived.emit(f.to)
	plan = state.plan
	if plan != null and plan.get("spiralStarted", false) and t >= float(plan.depart):
		launch()
	var sv: Variant = state.survey
	if sv != null and t >= float(sv.start) + float(sv.get("dur") if sv.get("dur") != null else SURVEY_MS):
		finish_survey()
	if real_ms() - _last_save > AUTOSAVE_MS:
		save_game()
