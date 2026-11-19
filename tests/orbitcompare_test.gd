extends TestCase
## Vertailutesti: Godot-version ratamekaniikka antaa samat tulokset kuin selainversio (web/js/flight.js).
## Vertailuarvot: tests/data/orbit_reference.json (tools/make_orbit_reference.mjs).
## Radat suhteellisella tarkkuudella 1e-9, haut 1e-6.
##   godot --headless -- --orbitcomparetest

const ORBIT_TOL := 1e-9
const SEARCH_TOL := 1e-6

var ref: Dictionary
var _errors: PackedStringArray = []


func _ready() -> void:
	var text := FileAccess.get_file_as_string("res://tests/data/orbit_reference.json")
	ref = JSON.parse_string(text)
	_planets()
	_kepler_and_orbits()
	_transfers()
	_searches()
	_launch_and_parking()
	_course()
	finish()


# Vertaa Godotin tulosta (got) JS:n tulokseen (want) rekursiivisesti. Luvut suhteellisella tarkkuudella tol
# (pienet luvut absoluuttisesti tol·scale), merkkijonot ja totuusarvot tarkasti; JS:n null = tyhjä sanakirja.
func same(name: String, got: Variant, want: Variant, tol: float = ORBIT_TOL, scale: float = 0.0) -> void:
	_errors.clear()
	_cmp(got, want, tol, scale, "")
	check(name + ("" if _errors.is_empty() else " — " + ", ".join(_errors.slice(0, 4))), _errors.is_empty())


func _cmp(got: Variant, want: Variant, tol: float, scale: float, path: String) -> void:
	if want == null:
		if not (got == null or (got is Dictionary and got.is_empty())):
			_errors.append("%s: odotettiin null" % path)
		return
	if want is String and (want == "Infinity" or want == "-Infinity"):
		if not (got is float and is_inf(got) and (got > 0) == (want == "Infinity")):
			_errors.append("%s: %s ≠ %s" % [path, got, want])
		return
	if want is float or want is int:
		if not (got is float or got is int):
			_errors.append("%s: ei luku (%s)" % [path, type_string(typeof(got))])
			return
		var a := float(got)
		var b := float(want)
		if absf(a - b) > tol * maxf(maxf(absf(a), absf(b)), scale):
			_errors.append("%s: %s ≠ %s" % [path, a, b])
		return
	if want is Array:
		if not (got is Array or got is PackedFloat64Array) or got.size() != want.size():
			_errors.append("%s: pituus %s ≠ %d" % [path, got.size() if (got is Array or got is PackedFloat64Array) else -1, want.size()])
			return
		# Vektorin komponentit verrataan vektorin pituuden mittakaavassa (nollan lähellä olevat komponentit).
		var mag := 0.0
		for x: Variant in want:
			if x is float or x is int:
				mag = maxf(mag, absf(x))
		for i in want.size():
			_cmp(got[i], want[i], tol, maxf(scale, mag), "%s[%d]" % [path, i])
		return
	if want is Dictionary:
		if not got is Dictionary:
			_errors.append("%s: ei sanakirja" % path)
			return
		for k: String in want:
			if not got.has(k):
				_errors.append("%s.%s puuttuu" % [path, k])
			else:
				_cmp(got[k], want[k], tol, scale, "%s.%s" % [path, k])
		return
	if got != want:
		_errors.append("%s: %s ≠ %s" % [path, got, want])


func _planets() -> void:
	for c: Dictionary in ref.planets:
		var label := "%s %d" % [c.name, int(c.time)]
		var el := Planets.elements(c.name, c.time)
		same("rata-alkiot " + label, el, c.elements)
		same("helioState " + label, Planets.helio_state(c.name, c.time), c.state)
		same("helio " + label, Planets.helio(c.name, c.time), c.helio)
	for name: String in ref.soi:
		same("vaikutuspiiri " + name, Flight.body(name).soiKm, ref.soi[name])


func _kepler_and_orbits() -> void:
	for c: Dictionary in ref.kepler:
		same("Kepler M=%s e=%s" % [c.M, c.e], Planets.eccentric_anomaly(c.M, c.e), c.E)
	for c: Dictionary in ref.propagate:
		same("propagate %s %s" % [c.v0, c.dt], Flight.propagate(c.r0, c.v0, c.dt, c.mu), c.result)
	for c: Dictionary in ref.lambert:
		same("Lambert %s %s" % [c.r2, c.tof], Flight.lambert(c.r1, c.r2, c.tof), c.result)
	for c: Dictionary in ref.flyby:
		same("ohilento %s %s" % [c.via, c.vout], Flight.flyby_dv(c.via, c.vin, c.vout), c.result)
	for c: Dictionary in ref.aero:
		same("ilmajarrutus " + c.body, Flight.aerobrake_dv(c.body), c.dv)
		same("lähtö kaappausradalta " + c.body, Flight.burn_dv(c.body, 5.5), c.high)
	for c: Array in ref.fmt:
		check("fmtDuration %s" % c[0], Flight.fmt_duration(c[0]) == c[1])


func _transfers() -> void:
	for c: Dictionary in ref.transfer:
		same("transfer %s→%s %s" % [c.from, c.to, c.ship], Flight.transfer(c.from, c.to, c.depart, c.tof, c.ship), c.result)
	for c: Dictionary in ref.assist:
		same("assistTransfer %s→%s→%s" % [c.from, c.via, c.to], Flight.assist_transfer(c.from, c.via, c.to, c.depart, c.tof1, c.tof2), c.result)
	for c: Dictionary in ref.local:
		var tr := Flight.local_transfer(c.from, c.to, c.depart)
		same("localTransfer %s→%s" % [c.from, c.to], tr, c.result)
		same("localTransfer keskellä %s→%s" % [c.from, c.to], Flight.ship_state(tr, (float(tr.depart) + float(tr.arrive)) / 2.0), c.mid)


func _searches() -> void:
	for c: Dictionary in ref.searches:
		var label := "haku %s→%s %s" % [c.from if c.from is String else "rata", c.to, JSON.stringify(c.opts)]
		var search := WindowSearch.new(c.from, c.to, c.start, c.opts)
		var progress: Array = []
		while not search.done:
			progress.append(search.step())
		# Godotissa suoran haun tarkennus on oma askeleensa (sama edistyminen kahdesti), ja viimeinen askel palauttaa 1.
		var deduped: Array = []
		for p: float in progress:
			if deduped.is_empty() or p != deduped[-1]:
				deduped.append(p)
		var want_progress: Array = c.progress
		check(label + " edistyminen päättyy 1:een", progress[-1] == 1.0)
		same(label + " edistyminen", deduped.slice(0, want_progress.size()), want_progress, 1e-12)
		var kinds := search.result.map(func(o: Dictionary) -> String: return o.kind)
		var want_kinds: Array = c.result.map(func(o: Dictionary) -> String: return o.kind)
		check(label + " vaihtoehdot %s" % [kinds], kinds == want_kinds)
		same(label + " tulokset", search.result, c.result, SEARCH_TOL)


func _launch_and_parking() -> void:
	for c: Dictionary in ref.launch:
		same("launchState %s" % c.time, Flight.launch_state(c.liftoff, c.time), c.result)
	same("launchOrbit", Flight.launch_orbit(ref.launchOrbit.liftoff), ref.launchOrbit.result)
	for c: Dictionary in ref.parking:
		same("parkingState %s %s" % [c.body, c.orbit], Flight.parking_state(c.body, c.time, c.orbit), c.result)
		same("orbitPeriod " + c.body, Flight.orbit_period(c.body), c.period)
	for c: Dictionary in ref.injection:
		same("injectionTime " + c.body, Flight.injection_time(c.body, c.vinf, c.after, c.orbit), c.result)
	var oa: Dictionary = ref.orbitAt
	same("orbitAt", Flight.orbit_at(oa.body, oa.r, oa.time), oa.result)


func _course() -> void:
	var c: Dictionary = ref.course[0]
	var tr: Dictionary = c.flight
	var mid: float = c.mid
	# Ohitusetäisyys (missKm, distance) on osumassa lähes nolla: verrataan kilometrin sadastuhannesosan tarkkuudella.
	same("predict", Flight.predict(tr, mid), c.predict, ORBIT_TOL, 1e4)
	var burned := Flight.apply_burn(tr, mid, "prograde", 0.5)
	same("applyBurn", burned, c.burned)
	same("autoCorrect", Flight.auto_correct(burned, mid + 5.0 * Flight.DAY_MS), c.fix, ORBIT_TOL, 1e4)
	var s := Flight.ship_state(tr, mid)
	for i in Flight.BURN_DIRECTIONS.size():
		same("burnVector " + Flight.BURN_DIRECTIONS[i], Flight.burn_vector(s, Flight.BURN_DIRECTIONS[i], 0.7), c.vectors[i])
	same("soiEntry", Flight.soi_entry(tr), c.soiEntry)
	same("soiExit", Flight.soi_exit(tr), c.soiExit)
	same("flightStats", Flight.flight_stats(tr), c.stats)
	same("flightStats korjattu", Flight.flight_stats(burned, 500), c.statsBurned)
	same("encounter", Flight.encounter(tr, mid, float(tr.arrive) + 30.0 * Flight.DAY_MS), c.encounter, ORBIT_TOL, 1e4)
	same("nearestPlanet", Flight.nearest_planet(s.r, s.v, mid), c.nearest)
	# shipView-arvoja ei enää verrata: Godot-versiossa ohjaamonäkymän rata on oikea hyperbeli (#20, orbittest).
