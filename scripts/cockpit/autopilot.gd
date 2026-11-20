class_name Autopilot
## Korkeudenvakain (#58): pitää aluksen lukitussa korkeudessa kääntämällä nokkaa pystytasossa. Korkeuden erosta
## lasketaan tavoiteltu pystynopeus ja siitä pystykiihtyvyys (kriittisesti vaimennettu), ja nokan kohtauskulma
## haetaan puolitushaulla niin, että painovoima, nostovoima, ilmanvastus ja nokan suuntainen työntö antavat juuri sen.
## Näin vakain toimii yhtä hyvin Maan tiheässä ilmassa, Marsin ohuessa ilmassa ja tyhjiössä (pelkällä työnnöllä).

## Pystynopeuden vahvistus korkeuden erosta (1/s) ja suurin tavoiteltu pystynopeus (km/s).
const ALT_GAIN := 0.1
const VS_MAX := 0.06
## Pystykiihtyvyyden vahvistus pystynopeuden erosta (1/s) ja suurin pystykiihtyvyys (km/s², 2 g).
const VS_GAIN := 0.4
const ACCEL_MAX := 0.0196
## Kohtauskulman rajat (rad): −20° … 35°.
const ALPHA_MIN := -0.35
const ALPHA_MAX := 0.61
## Suurin sivuttainen kulma (rad) kääntymiseen vakaimen ollessa päällä.
const TURN_MAX := 0.26


## Nokan suunta (ekliptika, yksikkövektori) kappaleen name ympärillä tilassa (r, v) (km, km/s kappaleen suhteen),
## kun tavoitekorkeus on target_km pinnasta ja nokan suuntainen työntö thrust km/s². turn −1…1 kääntää nokkaa
## sivulle (vasemmalle +), jolloin nostovoima kaartaa lentorataa.
static func nose(name: String, r: PackedFloat64Array, v: PackedFloat64Array, target_km: float, thrust: float,
		turn: float = 0.0) -> PackedFloat64Array:
	var rn := Flight.norm(r)
	var up := Flight.scale(r, 1.0 / rn)
	var vs := Flight.dot(v, up)
	var alt := rn - float(Flight.orbit_of(name).radiusKm)
	var vs_cmd := clampf((target_km - alt) * ALT_GAIN, -VS_MAX, VS_MAX)
	var a_cmd := clampf((vs_cmd - vs) * VS_GAIN, -ACCEL_MAX, ACCEL_MAX)
	var fr := frame(up, v)
	var vhat: PackedFloat64Array = fr.vhat
	var p: PackedFloat64Array = fr.p
	var side := Flight.cross(up, vhat)
	side = Flight.scale(side, 1.0 / maxf(Flight.norm(side), 1e-9))
	var beta := clampf(turn, -1.0, 1.0) * TURN_MAX
	var mu: float = Flight.orbit_of(name).mu
	var g := Flight.scale(up, -mu / (rn * rn))
	# Pystynopeuden muutos: kiihtyvyyden pystykomponentti + vaakanopeuden keskeisliike (v_h² / r).
	var vh2 := Flight.dot(v, v) - vs * vs
	var accel_up := func(alpha: float) -> float:
		var n := _dir(vhat, p, side, alpha, beta)
		var a := Flight.add(g, Flight.add(Flight.aero(name, r, v, n).a, Flight.scale(n, thrust)))
		return Flight.dot(a, up) + vh2 / rn - a_cmd
	var lo := ALPHA_MIN
	var hi := ALPHA_MAX
	if float(accel_up.call(hi)) < 0.0:
		return _dir(vhat, p, side, hi, beta)
	if float(accel_up.call(lo)) > 0.0:
		return _dir(vhat, p, side, lo, beta)
	for i in 24:
		var mid := (lo + hi) / 2.0
		if float(accel_up.call(mid)) > 0.0:
			hi = mid
		else:
			lo = mid
	return _dir(vhat, p, side, (lo + hi) / 2.0, beta)


## Pystytaso: menosuunta vhat ja sitä vastaan kohtisuora ylöspäin osoittava p. Hyvin pienellä nopeudella tai
## pystysuorassa lennossa menosuunnaksi otetaan vaakasuunta.
static func frame(up: PackedFloat64Array, v: PackedFloat64Array) -> Dictionary:
	var speed := Flight.norm(v)
	var vhat := Flight.scale(v, 1.0 / speed) if speed > 1e-3 else PackedFloat64Array()
	if vhat.is_empty() or absf(Flight.dot(vhat, up)) > 0.999:
		var h := Flight.sub(v, Flight.scale(up, Flight.dot(v, up))) if speed > 1e-3 else PackedFloat64Array([1.0, 0.0, 0.0])
		h = Flight.sub(h, Flight.scale(up, Flight.dot(h, up)))
		if Flight.norm(h) < 1e-9:
			h = Flight.cross(up, PackedFloat64Array([0.0, 0.0, 1.0]))
			if Flight.norm(h) < 1e-9:
				h = PackedFloat64Array([1.0, 0.0, 0.0])
		vhat = Flight.scale(h, 1.0 / Flight.norm(h))
	var p := Flight.sub(up, Flight.scale(vhat, Flight.dot(up, vhat)))
	return {"vhat": vhat, "p": Flight.scale(p, 1.0 / maxf(Flight.norm(p), 1e-9))}


static func _dir(vhat: PackedFloat64Array, p: PackedFloat64Array, side: PackedFloat64Array, alpha: float, beta: float) -> PackedFloat64Array:
	var n := Flight.add(Flight.scale(vhat, cos(alpha) * cos(beta)), Flight.add(Flight.scale(p, sin(alpha) * cos(beta)), Flight.scale(side, sin(beta))))
	return Flight.scale(n, 1.0 / Flight.norm(n))
