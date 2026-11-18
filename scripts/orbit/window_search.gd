class_name WindowSearch
extends RefCounted
## Laukaisuikkunoiden haku lähtöpaikasta from planeetalle to alkaen hetkestä start (ms), days vuorokauden ajalta
## (web/js/flight.js: windowSearch ja assistSearch). Haku ei jäädytä peliä: jokainen step() laskee yhden
## lähtöpäivän rivin ja palauttaa edistymisen (0–1), kuten JS:n generaattori. run(budget_ms) laskee rivejä, kunnes
## aikabudjetti on käytetty. Valmiina done = true ja result = vaihtoehdot halvimmasta alkaen: halvin (cheapest),
## nopeampi (faster, lentoaika enintään 70 % halvimman lentoajasta), aikaisin perillä polttoaineella fuel (earliest)
## ja yhden painovoimalinkouksen reitti (assist), jos se on halvempi tai ehtii perille selvästi aiemmin.
## opts: days (730), fuel (14), ship ("kemiallinen"), assists (true).

# Hakuruudukko: lähtöpäiviä ja lentoaikoja. Linkoushaussa harvempi ruudukko (lähtö, kaksi lentoaikaa).
const DEP_STEPS := 150
const TOF_STEPS := 40
const ASSIST_D := 40
const ASSIST_T := 12
const DAY_MS := Flight.DAY_MS

var from: Variant
var to: String
var start: float
var days: float
var fuel: float
var ship: String
var assists: bool

var done := false
var progress := 0.0
var result: Array = []

var _tof_min: float
var _tof_max: float
var _d_step: float
var _t_step: float
var _grid: Array[PackedFloat64Array] = [] # [dep, tof, cost]
var _row := 0
var _options: Array = []
var _cheapest: Dictionary = {}
# Linkoushaku
var _phase := 0 # 0 suora ruudukko ja sen tarkennus, 1 linkous, 2 valmis
var _vias: PackedStringArray = []
var _via_index := 0
var _via_row := 0
var _via_r1: PackedFloat64Array
var _via_r2: PackedFloat64Array
var _via_step: PackedFloat64Array
var _via_local: PackedFloat64Array = [] # [dep, tof1, tof2, cost]
var _assist_best: Dictionary = {}


func _init(p_from: Variant, p_to: String, p_start: float, opts: Dictionary = {}) -> void:
	from = p_from
	to = p_to
	start = p_start
	days = float(opts.get("days", 730.0))
	fuel = float(opts.get("fuel", Flight.FUEL_KMS))
	ship = String(opts.get("ship", "kemiallinen"))
	assists = bool(opts.get("assists", true))
	# Hohmannin lentoaika antaa haun mittakaavan; Auringon kiertoradalla isoakselin puolikas saadaan energiasta.
	var a1: float
	if Flight.is_planet(from):
		a1 = Planets.elements(from, start).a * Flight.AU_KM
	else:
		var s := Flight.departure_state(from, start)
		var e: float = Flight.invariants(s.r, s.v).energy
		a1 = -Flight.MU_SUN / (2.0 * e) if e < 0.0 else Flight.norm(s.r)
	var a2: float = Planets.elements(to, start).a * Flight.AU_KM
	var th: float = Flight.hohmann(a1, a2).tof / Flight.DAY_S
	_tof_min = maxf(20.0, th * 0.35)
	_tof_max = th * 1.15
	_d_step = days / DEP_STEPS
	_t_step = (_tof_max - _tof_min) / TOF_STEPS


## Laskee yhden rivin ja palauttaa edistymisen 0–1.
func step() -> float:
	if done:
		return progress
	if _phase == 0:
		if _row > DEP_STEPS:
			_finish_direct() # vaihtoehtojen tarkennus omana askeleenaan
		else:
			_grid_row()
	elif _phase == 1:
		_assist_row()
	return progress


## Laskee rivejä, kunnes budget_ms millisekuntia on kulunut tai haku valmistuu. Palauttaa edistymisen.
func run(budget_ms: float) -> float:
	var t0 := Time.get_ticks_usec()
	while not done and (Time.get_ticks_usec() - t0) < budget_ms * 1000.0:
		step()
	return progress


func _grid_row() -> void:
	var i := _row
	for j in TOF_STEPS + 1:
		var dep := i * _d_step
		var tof := _tof_min + j * _t_step
		var tr := Flight.transfer(from, to, start + dep * DAY_MS, tof, ship)
		# Ionialuksen spiraalinousun täytyy ehtiä ennen lähtöä.
		if not tr.is_empty() and float(tr.spiralOut) <= dep * DAY_MS:
			_grid.append(PackedFloat64Array([dep, tof, tr.dvTotal]))
	progress = 0.4 * i / DEP_STEPS
	_row += 1


# Lento ruudukon rajojen sisällä tai tyhjä.
func _at(dep: float, tof: float) -> Dictionary:
	if dep < 0.0 or dep > days or tof < _tof_min or tof > _tof_max:
		return {}
	var tr := Flight.transfer(from, to, start + dep * DAY_MS, tof, ship)
	return tr if not tr.is_empty() and float(tr.spiralOut) <= dep * DAY_MS else {}


func _dv(dep: float, tof: float) -> float:
	var tr := _at(dep, tof)
	return INF if tr.is_empty() else float(tr.dvTotal)


# Paras ruudukon piste kustannuksella cost(dep, tof), tarkennettuna kuvioetsinnällä.
func _pick(points: Array[PackedFloat64Array], cost: Callable) -> Dictionary:
	if points.is_empty():
		return {}
	var p := points[0]
	var pc: float = cost.call(p[0], p[1])
	for q in points:
		var qc: float = cost.call(q[0], q[1])
		if qc < pc:
			p = q
			pc = qc
	if not is_finite(pc):
		return {}
	var x := Flight.refine_n(func(v: PackedFloat64Array) -> float: return cost.call(v[0], v[1]),
		PackedFloat64Array([p[0], p[1]]), PackedFloat64Array([_d_step, _t_step]))
	return _at(x[0], x[1])


func _finish_direct() -> void:
	if _grid.is_empty():
		_finish([])
		return
	_cheapest = _pick(_grid, _dv)
	if _cheapest.is_empty():
		_finish([])
		return
	var limit := 0.7 * (float(_cheapest.arrive) - float(_cheapest.depart)) / DAY_MS
	var fast_points: Array[PackedFloat64Array] = _grid.filter(func(p: PackedFloat64Array) -> bool: return p[1] <= limit)
	var faster := _pick(fast_points, func(dep: float, tof: float) -> float: return INF if tof > limit else _dv(dep, tof))
	var fuel_points: Array[PackedFloat64Array] = _grid.filter(func(p: PackedFloat64Array) -> bool: return p[2] <= fuel)
	var earliest := _pick(fuel_points, func(dep: float, tof: float) -> float: return dep + tof if _dv(dep, tof) <= fuel else INF)
	_options = [_with_kind("cheapest", _cheapest)]
	if not faster.is_empty():
		_options.append(_with_kind("faster", faster))
	# Aikaisin perille ehtivä vaihtoehto näytetään vain, jos se eroaa muista selvästi.
	if not earliest.is_empty():
		var distinct := true
		for o: Dictionary in _options:
			if absf(float(o.arrive) - float(earliest.arrive)) <= 5.0 * DAY_MS:
				distinct = false
		if distinct:
			_options.append(_with_kind("earliest", earliest))
	if assists and Flight.is_planet(from) and Flight.ship_accel(ship) == 0.0:
		for n in Planets.NAMES:
			if n != from and n != to:
				_vias.append(n)
		_phase = 1
		_start_via()
	else:
		_finish(_options)


func _with_kind(kind: String, tr: Dictionary) -> Dictionary:
	var o := {"kind": kind}
	o.merge(tr)
	return o


func _finish(options: Array) -> void:
	for o: Dictionary in options:
		o.fuelOk = float(o.dvTotal) <= fuel
	result = options
	progress = 1.0
	done = true
	_phase = 2


# --- Painovoimalinkous: halvin yhden linkouksen reitti, kun ohilentoplaneetaksi kokeillaan jokaista muuta planeettaa ---

func _a_km(name: String) -> float:
	return Planets.elements(name, start).a * Flight.AU_KM


func _start_via() -> void:
	var via := _vias[_via_index]
	var t1: float = Flight.hohmann(_a_km(from), _a_km(via)).tof / Flight.DAY_S
	var t2: float = Flight.hohmann(_a_km(via), _a_km(to)).tof / Flight.DAY_S
	_via_r1 = PackedFloat64Array([maxf(20.0, t1 * 0.3), t1 * 1.2])
	_via_r2 = PackedFloat64Array([maxf(20.0, t2 * 0.3), t2 * 1.2])
	_via_step = PackedFloat64Array([days / ASSIST_D, (_via_r1[1] - _via_r1[0]) / ASSIST_T, (_via_r2[1] - _via_r2[0]) / ASSIST_T])
	_via_row = 0
	_via_local = PackedFloat64Array()


func _assist_row() -> void:
	var via := _vias[_via_index]
	var i := _via_row
	for j in ASSIST_T + 1:
		for k in ASSIST_T + 1:
			var x0 := i * _via_step[0]
			var x1 := _via_r1[0] + j * _via_step[1]
			var x2 := _via_r2[0] + k * _via_step[2]
			var tr := Flight.assist_transfer(from, via, to, start + x0 * DAY_MS, x1, x2, ship)
			if not tr.is_empty() and (_via_local.is_empty() or float(tr.dvTotal) < _via_local[3]):
				_via_local = PackedFloat64Array([x0, x1, x2, tr.dvTotal])
	_via_row += 1
	progress = 0.4 + 0.6 * (_via_index + float(_via_row) / (ASSIST_D + 1)) / _vias.size()
	if _via_row <= ASSIST_D:
		return
	if not _via_local.is_empty():
		var cost := func(x: PackedFloat64Array) -> float:
			if x[0] < 0.0 or x[0] > days or x[1] < _via_r1[0] or x[1] > _via_r1[1] or x[2] < _via_r2[0] or x[2] > _via_r2[1]:
				return INF
			var t := Flight.assist_transfer(from, via, to, start + x[0] * DAY_MS, x[1], x[2], ship)
			return INF if t.is_empty() else float(t.dvTotal)
		var x := Flight.refine_n(cost, _via_local.slice(0, 3), _via_step)
		var tr := Flight.assist_transfer(from, via, to, start + x[0] * DAY_MS, x[1], x[2], ship)
		if not tr.is_empty() and (_assist_best.is_empty() or float(tr.dvTotal) < float(_assist_best.dvTotal)):
			_assist_best = tr
	_via_index += 1
	if _via_index < _vias.size():
		_start_via()
		return
	# Linkousreitti näytetään, jos se on halvin tai ehtii perille aiemmin kuin halvin suora lento.
	var assist := _assist_best
	if not assist.is_empty():
		var cheaper: bool = float(assist.dvTotal) < float(_cheapest.dvTotal) - 0.05
		var sooner: bool = float(assist.arrive) < float(_cheapest.arrive) - 30.0 * DAY_MS and float(assist.dvTotal) <= fuel
		if cheaper or sooner:
			_options.append(_with_kind("assist", assist))
	_finish(_options)
