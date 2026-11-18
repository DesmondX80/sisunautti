class_name Planets
## Planeettojen sijainnit ja nopeudet Auringon ympärillä Keplerin rata-alkioista (web/js/planets.js).
## Alkiot: E. M. Standish (JPL), "Keplerian Elements for Approximate Positions of the Major Planets", taulukot 2a ja 2b,
## voimassa vuosina 3000 eKr.–3000 jKr. Ulkoplaneettojen keskianomaliaan lisätään Jupiterin ja Saturnuksen
## häiriöitä kuvaavat termit b, c, s ja f. Tarkkuus on kaariminuuttien luokkaa.
## Koordinaatit ovat ekliptikan tasossa (J2000) astronomisina yksikköinä: x kohti kevätpistettä, z pohjoisnavalle.
## Vektorit ovat PackedFloat64Array-taulukoita (64-bittiset), ajat millisekunteja (float, kuten JS:n Date.getTime()).

const RAD := PI / 180.0
const DAY_MS := 86400000.0
const CENTURY_MS := 36525.0 * DAY_MS
## J2000.0 = 2000-01-01 12:00 UTC millisekunteina.
const J2000_MS := 946728000000.0
## Astronominen yksikkö kilometreinä.
const AU_KM := 149597870.7
## Valon nopeus astronomisina yksikköinä minuutissa.
const LIGHT_AU_PER_MIN := 299792.458 * 60.0 / AU_KM
## Auringon säde kilometreinä.
const SUN_RADIUS_KM := 696000.0

# [nimi, väri, säde km, kiertoaika vuosina,
#  a (AU), e, I, L, pitkä periheli ϖ, nousevan solmun pituus Ω (asteina),
#  sama järjestys muutoksina vuosisadassa,
#  keskianomalian lisätermit b, c, s, f (asteina; M += bT² + c cos fT + s sin fT)]
const ELEMENTS := [
	["Merkurius", "#b8b2a8", 2439.7, 0.2408, 0.38709843, 0.20563661, 7.00559432, 252.25166724, 77.45771895, 48.33961819,
		0.00000000, 0.00002123, -0.00590158, 149472.67486623, 0.15940013, -0.12214182],
	["Venus", "#f2d9a0", 6051.8, 0.6152, 0.72332102, 0.00676399, 3.39777545, 181.97970850, 131.76755713, 76.67261496,
		-0.00000026, -0.00005107, 0.00043494, 58517.81560260, 0.05679648, -0.27274174],
	# Maan alkiot kuvaavat Maan ja Kuun yhteistä painopistettä, joka on alle 5 000 km Maan keskipisteestä.
	["Maa", "#5ed6ff", 6371.0, 1.0000, 1.00000018, 0.01673163, -0.00054346, 100.46691572, 102.93005885, -5.11260389,
		-0.00000003, -0.00003661, -0.01337178, 35999.37306329, 0.31795260, -0.24123856],
	["Mars", "#ff8a65", 3389.5, 1.8808, 1.52371243, 0.09336511, 1.85181869, -4.56813164, -23.91744784, 49.71320984,
		0.00000097, 0.00009149, -0.00724757, 19140.29934243, 0.45223625, -0.26852431],
	["Jupiter", "#e0b88a", 69911.0, 11.862, 5.20248019, 0.04853590, 1.29861416, 34.33479152, 14.27495244, 100.29282654,
		-0.00002864, 0.00018026, -0.00322699, 3034.90371757, 0.18199196, 0.13024619,
		-0.00012452, 0.06064060, -0.35635438, 38.35125000],
	["Saturnus", "#f0d58c", 58232.0, 29.457, 9.54149883, 0.05550825, 2.49424102, 50.07571329, 92.86136063, 113.63998702,
		-0.00003065, -0.00032044, 0.00451969, 1222.11494724, 0.54179478, -0.25015002,
		0.00025899, -0.13434469, 0.87320147, 38.35125000],
	["Uranus", "#9fe3e8", 25362.0, 84.011, 19.18797948, 0.04685740, 0.77298127, 314.20276625, 172.43404441, 73.96250215,
		-0.00020455, -0.00001550, -0.00180155, 428.49512595, 0.09266985, 0.05739699,
		0.00058331, -0.97731848, 0.17689245, 7.67025000],
	["Neptunus", "#7f9cff", 24622.0, 164.79, 30.06952752, 0.00895439, 1.77005520, 304.22289287, 46.68158724, 131.78635853,
		0.00006447, 0.00000818, 0.00022400, 218.46515314, 0.01009938, -0.00606302,
		-0.00041348, 0.68346318, -0.10162547, 7.67025000],
]

## Planeettojen nimet aurinkokunnan järjestyksessä.
const NAMES: PackedStringArray = ["Merkurius", "Venus", "Maa", "Mars", "Jupiter", "Saturnus", "Uranus", "Neptunus"]


static func _row(name: String) -> Array:
	for row: Array in ELEMENTS:
		if row[0] == name:
			return row
	push_error("Tuntematon planeetta: " + name)
	return []


## Planeetan perustiedot: name, color, radius_km, period_years.
static func info(name: String) -> Dictionary:
	var row := _row(name)
	return {"name": row[0], "color": Color(row[1]), "radius_km": float(row[2]), "period_years": float(row[3])}


static func radius_km(name: String) -> float:
	return float(_row(name)[2])


## Rata-alkiot hetkellä time (ms): a, e ja kulmat radiaaneina (I, peri = perihelin argumentti, node, M) sekä
## keskiliike n (rad/vrk).
static func elements(name: String, time: float) -> Dictionary:
	var row := _row(name)
	var T := (time - J2000_MS) / CENTURY_MS
	var v := func(i: int) -> float: return float(row[4 + i]) + float(row[10 + i]) * T
	var a: float = v.call(0)
	var e: float = v.call(1)
	var I: float = v.call(2)
	var L: float = v.call(3)
	var varpi: float = v.call(4)
	var node: float = v.call(5)
	var b := 0.0
	var c := 0.0
	var s := 0.0
	var f := 0.0
	if row.size() > 16:
		b = row[16]
		c = row[17]
		s = row[18]
		f = row[19]
	var M := L - varpi + b * T * T + c * cos(f * T * RAD) + s * sin(f * T * RAD)
	return {"a": a, "e": e, "I": I * RAD, "node": node * RAD, "peri": (varpi - node) * RAD,
		"M": fmod(M, 360.0) * RAD, "n": float(row[13]) * RAD / 36525.0}


## Eksentrinen anomalia E Keplerin yhtälöstä M = E − e sin E (Newtonin menetelmä).
static func eccentric_anomaly(M: float, e: float) -> float:
	M = atan2(sin(M), cos(M))
	var E := M + e * sin(M)
	for i in 20:
		var d := (E - e * sin(E) - M) / (1.0 - e * cos(E))
		E -= d
		if absf(d) < 1e-12:
			break
	return E


# Kiertää radan tason vektorin (xp perihelin suuntaan, yp liikkeen suuntaan) ekliptikan koordinaatteihin.
static func _to_ecliptic(el: Dictionary, xp: float, yp: float) -> PackedFloat64Array:
	var cw := cos(el.peri)
	var sw := sin(el.peri)
	var cO := cos(el.node)
	var sO := sin(el.node)
	var cI := cos(el.I)
	var sI := sin(el.I)
	return PackedFloat64Array([
		(cw * cO - sw * sO * cI) * xp + (-sw * cO - cw * sO * cI) * yp,
		(cw * sO + sw * cO * cI) * xp + (-sw * sO + cw * cO * cI) * yp,
		sw * sI * xp + cw * sI * yp,
	])


## Radan piste eksentrisellä anomalialla E ekliptikan koordinaateissa [x, y, z] (AU).
static func orbit_point(el: Dictionary, E: float) -> PackedFloat64Array:
	var e: float = el.e
	return _to_ecliptic(el, el.a * (cos(E) - e), el.a * sqrt(1.0 - e * e) * sin(E))


## Planeetan sijainti (AU) ja nopeus (AU/vrk) Auringon ympärillä hetkellä time (ms): {pos, vel}.
static func helio_state(name: String, time: float) -> Dictionary:
	var el := elements(name, time)
	var e: float = el.e
	var E := eccentric_anomaly(el.M, e)
	var dE: float = el.n / (1.0 - e * cos(E))
	return {
		"pos": orbit_point(el, E),
		"vel": _to_ecliptic(el, -el.a * sin(E) * dE, el.a * sqrt(1.0 - e * e) * cos(E) * dE),
	}


## Planeetan sijainti Auringon ympärillä hetkellä time (ms) astronomisina yksikköinä.
static func helio(name: String, time: float) -> PackedFloat64Array:
	var el := elements(name, time)
	return orbit_point(el, eccentric_anomaly(el.M, el.e))


## Kaikkien planeettojen sijainnit ja rata-alkiot hetkellä time: [{name, color, radius_km, period_years, el, E, pos}].
static func solar_system(time: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for name in NAMES:
		var p := info(name)
		var el := elements(name, time)
		var E := eccentric_anomaly(el.M, el.e)
		p.el = el
		p.E = E
		p.pos = orbit_point(el, E)
		out.append(p)
	return out


static func distance(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return sqrt((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2)
