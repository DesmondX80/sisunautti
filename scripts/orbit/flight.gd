class_name Flight
## Avaruuslennon ratamekaniikka (web/js/flight.js): Keplerin radan eteneminen, Lambertin ongelma, ratamuutosten Δv,
## linkoukset, kuut, alukset, nousu Maan pinnalta, pysäköintiradat ja kurssikorjaukset.
## Yksiköt: km, km/s ja sekunnit, ellei toisin mainita. Ajanhetket ovat millisekunteja (float, kuten JS:n
## Date.getTime(); 64-bittinen float esittää millisekunnit tarkasti). Koordinaatit ovat Auringon keskisiä ekliptikan
## koordinaatteja (J2000). Vektorit ovat PackedFloat64Array-taulukoita: Vector3 on 32-bittinen eikä riitä kilometreihin.
## Lennot ja muut tulokset ovat sanakirjoja, joiden avaimet ovat samat kuin selainversiossa (camelCase), jotta
## tallennukset ovat yhteensopivia.
## Laukaisuikkunoiden haku on luokassa WindowSearch (window_search.gd), joka jakaa haun ruutujen kesken.

## Auringon gravitaatioparametri GM (km³/s²).
const MU_SUN := 1.32712440018e11
const DAY_S := 86400.0
const DAY_MS := DAY_S * 1000.0
const AU_KM := Planets.AU_KM
const J2000_MS := Planets.J2000_MS
## Raketin Δv-budjetti (km/s) yhdelle lennolle; polttoaine täydentyy, kun planeetta on tutkittu.
const FUEL_KMS := 14.0

# Planeettojen gravitaatioparametrit (km³/s²) ja kiertoradat, joilla alus pysäköidään: [perikeskuksen ja
# apokeskuksen korkeus km]. Kiviplaneetoilla matala ympyrärata noin 500 km korkeudessa, Maassa 200 km.
# Jättiläisplaneetoilla perikeskus on heti pilvien yläpuolella, mutta rata on venynyt; low on matala ympyrärata,
# jolle päästään ilmajarrutuksella (alus sukeltaa noin 200 km pilvien yläpuolelle).
const AERO_ALT_KM := 200.0
const _BODIES := {
	"Merkurius": {"mu": 22031.86, "orbit": [500.0, 500.0]},
	"Venus": {"mu": 324858.59, "orbit": [500.0, 500.0]},
	"Maa": {"mu": 398600.44, "orbit": [200.0, 200.0]},
	"Mars": {"mu": 42828.37, "orbit": [500.0, 500.0]},
	"Jupiter": {"mu": 126686531.9, "orbit": [5000.0, 2000000.0], "low": 5000.0},
	"Saturnus": {"mu": 37931206.2, "orbit": [3000.0, 1500000.0], "low": 3000.0},
	"Uranus": {"mu": 5793951.3, "orbit": [3000.0, 500000.0], "low": 3000.0},
	"Neptunus": {"mu": 6835099.5, "orbit": [3000.0, 500000.0], "low": 3000.0},
}

## Alukset: Δv-budjetti (km/s), kiihtyvyys (km/s², 0 = hetkellinen poltto) ja planeetat, joilla voi tankata
## (tyhjä = kaikilla). Ydinlämpöraketti kuumentaa vetyä reaktorissa, joten sitä saa vain Maasta ja kaasujättiläisistä.
## Ionialuksen työntövoima on pieni: lähtö ja jarrutus ovat spiraaleja, jotka kestävät kuukausia.
const SHIPS := {
	"kemiallinen": {"name": "Kemiallinen raketti", "fuel": 14.0, "accel": 0.0, "refuel": [],
		"text": "Perusalus. Lähtö- ja jarrutuspoltot kestävät minuutteja."},
	"ydin": {"name": "Ydinlämpöraketti", "fuel": 22.0, "accel": 0.0, "refuel": ["Maa", "Jupiter", "Saturnus", "Uranus", "Neptunus"],
		"text": "Enemmän Δv:tä, mutta vetyä voi tankata vain Maassa ja kaasujättiläisillä."},
	"ioni": {"name": "Ionialus", "fuel": 45.0, "accel": 1e-6, "refuel": [],
		"text": "Suuri Δv, mutta työntövoima on pieni (1 mm/s²): lähtö ja jarrutus ovat kuukausien spiraaleja, eikä linkousta voi tehdä."},
}

## Kuut kohteina: emoplaneetta, radan säde (km), säde, gravitaatioparametri (km³/s²), kiertoaika (vrk) ja
## pysäköintiradan korkeus. Rata on yksinkertaistettu ympyräksi ekliptikan tasossa (Triton kiertää takaperin).
const MOONS := {
	"Kuu": {"parent": "Maa", "aKm": 384400.0, "radiusKm": 1737.4, "mu": 4902.8, "periodDays": 27.3217, "altKm": 100.0, "color": "#c9c5bd"},
	"Phobos": {"parent": "Mars", "aKm": 9376.0, "radiusKm": 11.1, "mu": 0.000711, "periodDays": 0.31891, "altKm": 5.0, "color": "#8a7a6a"},
	"Io": {"parent": "Jupiter", "aKm": 421700.0, "radiusKm": 1821.6, "mu": 5959.9, "periodDays": 1.769, "altKm": 100.0, "color": "#e8d36a"},
	"Europa": {"parent": "Jupiter", "aKm": 671034.0, "radiusKm": 1560.8, "mu": 3202.7, "periodDays": 3.551, "altKm": 100.0, "color": "#d9cfc0"},
	"Ganymedes": {"parent": "Jupiter", "aKm": 1070412.0, "radiusKm": 2634.1, "mu": 9887.8, "periodDays": 7.155, "altKm": 100.0, "color": "#a49a8c"},
	"Titan": {"parent": "Saturnus", "aKm": 1221870.0, "radiusKm": 2574.7, "mu": 8978.1, "periodDays": 15.945, "altKm": 800.0, "color": "#d9a54e"},
	"Enceladus": {"parent": "Saturnus", "aKm": 238020.0, "radiusKm": 252.1, "mu": 7.21, "periodDays": 1.370, "altKm": 50.0, "color": "#f2f5f8"},
	"Triton": {"parent": "Neptunus", "aKm": 354759.0, "radiusKm": 1353.4, "mu": 1427.6, "periodDays": -5.877, "altKm": 100.0, "color": "#d8c4c0"},
}

## Polton suunnat: eteen (radan suuntaan), taakse, Aurinkoa kohti (sisään) ja poispäin (ulos).
const BURN_DIRECTIONS: PackedStringArray = ["prograde", "retrograde", "inward", "outward"]

## Nousun kesto laukaisusta kiertoradalle (s) ja tapahtumien hetket: suurin aerodynaaminen kuorma, vaiheen 1
## sammutus ja vaiheen 2 sytytys.
const ASCENT_S := 510.0
const ASCENT_EVENTS := {"maxQ": 70.0, "meco": 150.0, "stage2": 158.0}
# Vaakanopeus kasvaa nousun osuuden potenssina TURN_POWER, jolloin kuljettu kulma kasvaa potenssina TURN_POWER + 1.
const EARTH_SPIN := 2.0 * PI / 86164.1
const PAD_ALT_KM := 0.06
const TURN_POWER := 1.5

static var _flight_bodies: Dictionary = {}


# --- Vektorit (PackedFloat64Array, 3 alkiota) ---

static func vec(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] + b[0], a[1] + b[1], a[2] + b[2]])


static func sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


static func scale(a: PackedFloat64Array, k: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] * k, a[1] * k, a[2] * k])


static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]])


static func norm(a: PackedFloat64Array) -> float:
	return sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])


# JS:n Math.round (puolikkaat ylöspäin), jotta tulokset vastaavat selainversiota.
static func _js_round(x: float) -> float:
	return floor(x + 0.5)


# --- Kappaleet ---

## Planeettojen tiedot lentoa varten: name, radiusKm, mu, vaikutuspiirin säde soiKm = a·(μ/μ☉)^(2/5),
## pysäköintirata periKm ja apoKm (km), capture (kaappausrata) ja low (matala rata tai null).
## Sanakirja on muuttuva: set_low_orbit() vaihtaa periKm/apoKm-arvot.
static func flight_bodies() -> Dictionary:
	if _flight_bodies.is_empty():
		for name in Planets.NAMES:
			var b: Dictionary = _BODIES[name]
			var mu: float = b.mu
			var r := Planets.radius_km(name)
			var a: float = Planets.elements(name, J2000_MS).a * AU_KM
			var capture := {"periKm": r + float(b.orbit[0]), "apoKm": r + float(b.orbit[1])}
			var low: Variant = null
			if b.has("low"):
				low = {"periKm": r + float(b.low), "apoKm": r + float(b.low)}
			_flight_bodies[name] = {"name": name, "radiusKm": r, "mu": mu, "soiKm": a * pow(mu / MU_SUN, 0.4),
				"periKm": capture.periKm, "apoKm": capture.apoKm, "capture": capture, "low": low}
	return _flight_bodies


static func body(name: String) -> Dictionary:
	return flight_bodies()[name]


## Onko planeetalla matala ympyrärata, jolle pääsee ilmajarrutuksella.
static func has_low_orbit(name: String) -> bool:
	return flight_bodies().has(name) and body(name).low != null


## Valitsee, kummalla radalla alus on planeetan luona: matalalla ympyräradalla (low = true) vai kaappausradalla.
static func set_low_orbit(name: String, low: bool) -> void:
	if not has_low_orbit(name):
		return
	var b := body(name)
	var src: Dictionary = b.low if low else b.capture
	b.periKm = src.periKm
	b.apoKm = src.apoKm


## Ilmajarrutuksen jälkeinen poltto (km/s): apokeskuksessa perikeskus nostetaan matalan radan korkeudelle:
## Δv = v_ympyrä·(1 − √(2·r_ilma/(r_ilma + r))).
static func aerobrake_dv(name: String) -> float:
	var b := body(name)
	var r: float = b.low.periKm
	var r_air: float = b.radiusKm + AERO_ALT_KM
	return sqrt(b.mu / r) * (1.0 - sqrt(2.0 * r_air / (r_air + r)))


## Planeetan paikka (km) ja nopeus (km/s) Auringon ympärillä hetkellä time (ms): {r, v}.
static func planet_state(name: String, time: float) -> Dictionary:
	var s := Planets.helio_state(name, time)
	return {"r": scale(s.pos, AU_KM), "v": scale(s.vel, AU_KM / DAY_S)}


static func is_moon(name: Variant) -> bool:
	return name is String and MOONS.has(name)


static func moons_of(planet: String) -> PackedStringArray:
	var out := PackedStringArray()
	for m: String in MOONS:
		if MOONS[m].parent == planet:
			out.append(m)
	return out


## Kappaleen (planeetta tai kuu) pysäköintirata: name, mu, radiusKm, periKm, apoKm.
static func orbit_of(name: String) -> Dictionary:
	if not is_moon(name):
		return body(name)
	var m: Dictionary = MOONS[name]
	var r: float = m.radiusKm + m.altKm
	return {"name": name, "mu": m.mu, "radiusKm": m.radiusKm, "periKm": r, "apoKm": r}


static func _moon_angle(name: String, time: float) -> float:
	var m: Dictionary = MOONS[name]
	# Alkukulma kuun nimestä, jotta kuut eivät ole samassa linjassa.
	var sum := 0
	for i in name.length():
		sum += name.unicode_at(i)
	var phase := float(sum % 360) * PI / 180.0
	return phase + 2.0 * PI * (time - J2000_MS) / (m.periodDays * DAY_MS)


## Kuun paikka ja nopeus emoplaneetan suhteen (km, km/s).
static func moon_rel(name: String, time: float) -> Dictionary:
	var m: Dictionary = MOONS[name]
	var th := _moon_angle(name, time)
	var v: float = 2.0 * PI * m.aKm / (m.periodDays * DAY_S)
	return {"r": vec(m.aKm * cos(th), m.aKm * sin(th), 0.0), "v": vec(-v * sin(th), v * cos(th), 0.0)}


## Planeetan tai kuun paikka ja nopeus Auringon ympärillä.
static func body_state(name: String, time: float) -> Dictionary:
	if not is_moon(name):
		return planet_state(name, time)
	var p := planet_state(MOONS[name].parent, time)
	var m := moon_rel(name, time)
	return {"r": add(p.r, m.r), "v": add(p.v, m.v)}


# --- Keplerin rata ja Lambert ---

# Stumpffin funktiot C(z) ja S(z); pienillä z:n arvoilla sarjakehitelmä välttää kumoutumisen.
static func _stumpff_c(z: float) -> float:
	if z > 1e-6:
		return (1.0 - cos(sqrt(z))) / z
	if z < -1e-6:
		return (cosh(sqrt(-z)) - 1.0) / -z
	return 0.5 - z / 24.0 + z * z / 720.0


static func _stumpff_s(z: float) -> float:
	if z > 1e-6:
		var s := sqrt(z)
		return (s - sin(s)) / (s * z)
	if z < -1e-6:
		var s := sqrt(-z)
		return (sinh(s) - s) / (s * -z)
	return 1.0 / 6.0 - z / 120.0 + z * z / 5040.0


## Keplerin radan eteneminen universaalimuuttujalla: paikka r ja nopeus v ajan dt (s) kuluttua alkutilasta (r0, v0).
## Toimii ellipsillä, paraabelilla ja hyperbelillä sekä taaksepäin (dt < 0). Universaalin Keplerin yhtälön
## ratkaisuun käytetään Laguerren–Conwayn menetelmää.
static func propagate(r0: PackedFloat64Array, v0: PackedFloat64Array, dt: float, mu: float = MU_SUN) -> Dictionary:
	var rn := norm(r0)
	var rv := dot(r0, v0)
	var vr := rv / rn
	var alpha := 2.0 / rn - dot(v0, v0) / mu
	var sqmu := sqrt(mu)
	# Ellipsillä kokonaiset kierrokset voi jättää pois, mikä pitää vuosikymmenien etenemisen tarkkana.
	if alpha > 1e-12:
		var period := 2.0 * PI / sqrt(mu * alpha * alpha * alpha)
		dt -= _js_round(dt / period) * period
	if dt == 0.0:
		return {"r": r0.duplicate(), "v": v0.duplicate()}
	# Alkuarvaus: ellipsillä keskiliike, hyperbelillä ja paraabelilla logaritminen arvio (Vallado).
	var x: float
	if alpha > 1e-12:
		x = sqmu * dt * alpha
	elif alpha < -1e-12:
		var a := 1.0 / alpha
		var sg := signf(dt)
		x = sg * sqrt(-a) * log((-2.0 * mu * alpha * dt) / (rv + sg * sqrt(-mu * a) * (1.0 - rn * alpha)))
		if not is_finite(x):
			x = sqmu * dt / rn
	else:
		x = sqmu * dt / rn
	var k := rn * vr / sqmu
	var q := 1.0 - alpha * rn
	for i in 100:
		var z := alpha * x * x
		var C := _stumpff_c(z)
		var S := _stumpff_s(z)
		var F := k * x * x * C + q * x * x * x * S + rn * x - sqmu * dt
		var dF := k * x * (1.0 - z * S) + q * x * x * C + rn
		var ddF := k * (1.0 - z * C) + q * x * (1.0 - z * S)
		var root := sqrt(absf(16.0 * dF * dF - 20.0 * F * ddF))
		var dx := 5.0 * F / (dF + signf(dF) * root)
		x -= dx
		if absf(dx) < 1e-10 * maxf(1.0, absf(x)):
			break
	var z := alpha * x * x
	var C := _stumpff_c(z)
	var S := _stumpff_s(z)
	var f := 1.0 - x * x / rn * C
	var g := dt - x * x * x / sqmu * S
	var r := add(scale(r0, f), scale(v0, g))
	var r1 := norm(r)
	var fd := sqmu / (r1 * rn) * (alpha * x * x * x * S - x)
	var gd := 1.0 - x * x / r1 * C
	return {"r": r, "v": add(scale(r0, fd), scale(v0, gd))}


# Lambertin lentoaika universaalimuuttujan z funktiona; −∞, jos y < 0.
static func _lambert_tof(z: float, n12: float, A: float, sqmu: float) -> float:
	var C := _stumpff_c(z)
	var S := _stumpff_s(z)
	var y := n12 + A * (z * S - 1.0) / sqrt(C)
	if y < 0.0:
		return -INF
	return (pow(y / C, 1.5) * S + A * sqrt(y)) / sqmu


## Lambertin ongelma: siirtorata, joka kulkee paikasta r1 paikkaan r2 ajassa tof (s). Rata kiertää planeettojen
## suuntaan alle yhden kierroksen. Palauttaa {v1, v2} (km/s) tai tyhjän sanakirjan, jos ratkaisua ei löydy.
## Universaalimuuttujan z ratkaisu haetaan puolitushaulla, koska lentoaika kasvaa z:n mukana monotonisesti.
static func lambert(r1: PackedFloat64Array, r2: PackedFloat64Array, tof: float, mu: float = MU_SUN) -> Dictionary:
	var n1 := norm(r1)
	var n2 := norm(r2)
	var dtheta := acos(clampf(dot(r1, r2) / (n1 * n2), -1.0, 1.0))
	if cross(r1, r2)[2] < 0.0:
		dtheta = 2.0 * PI - dtheta
	var A := sin(dtheta) * sqrt(n1 * n2 / (1.0 - cos(dtheta)))
	if not (tof > 0.0) or not is_finite(A) or absf(A) < 1e-9:
		return {}
	var sqmu := sqrt(mu)
	var n12 := n1 + n2
	var lo := -4.0 * PI * PI
	var hi := 4.0 * PI * PI * (1.0 - 1e-12)
	var i := 0
	while i < 60 and _lambert_tof(lo, n12, A, sqmu) > tof:
		lo *= 2.0
		i += 1
	if _lambert_tof(lo, n12, A, sqmu) > tof:
		return {}
	for j in 200:
		var mid := (lo + hi) / 2.0
		if _lambert_tof(mid, n12, A, sqmu) < tof:
			lo = mid
		else:
			hi = mid
		if hi - lo < 1e-13 * maxf(1.0, absf(mid)):
			break
	var z := (lo + hi) / 2.0
	var y := n12 + A * (z * _stumpff_s(z) - 1.0) / sqrt(_stumpff_c(z))
	var f := 1.0 - y / n1
	var g := A * sqrt(y / mu)
	var gd := 1.0 - y / n2
	return {"v1": scale(sub(r2, scale(r1, f)), 1.0 / g), "v2": scale(sub(scale(r2, gd), r1), 1.0 / g)}


## Ominaisenergia ja liikemäärämomentti (radan säilyvät suureet).
static func invariants(r: PackedFloat64Array, v: PackedFloat64Array, mu: float = MU_SUN) -> Dictionary:
	return {"energy": dot(v, v) / 2.0 - mu / norm(r), "h": cross(r, v)}


## Polton Δv (km/s) pysäköintiradan ja Auringon ympäri kulkevan radan välillä, kun ylinopeus on vinf (km/s).
## Poltto tehdään radan perikeskuksessa: Δv = √(v∞² + 2μ/r) − v_rata. Sama kaava lähtöön ja kaappaukseen.
static func burn_dv(name: String, vinf: float, orbit: Dictionary = {}) -> float:
	if orbit.is_empty():
		orbit = body(name)
	var mu: float = orbit.mu
	var peri: float = orbit.periKm
	var v_orbit := sqrt(mu * (2.0 / peri - 2.0 / (peri + float(orbit.apoKm))))
	return sqrt(vinf * vinf + 2.0 * mu / peri) - v_orbit


static func ship_accel(ship: String) -> float:
	return SHIPS[ship].accel


static func can_refuel(ship: String, name: String) -> bool:
	var list: Array = SHIPS[ship].refuel
	return list.is_empty() or list.has(name)


## Polton hinta planeetan luona ylinopeudella vinf. Ionialus kiertää spiraalina ulos tai sisään (Edelbaumin
## likiarvo): hinta on ympyräradan nopeus pysäköintiradan keskietäisyydellä ja ylinopeus.
static func burn_cost(ship: String, name: String, vinf: float) -> float:
	if ship_accel(ship) == 0.0:
		return burn_dv(name, vinf)
	var b := body(name)
	return sqrt(b.mu / ((b.periKm + b.apoKm) / 2.0)) + vinf


## Ionialuksen spiraalin kesto (ms) polton suuruudesta.
static func spiral_ms(ship: String, dv_kms: float) -> float:
	var acc := ship_accel(ship)
	return dv_kms / acc * 1000.0 if acc > 0.0 else 0.0


## Lähtöpaikka on kappaleen nimi (alus pysäköintiradalla) tai Auringon ympäri kulkeva rata {r, v, t}.
static func is_planet(from: Variant) -> bool:
	return from is String or from is StringName


## Lähtöpaikan paikka ja nopeus Auringon ympärillä hetkellä time (ms).
static func departure_state(from: Variant, time: float) -> Dictionary:
	if is_planet(from):
		return body_state(from, time)
	return propagate(from.r, from.v, (time - float(from.t)) / 1000.0)


## Siirtolento lähtöpaikasta from planeetalle to: lähtö hetkellä depart (ms), lentoaika tof_days vuorokautta.
## Palauttaa siirtoradan alkutilan, ylinopeudet ja polttojen Δv:t tai tyhjän sanakirjan.
static func transfer(from: Variant, to: String, depart: float, tof_days: float, ship: String = "kemiallinen") -> Dictionary:
	var arrive := depart + tof_days * DAY_S * 1000.0
	var a := departure_state(from, depart)
	var b := planet_state(to, arrive)
	var sol := lambert(a.r, b.r, tof_days * DAY_S)
	if sol.is_empty():
		return {}
	var vinf_dep := norm(sub(sol.v1, a.v))
	var vinf_arr := norm(sub(sol.v2, b.v))
	var planet := is_planet(from)
	var dv_dep := burn_cost(ship, from, vinf_dep) if planet else vinf_dep
	var dv_arr := burn_cost(ship, to, vinf_arr)
	return {"from": from, "to": to, "depart": depart, "arrive": arrive, "r1": a.r, "v1": sol.v1, "r2": b.r, "v2": sol.v2,
		"ship": ship, "vinfDep": vinf_dep, "vinfArr": vinf_arr, "dvDep": dv_dep, "dvArr": dv_arr, "dvTotal": dv_dep + dv_arr,
		"spiralOut": spiral_ms(ship, dv_dep) if planet else 0.0, "spiralIn": spiral_ms(ship, dv_arr)}


## Aluksen paikka ja nopeus siirtoradalla hetkellä time (ms). Kurssikorjausten jälkeen lennossa on osuuksia
## (legs: [{t, r, v}]); kullakin hetkellä käytetään viimeisintä osuutta, joka on alkanut ennen sitä.
static func ship_state(tr: Dictionary, time: float) -> Dictionary:
	if tr.get("local", false):
		return _local_state(tr, time)
	var legs: Variant = tr.get("legs")
	if legs is Array and not legs.is_empty():
		var leg: Dictionary = legs[0]
		for l: Dictionary in legs:
			if float(l.t) <= time:
				leg = l
		return propagate(leg.r, leg.v, (time - float(leg.t)) / 1000.0)
	return propagate(tr.r1, tr.v1, (time - float(tr.depart)) / 1000.0)


## Hohmannin siirto ympyräratojen r1 ja r2 välillä: lentoaika (s) ja ylinopeudet lähdössä ja saapumisessa (km/s).
static func hohmann(r1: float, r2: float, mu: float = MU_SUN) -> Dictionary:
	var a := (r1 + r2) / 2.0
	return {
		"tof": PI * sqrt(a * a * a / mu),
		"vinfDep": absf(sqrt(mu * (2.0 / r1 - 1.0 / a)) - sqrt(mu / r1)),
		"vinfArr": absf(sqrt(mu / r2) - sqrt(mu * (2.0 / r2 - 1.0 / a))),
	}


## Kuvioetsintä (pattern search) pisteen x ympäriltä: kokeillaan akselien ja lävistäjien suuntia, ja askelta
## puolitetaan, kunnes kaikki askeleet ovat alle tunnin. cost: Callable(PackedFloat64Array) -> float.
static func refine_n(cost: Callable, x: PackedFloat64Array, steps: PackedFloat64Array) -> PackedFloat64Array:
	x = x.duplicate()
	steps = steps.duplicate()
	var n := x.size()
	var best: float = cost.call(x)
	var dirs: Array[PackedFloat64Array] = []
	for i in n:
		for s: float in [1.0, -1.0]:
			var d := PackedFloat64Array()
			d.resize(n)
			d[i] = s
			dirs.append(d)
	for i in n:
		for j in range(i + 1, n):
			for ab: Array in [[1.0, 1.0], [-1.0, -1.0], [1.0, -1.0], [-1.0, 1.0]]:
				var d := PackedFloat64Array()
				d.resize(n)
				d[i] = ab[0]
				d[j] = ab[1]
				dirs.append(d)
	while true:
		var any_big := false
		for v in steps:
			if v > 1.0 / 24.0:
				any_big = true
				break
		if not any_big:
			break
		var moved := false
		for d in dirs:
			var y := PackedFloat64Array()
			y.resize(n)
			for i in n:
				y[i] = x[i] + d[i] * steps[i]
			var c: float = cost.call(y)
			if c < best:
				best = c
				x = y
				moved = true
				break
		if not moved:
			for i in n:
				steps[i] /= 2.0
	return x


# --- Painovoimalinkous ---

## Ohilennon hinta planeetan via ohi, kun tuloylinopeus on vin ja lähtöylinopeus vout (vektorit, km/s).
## Palauttaa {dv, rp} tai tyhjän, jos käännös vaatisi perikeskuksen planeetan sisällä.
static func flyby_dv(via: String, vin: PackedFloat64Array, vout: PackedFloat64Array) -> Dictionary:
	var b := body(via)
	var mu: float = b.mu
	var radius: float = b.radiusKm
	var a := norm(vin)
	var c := norm(vout)
	var turn := acos(clampf(dot(vin, vout) / (a * c), -1.0, 1.0))
	var vm := (a + c) / 2.0
	var min_rp := radius * (1.3 if radius > 20000.0 else 1.05)
	var rp := INF if turn < 1e-6 else mu * (1.0 / sin(turn / 2.0) - 1.0) / (vm * vm)
	if rp < min_rp:
		return {}
	var r := rp if is_finite(rp) else 1e12
	return {"dv": absf(sqrt(c * c + 2.0 * mu / r) - sqrt(a * a + 2.0 * mu / r)), "rp": rp}


## Lento planeetalta from planeetalle to planeetan via ohi: lähtö depart (ms), lentoajat tof1 ja tof2 (vrk).
## Rata koostuu kahdesta osuudesta (legs), jotka kohtaavat ohilentoplaneetan keskipisteessä (patched conics).
static func assist_transfer(from: Variant, via: String, to: String, depart: float, tof1: float, tof2: float, ship: String = "kemiallinen") -> Dictionary:
	var tB := depart + tof1 * DAY_MS
	var arrive := tB + tof2 * DAY_MS
	var a := departure_state(from, depart)
	var b := planet_state(via, tB)
	var c := planet_state(to, arrive)
	var l1 := lambert(a.r, b.r, tof1 * DAY_S)
	if l1.is_empty():
		return {}
	var l2 := lambert(b.r, c.r, tof2 * DAY_S)
	if l2.is_empty():
		return {}
	var fb := flyby_dv(via, sub(l1.v2, b.v), sub(l2.v1, b.v))
	if fb.is_empty():
		return {}
	var vinf_dep := norm(sub(l1.v1, a.v))
	var vinf_arr := norm(sub(l2.v2, c.v))
	var dv_dep := burn_cost(ship, from, vinf_dep) if is_planet(from) else vinf_dep
	var dv_arr := burn_cost(ship, to, vinf_arr)
	return {"from": from, "to": to, "via": via, "depart": depart, "arrive": arrive, "r1": a.r, "v1": l1.v1, "r2": c.r, "v2": l2.v2,
		"ship": ship, "legs": [{"t": depart, "r": a.r, "v": l1.v1}, {"t": tB, "r": b.r, "v": l2.v1}],
		"flyby": {"body": via, "t": tB, "dv": fb.dv, "rpKm": fb.rp, "vinf": norm(sub(l1.v2, b.v))},
		"vinfDep": vinf_dep, "vinfArr": vinf_arr, "dvDep": dv_dep, "dvArr": dv_arr, "dvFlyby": fb.dv,
		"dvTotal": dv_dep + fb.dv + dv_arr, "spiralOut": 0.0, "spiralIn": 0.0}


## Ajaa ikkunahaun loppuun kerralla (testit ja pienet haut). Pelissä käytetään WindowSearch-oliota ruutu kerrallaan.
static func find_windows(from: Variant, to: String, start: float, opts: Dictionary = {}) -> Array:
	var search := WindowSearch.new(from, to, start, opts)
	while not search.done:
		search.step()
	return search.result


## Kesto muodossa 123 vrk 04:12:33.
static func fmt_duration(ms: float) -> String:
	var s := int(maxf(0.0, floor(ms / 1000.0)))
	return "%d vrk %02d:%02d:%02d" % [s / 86400, (s / 3600) % 24, (s / 60) % 60, s % 60]


# --- Vaikutuspiirit ja ohjaamonäkymä ---

## Hetki (ms), jolloin alus saapuu kohdeplaneetan vaikutuspiiriin siirtoradalla tr.
static func soi_entry(tr: Dictionary) -> float:
	var to: String = tr.to
	var soi: float = body(to).soiKm
	var gap := func(t: float) -> float: return norm(sub(ship_state(tr, t).r, planet_state(to, t).r)) - soi
	var N := 400
	var depart: float = tr.depart
	var span: float = float(tr.arrive) - depart
	var lo := NAN
	for i in range(N - 1, -1, -1):
		var t := depart + span * i / N
		if gap.call(t) > 0.0:
			lo = t
			break
	if is_nan(lo):
		return depart
	var hi := minf(tr.arrive, lo + span / N)
	for i in 60:
		var mid := (lo + hi) / 2.0
		if gap.call(mid) > 0.0:
			lo = mid
		else:
			hi = mid
	return hi


## Hetki (ms), jolloin alus poistuu lähtöplaneetan vaikutuspiiristä.
static func soi_exit(tr: Dictionary) -> float:
	if not is_planet(tr.from):
		return tr.depart
	var from: String = tr.from
	var soi: float = body(from).soiKm
	var gap := func(t: float) -> float: return norm(sub(ship_state(tr, t).r, planet_state(from, t).r)) - soi
	var lo: float = tr.depart
	var hi: float = tr.arrive
	if gap.call(hi) < 0.0:
		return hi
	for i in 60:
		var mid := (lo + hi) / 2.0
		if gap.call(mid) < 0.0:
			lo = mid
		else:
			hi = mid
	return hi


## Lähin planeetta paikassa r (km) hetkellä time: {name, distance (km), speed (km/s) sen suhteen}.
static func nearest_planet(r: PackedFloat64Array, v: PackedFloat64Array, time: float) -> Dictionary:
	var best := {}
	for name in Planets.NAMES:
		var s := planet_state(name, time)
		var d := norm(sub(r, s.r))
		if best.is_empty() or d < float(best.distance):
			best = {"name": name, "distance": d, "speed": norm(sub(v, s.v))}
	return best


# Siirtää paikan r vähintään etäisyydelle min kappaleen keskipisteestä c, jotta alus ei näy kappaleen sisällä.
static func _clamp_outside(r: PackedFloat64Array, c: PackedFloat64Array, min_km: float) -> PackedFloat64Array:
	var rel := sub(r, c)
	var dist := norm(rel)
	if dist >= min_km:
		return r
	return add(c, scale(rel, min_km / dist) if dist > 1.0 else vec(min_km, 0.0, 0.0))


## Aluksen menosuunta (nopeus, km/s) samassa koordinaatistossa kuin lentokartan nuoli: paikallisella lennolla
## (kuuhun tai kuusta) emoplaneetan suhteen, muuten Auringon suhteen.
static func heading_velocity(tr: Dictionary, time: float) -> PackedFloat64Array:
	var s := ship_state(tr, maxf(time, float(tr.depart)))
	if tr.get("local", false):
		return sub(s.v, planet_state(tr.parent, time).v)
	return s.v


## Hyperbolinen ohitusrata kappaleen ympäri ekliptikan tasossa samaan kiertosuuntaan kuin pysäköintiradat: perikeskus
## rp (km) hetkellä t_peri ja ylinopeus vinf (km/s). outgoing: vinf on lähtevän asymptootin suunta (lähtöpoltto
## perikeskuksessa), muuten saapuvan (jarrutuspoltto perikeskuksessa). Paikka ja nopeus kappaleen suhteen hetkellä time.
## Asymptootti kääntyy perikeskuksen nopeudesta kulman β = acos(1/e), e = 1 + rp·v∞²/μ.
static func hyperbola_rel(mu: float, rp: float, vinf: PackedFloat64Array, t_peri: float, time: float, outgoing: bool) -> Dictionary:
	var speed := maxf(norm(vinf), 1e-3)
	var e := 1.0 + rp * speed * speed / mu
	var beta := acos(1.0 / e)
	var u := atan2(vinf[1], vinf[0])
	var arg := u - (PI - beta) if outgoing else u - beta
	var vp := sqrt(speed * speed + 2.0 * mu / rp)
	var c := cos(arg)
	var s := sin(arg)
	return propagate(vec(rp * c, rp * s, 0.0), vec(-vp * s, vp * c, 0.0), (time - t_peri) / 1000.0, mu)


## Kuun vaikutuspiiri (km) emoplaneetan suhteen: a·(μ/μ_planeetta)^0,4.
static func moon_soi(name: String) -> float:
	var m: Dictionary = MOONS[name]
	return float(m.aKm) * pow(float(m.mu) / float(body(m.parent).mu), 0.4)


# Kappaleen vaikutuspiirissä siirtoradan paikka ja nopeus (s, Auringon suhteen) korvataan vähitellen oikealla
# hyperbelillä, jonka perikeskus on pysäköintiradan korkeudella hetkellä t_peri; vaikutuspiirin rajalla siirtorata.
static func _near_body(s: Dictionary, name: String, time: float, t_peri: float, vinf: PackedFloat64Array, outgoing: bool, soi: float) -> Dictionary:
	var b := body_state(name, time)
	var rel := sub(s.r, b.r)
	var fade := clampf(1.0 - norm(rel) / soi, 0.0, 1.0)
	if fade <= 0.0:
		return s
	fade = fade * fade * (3.0 - 2.0 * fade)
	var o := orbit_of(name)
	var h := hyperbola_rel(o.mu, o.periKm, vinf, t_peri, time, outgoing)
	var rel_v := sub(s.v, b.v)
	return {"r": add(b.r, add(scale(rel, 1.0 - fade), scale(h.r, fade))),
		"v": add(b.v, add(scale(rel_v, 1.0 - fade), scale(h.v, fade)))}


## Aluksen paikka ja nopeus ohjaamonäkymää varten. Siirtorata kulkee lähtö- ja kohdekappaleen keskipisteen kautta,
## joten niiden vaikutuspiirissä se korvataan vähitellen hyperbelillä: lähtöpoltto ja jarrutuspoltto tehdään
## perikeskuksessa pysäköintiradan korkeudella, kuten oikeasti (esim. Apollo: Kuun kiertoradalle asettuminen
## lähimmässä kohdassa). Lähtöhetkellä paikka on pysäköintiradalla ja saapuessa pysäköintiradan perikeskuksessa.
static func ship_view(tr: Dictionary, time: float) -> Dictionary:
	if tr.get("local", false):
		var t_local := clampf(time, tr.depart, tr.arrive)
		var moon: String = tr.to if tr.toMoon else tr.from
		var t_peri: float = tr.arrive if tr.toMoon else tr.depart
		var vinf_local := sub(ship_state(tr, t_peri).v, body_state(moon, t_peri).v)
		var lv := _near_body(ship_state(tr, t_local), moon, t_local, t_peri, vinf_local, not tr.toMoon, moon_soi(moon))
		return {"r": _clamp_outside(lv.r, body_state(moon, t_local).r, float(orbit_of(moon).radiusKm) + 1.0), "v": lv.v}
	var to: String = tr.to
	var t := maxf(time, tr.depart)
	var view := ship_state(tr, t)
	# Korjattu rata ei kulje kohteen keskipisteen kautta, joten saapumishyperbeliä käytetään vain alkuperäisellä radalla.
	var legs: Variant = tr.get("legs")
	if not (legs is Array and legs.size() > 1):
		var vinf_arr := sub(ship_state(tr, tr.arrive).v, planet_state(to, tr.arrive).v)
		view = _near_body(view, to, t, tr.arrive, vinf_arr, false, body(to).soiKm)
	var r := _clamp_outside(view.r, planet_state(to, t).r, body(to).periKm)
	# Linkouksessa alus ohittaa planeetan perikeskuksen etäisyydeltä.
	var flyby: Variant = tr.get("flyby")
	if flyby is Dictionary:
		var fb_body: String = flyby.body
		r = _clamp_outside(r, planet_state(fb_body, t).r, minf(flyby.rpKm, float(body(fb_body).soiKm) / 4.0))
	view = {"r": r, "v": view.v}
	if is_planet(tr.from):
		var from: String = tr.from
		var vinf_dep := sub(tr.v1, planet_state(from, tr.depart).v)
		view = _near_body(view, from, t, tr.depart, vinf_dep, true, body(from).soiKm)
		# Ennen lähtöä alus odottaa perikeskuksessa ja kulkee planeetan mukana.
		if time < float(tr.depart):
			var shift := sub(planet_state(from, time).r, planet_state(from, tr.depart).r)
			return {"r": add(view.r, shift), "v": planet_state(from, time).v}
	elif time <= float(tr.depart):
		return departure_state(tr.from, time)
	return view


# --- Pysäköintiradat ---

static func _orbit_epoch(orbit: Variant) -> float:
	return float(orbit.get("epoch", J2000_MS)) if orbit is Dictionary else J2000_MS


static func _orbit_arg(orbit: Variant) -> float:
	return float(orbit.get("arg", 0.0)) if orbit is Dictionary else 0.0


## Aluksen paikka ja nopeus pysäköintiradalla planeetan tai kuun ympärillä hetkellä time (ms). Rata on ekliptikan
## tasossa. orbit = {epoch, arg}: perikeskuksen ohitushetki (ms) ja perikeskuksen suunta (rad), tai null.
static func parking_state(name: String, time: float, orbit: Variant = null) -> Dictionary:
	var o := orbit_of(name)
	var mu: float = o.mu
	var peri: float = o.periKm
	var a: float = (peri + float(o.apoKm)) / 2.0
	var epoch := _orbit_epoch(orbit)
	var arg := _orbit_arg(orbit)
	var vp := sqrt(mu * (2.0 / peri - 1.0 / a))
	var c := cos(arg)
	var s := sin(arg)
	var rel := propagate(vec(peri * c, peri * s, 0.0), vec(-vp * s, vp * c, 0.0), (time - epoch) / 1000.0, mu)
	var p := body_state(name, time)
	return {"r": add(p.r, rel.r), "v": add(p.v, rel.v), "rel": rel}


## Pysäköintiradan kiertoaika (s).
static func orbit_period(name: String) -> float:
	var o := orbit_of(name)
	var a: float = (float(o.periKm) + float(o.apoKm)) / 2.0
	return 2.0 * PI * sqrt(a * a * a / float(o.mu))


## Pysäköintirata, jonka perikeskus on aluksen paikassa r (Auringon suhteen, km) hetkellä time.
static func orbit_at(name: String, r: PackedFloat64Array, time: float) -> Dictionary:
	var rel := sub(r, body_state(name, time).r)
	return {"epoch": time, "arg": atan2(rel[1], rel[0])}


## Lähtöpolton hetki (ms): ensimmäinen hetki ajan after jälkeen, jolloin alus on pysäköintiradalla kohdassa, josta
## poltto vie sen oikeaan suuntaan. Hyperbelin asymptootti kääntyy perikeskuksesta kulman θ∞ = acos(−1/e),
## e = 1 + r·v∞²/μ. Venyneellä radalla poltto tehdään seuraavassa perikeskuksessa.
static func injection_time(name: String, vinf: PackedFloat64Array, after: float, orbit: Variant = null) -> float:
	var o := orbit_of(name)
	var peri: float = o.periKm
	var speed := norm(vinf)
	var e: float = 1.0 + peri * speed * speed / float(o.mu)
	return angle_time(name, atan2(vinf[1], vinf[0]) - acos(-1.0 / e), after, orbit)


## Ensimmäinen hetki ajan after jälkeen, jolloin alus on pysäköintiradalla suunnassa want (rad). Venyneellä radalla
## seuraava perikeskus.
static func angle_time(name: String, want: float, after: float, orbit: Variant = null) -> float:
	var o := orbit_of(name)
	var epoch := _orbit_epoch(orbit)
	var arg := _orbit_arg(orbit)
	var period := orbit_period(name) * 1000.0
	if float(o.apoKm) - float(o.periKm) > 1.0:
		return epoch + ceil((after - epoch) / period) * period
	var now := arg + 2.0 * PI * (after - epoch) / period
	var turn := fmod(fmod(want - now, 2.0 * PI) + 2.0 * PI, 2.0 * PI)
	return after + turn / (2.0 * PI) * period


# --- Nousu Maan pinnalta kiertoradalle ---
# Kantoraketti nostaa aluksen 200 km:n radalle noin 8,5 minuutissa. Korkeus ja vaakanopeus seuraavat sileitä käyriä,
# jotka alkavat levosta ja päättyvät täsmälleen ympyräradan tilaan. Laukaisupaikka on ekliptikan tasossa Maan
# pinnalla ja kiertää Maan mukana.

static func _pad_angle(time: float) -> float:
	return EARTH_SPIN * (time - J2000_MS) / 1000.0


static func _ascent_turn() -> float:
	var E := body("Maa")
	var peri: float = E.periKm
	return sqrt(E.mu / peri) * ASCENT_S / ((TURN_POWER + 1.0) * peri)


## Aluksen tila laukaisualustalla ja nousussa. liftoff on laukaisuhetki (ms) tai null ennen lähtölaskentaa.
## Palauttaa r, v (Auringon suhteen), rel (Maan suhteen), tau (s), alt (km), speed (km/s), g, phase, shake,
## thrust (0–1) sekä nokan ja katon suunnat nose ja up.
static func launch_state(liftoff: Variant, time: float) -> Dictionary:
	var E := body("Maa")
	var radius: float = E.radiusKm
	var peri: float = E.periKm
	var has_liftoff := liftoff != null
	var tau := -INF if not has_liftoff else (time - float(liftoff)) / 1000.0
	var s := clampf(tau / ASCENT_S, 0.0, 1.0)
	var turn := _ascent_turn()
	var phi := (_pad_angle(float(liftoff)) if tau > 0.0 else _pad_angle(time)) + turn * pow(s, TURN_POWER + 1.0)
	var r0 := radius + PAD_ALT_KM
	var r := r0 + (peri - r0) * (3.0 * s * s - 2.0 * s * s * s)
	var radial := vec(cos(phi), sin(phi), 0.0)
	var tangent := vec(-sin(phi), cos(phi), 0.0)
	var vr := (peri - r0) * 6.0 * s * (1.0 - s) / ASCENT_S
	var vt := r * turn * (TURN_POWER + 1.0) * pow(s, TURN_POWER) / ASCENT_S
	var rel := {"r": scale(radial, r), "v": add(scale(radial, vr), scale(tangent, vt))}
	var p := planet_state("Maa", time)
	# Painovoimakäännös: nokka kallistuu pystystä lähes vaakaan nousun kolmen ensimmäisen neljänneksen aikana.
	var pitch := PI / 2.0 * pow(minf(1.0, s / 0.75), 0.7)
	var cp := cos(pitch)
	var sp := sin(pitch)
	var max_q: float = ASCENT_EVENTS.maxQ
	var meco: float = ASCENT_EVENTS.meco
	var stage2: float = ASCENT_EVENTS.stage2
	var phase := "Laukaisualusta"
	var g := 1.0
	var shake := 0.0
	var thrust := 0.0
	if tau >= ASCENT_S:
		phase = "Kiertoradalla"
		g = 0.0
	elif tau >= stage2:
		var k := (tau - stage2) / (ASCENT_S - stage2)
		phase = "Vaihe 2"
		g = 0.7 + 2.6 * k * k
		thrust = 0.6
		shake = 0.16 - 0.08 * k + (0.8 if tau - stage2 < 0.6 else 0.0)
	elif tau >= meco:
		phase = "Vaiheen erotus"
		g = 0.0
		shake = 0.9 if tau - meco < 0.5 else 0.02
	elif tau >= 0.0:
		var k := tau / meco
		phase = "Max Q" if absf(tau - max_q) < 12.0 else ("Laukaisu" if tau < 8.0 else "Vaihe 1")
		g = 1.3 + 2.4 * pow(k, 1.5)
		thrust = 1.0
		# Tärinä: kova laukaisussa, uusi huippu suurimman aerodynaamisen kuorman kohdalla, sitten ilma ohenee.
		shake = maxf(1.0 if tau < 8.0 else 0.0, 0.5 - 0.2 * k + 0.45 * exp(-pow((tau - max_q) / 14.0, 2.0)))
	elif tau >= -3.0:
		phase = "Sytytys"
		shake = 0.35 + 0.25 * (tau + 3.0) / 3.0
		thrust = 0.7
	elif has_liftoff:
		phase = "Lähtölaskenta"
	return {"r": add(p.r, rel.r), "v": add(p.v, rel.v), "rel": rel, "tau": tau, "alt": r - radius,
		"speed": sqrt(vr * vr + vt * vt), "g": g, "phase": phase, "shake": shake, "thrust": thrust,
		"nose": add(scale(radial, cp), scale(tangent, sp)), "up": add(scale(radial, sp), scale(tangent, -cp))}


## Pysäköintirata, jolle hetkellä liftoff alkanut nousu päättyy.
static func launch_orbit(liftoff: float) -> Dictionary:
	return {"epoch": liftoff + ASCENT_S * 1000.0, "arg": _pad_angle(liftoff) + _ascent_turn()}


## Siirtoradan pituus (km) ja huippunopeus Auringon suhteen (km/s) näytteistä.
static func flight_stats(tr: Dictionary, samples: int = 2000) -> Dictionary:
	var km := 0.0
	var max_speed := 0.0
	var prev := PackedFloat64Array()
	var depart: float = tr.depart
	var span: float = float(tr.arrive) - depart
	for i in samples + 1:
		var s := ship_state(tr, depart + span * i / samples)
		if not prev.is_empty():
			km += norm(sub(s.r, prev))
		max_speed = maxf(max_speed, norm(s.v))
		prev = s.r
	return {"km": km, "maxSpeed": max_speed}


# --- Kurssikorjaukset ---

static func burn_vector(state: Dictionary, direction: String, dv_kms: float) -> PackedFloat64Array:
	var r: PackedFloat64Array = state.r
	var vh := scale(state.v, 1.0 / norm(state.v))
	# Säteittäinen suunta kohtisuoraan nopeutta vastaan.
	var out := sub(scale(r, 1.0 / norm(r)), scale(vh, dot(r, vh) / norm(r)))
	out = scale(out, 1.0 / norm(out))
	var dir: PackedFloat64Array
	match direction:
		"prograde": dir = vh
		"retrograde": dir = scale(vh, -1.0)
		"outward": dir = out
		"inward": dir = scale(out, -1.0)
		_:
			push_error("Tuntematon polton suunta: " + direction)
			dir = vec(0.0, 0.0, 0.0)
	return scale(dir, dv_kms)


## Kohtaaminen kohdeplaneetan kanssa hetkestä from alkaen: lähin ohitus {t, distance (km), vinf (km/s)}.
static func encounter(tr: Dictionary, from: float, until: float) -> Dictionary:
	var to: String = tr.to
	var d := func(t: float) -> float: return norm(sub(ship_state(tr, t).r, planet_state(to, t).r))
	var N := 800
	var span := until - from
	var best := 0
	var best_d := INF
	for i in N + 1:
		var v: float = d.call(from + span * i / N)
		if v < best_d:
			best_d = v
			best = i
	var a := from + span * maxi(0, best - 1) / N
	var b := from + span * mini(N, best + 1) / N
	var g := (sqrt(5.0) - 1.0) / 2.0
	for i in 80:
		var c := b - g * (b - a)
		var e := a + g * (b - a)
		if d.call(c) < d.call(e):
			b = e
		else:
			a = c
	var t := (a + b) / 2.0
	var s := ship_state(tr, t)
	var p := planet_state(to, t)
	return {"t": t, "distance": norm(sub(s.r, p.r)), "vinf": norm(sub(s.v, p.v))}


## Lennon ennuste hetkestä from alkaen: osuuko alus kohteen vaikutuspiiriin, milloin se saapuu (lähin ohitus) ja
## paljonko jarrutus maksaa. Palauttaa päivitetyn lennon (planned, arrive, soi, miss, missKm, vinfArr, dvArr).
static func predict(tr: Dictionary, from: float) -> Dictionary:
	var planned: float = tr.planned if tr.get("planned") != null else tr.arrive
	var until := minf(from + 3.0 * 365.25 * DAY_MS, maxf(planned, from) + maxf(60.0 * DAY_MS, 0.6 * (planned - float(tr.depart))))
	var e := encounter(tr, from, until)
	var soi: float = body(tr.to).soiKm
	var next := tr.duplicate()
	next.planned = planned
	next.arrive = e.t
	next.missKm = e.distance
	next.miss = float(e.distance) > soi
	next.vinfArr = e.vinf
	next.dvArr = burn_dv(tr.to, e.vinf)
	next.soi = e.t if next.miss else soi_entry(next)
	return next


static func _legs_before(tr: Dictionary, time: float) -> Array:
	var legs: Variant = tr.get("legs")
	if not (legs is Array) or legs.is_empty():
		legs = [{"t": tr.depart, "r": tr.r1, "v": tr.v1}]
	var out := []
	for l: Dictionary in legs:
		if float(l.t) < time:
			out.append(l)
	return out


## Poltto hetkellä time annettuun suuntaan: lennolle lisätään uusi osuus ja ennuste lasketaan uudelleen.
static func apply_burn(tr: Dictionary, time: float, direction: String, dv_kms: float) -> Dictionary:
	return apply_burn_vector(tr, time, burn_vector(ship_state(tr, time), direction, dv_kms))


## Poltto hetkellä time nopeuden muutoksella dv (km/s, ekliptikan koordinaatit; manuaaliohjaus).
static func apply_burn_vector(tr: Dictionary, time: float, dv: PackedFloat64Array) -> Dictionary:
	var s := ship_state(tr, time)
	var next := tr.duplicate()
	var legs := _legs_before(tr, time)
	legs.append({"t": time, "r": s.r, "v": add(s.v, dv)})
	next.legs = legs
	# Ennen linkousta tehty poltto vie aluksen pois ohilentoradalta.
	if next.get("flyby") is Dictionary and float(next.flyby.t) > time:
		next.erase("flyby")
	return predict(next, time)


## Automaattinen kurssikorjaus: Lambertin rata nykyisestä paikasta kohteeseen alkuperäisellä saapumishetkellä
## (tai vähintään 10 vrk päähän). Palauttaa {flight, dv} tai tyhjän.
static func auto_correct(tr: Dictionary, time: float) -> Dictionary:
	var s := ship_state(tr, time)
	var planned: float = tr.planned if tr.get("planned") != null else tr.arrive
	var arrive := maxf(planned, time + 10.0 * DAY_MS)
	var sol := lambert(s.r, planet_state(tr.to, arrive).r, (arrive - time) / 1000.0)
	if sol.is_empty():
		return {}
	var dv := norm(sub(sol.v1, s.v))
	var corrected := tr.duplicate()
	var legs := _legs_before(tr, time)
	legs.append({"t": time, "r": s.r, "v": sol.v1})
	corrected.legs = legs
	if corrected.get("flyby") is Dictionary and float(corrected.flyby.t) > time:
		corrected.erase("flyby")
	return {"flight": predict(corrected, time), "dv": dv}


# --- Kuut ---

## Lento emoplaneetan kiertoradalta kuuhun tai kuusta takaisin emoplaneetan kiertoradalle (Hohmannin siirto
## emoplaneetan ympärillä). Ellipsin perikeskus on planeetan pysäköintiradan perikeskuksen etäisyydellä ja
## apokeskus kuun radalla; kuu on apokeskuksessa saapumis- tai lähtöhetkellä.
static func local_transfer(from: String, to: String, depart: float) -> Dictionary:
	var to_moon := is_moon(to)
	var moon := to if to_moon else from
	var m: Dictionary = MOONS[moon]
	var parent: String = m.parent
	var P := body(parent)
	var mu: float = P.mu
	var rp: float = P.periKm
	var ra: float = m.aKm
	var a := (rp + ra) / 2.0
	var tof := PI * sqrt(a * a * a / mu) * 1000.0
	var arrive := depart + tof
	var v_peri := sqrt(mu * (2.0 / rp - 1.0 / a))
	var v_apo := sqrt(mu * (2.0 / ra - 1.0 / a))
	var v_park := sqrt(mu * (2.0 / rp - 2.0 / (rp + float(P.apoKm))))
	var v_moon := 2.0 * PI * ra / (absf(m.periodDays) * DAY_S)
	# Takaperin kiertävän kuun (Triton) nopeus on vastakkainen siirtoradan nopeudelle.
	var vinf: float = v_moon + v_apo if float(m.periodDays) < 0.0 else absf(v_moon - v_apo)
	var moon_burn := burn_dv(moon, vinf, orbit_of(moon))
	var planet_burn := absf(v_peri - v_park)
	var dv_dep := planet_burn if to_moon else moon_burn
	var dv_arr := moon_burn if to_moon else planet_burn
	# Apokeskuksen suunta: kuun paikka saapuessa (kuuhun) tai lähtiessä (kuusta).
	var apo_angle := _moon_angle(moon, arrive if to_moon else depart)
	return {"local": true, "from": from, "to": to, "parent": parent, "depart": depart, "arrive": arrive, "rp": rp, "ra": ra,
		"apoAngle": apo_angle, "toMoon": to_moon, "mu": mu, "vPeri": v_peri, "vApo": v_apo,
		"dvDep": dv_dep, "dvArr": dv_arr, "dvTotal": dv_dep + dv_arr, "vinfArr": vinf if to_moon else 0.0,
		"ship": "kemiallinen", "spiralOut": 0.0, "spiralIn": 0.0}


# Aluksen paikka paikallisella siirtoradalla: emoplaneetan suhteen Keplerin rata, Auringon suhteen siihen lisätään planeetta.
static func _local_state(tr: Dictionary, time: float) -> Dictionary:
	var t := clampf(time, tr.depart, tr.arrive)
	var c := cos(tr.apoAngle)
	var s := sin(tr.apoAngle)
	var rp: float = tr.rp
	var ra: float = tr.ra
	var vp: float = tr.vPeri
	var va: float = tr.vApo
	var dt := (t - float(tr.depart)) / 1000.0
	# Kuuhun: lähtö perikeskuksesta (apokeskusta vastapäätä). Kuusta: lähtö apokeskuksesta.
	var rel: Dictionary
	if tr.toMoon:
		rel = propagate(vec(-rp * c, -rp * s, 0.0), vec(vp * s, -vp * c, 0.0), dt, tr.mu)
	else:
		rel = propagate(vec(ra * c, ra * s, 0.0), vec(-va * s, va * c, 0.0), dt, tr.mu)
	var p := planet_state(tr.parent, time)
	return {"r": add(p.r, rel.r), "v": add(p.v, rel.v), "rel": rel}
