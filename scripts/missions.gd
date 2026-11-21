class_name Missions
## Lennonjohdon tehtävät (#44): tehtävien arvonta, ehdot ja tekstit. Tila on Game.state.missions (JSON-yhteensopiva):
##   {"active": [tehtävä…], "done": [tehtävä…], "points": tutkimuspisteet, "seq": seuraavan tehtävän numero}
## "dropped": ["laji kohde"…] luovutut tehtävät, joita ei anneta uudelleen.
## Tehtävä: {"id", "kind", "body", "points", "t" (annettu), "from" ja "limit" (lajin mukaan), "doneAt" (suoritettu)}.
## Lajit:
##   "orbit"   saavu kohteen kiertoradalle
##   "survey"  kartoita kohde kiertoradalta
##   "flyby"   linkoa planeetan ohi matkalla toiseen kohteeseen
##   "aero"    ilmajarruta kaasujättiläisen kaasukehässä kiertoradalle
##   "fast"    lennä lähtöplaneetalta kohteen kiertoradalle aikarajan alla (vrk)
##   "frugal"  lennä lähtöplaneetalta kohteen kiertoradalle Δv-rajan alla (km/s)
##   "land"    laskeudu kohteen pinnalle (#45)
##   "fault"   korjaa seuraava vika niin, että aikaa jää vähintään rajan verran (s)
## Tapahtumat (match): {"type": "capture", "body", "aero", "from", "days", "dv"}, {"type": "survey", "body"},
## {"type": "flyby", "body"}, {"type": "land", "body"} ja {"type": "fault", "left"}. Arvonta on toistettava: siemen on tehtävän numero.

const ACTIVE := 3
## Kohteiden vaikeusportaat ja portaan peruspalkkio (tutkimuspisteet). Porras aukeaa suoritettujen tehtävien määrällä.
const TIERS := [["Kuu", "Mars", "Venus"], ["Phobos", "Merkurius", "Jupiter", "Io", "Europa", "Ganymedes"],
	["Saturnus", "Titan", "Enceladus", "Uranus", "Neptunus", "Triton"]]
const TIER_POINTS := [10, 25, 50]
const TIER_UNLOCK := [0, 2, 5]
## Lajien palkkiokerroin.
const FACTOR := {"orbit": 1.0, "survey": 1.5, "flyby": 1.5, "aero": 1.5, "fast": 2.0, "frugal": 2.0, "land": 2.5}
const FLYBY_BODIES := ["Venus", "Mars", "Jupiter", "Saturnus"]
const FAULT_POINTS := 15
const FAULT_LEFT_S := 30.0
## Aikaraja Hohmannin siirron kestosta ja Δv-raja Hohmannin siirron Δv:stä.
const FAST_SHARE := 0.8
const FRUGAL_MARGIN := 1.12


static func fresh() -> Dictionary:
	return {"active": [], "done": [], "points": 0, "seq": 0}


static func tier_of(body: String) -> int:
	for i in TIERS.size():
		if body in TIERS[i]:
			return i
	return 0


## Avoimet portaat suoritettujen tehtävien määrän mukaan.
static func tiers_open(done: int) -> int:
	var n := 0
	for need: int in TIER_UNLOCK:
		if done >= need:
			n += 1
	return n


## Kohteen kiertorata on jo saavutettu jollakin lennolla.
static func _visited(s: Dictionary, body: String) -> bool:
	for f: Dictionary in s.get("flights", []):
		if f.get("to") == body and f.get("captured", false):
			return true
	return false


static func _taken(ms: Dictionary, kind: String, body: String) -> bool:
	for list: String in ["active", "done"]:
		for m: Dictionary in ms[list]:
			if m.kind == kind and m.get("body", "") == body:
				return true
	return ms.get("dropped", []).has("%s %s" % [kind, body])


## Lähtöplaneetta aika- ja Δv-tehtäville: aluksen planeetta (kuusta emoplaneetta), muuten Maa.
static func origin_of(s: Dictionary) -> String:
	var loc: Variant = s.get("location")
	if loc is String:
		return Flight.MOONS[loc].parent if Flight.is_moon(loc) else loc
	return "Maa"


## Hohmannin siirto planeettojen välillä: {"days", "dv"} (lähtö- ja jarrutuspolton Δv pysäköintiradoilta).
static func hohmann_estimate(from: String, to: String) -> Dictionary:
	var h := Flight.hohmann(float(Planets._row(from)[4]) * Planets.AU_KM, float(Planets._row(to)[4]) * Planets.AU_KM)
	return {"days": float(h.tof) / Flight.DAY_S, "dv": Flight.burn_dv(from, h.vinfDep) + Flight.burn_dv(to, h.vinfArr)}


## Tehtäväehdokkaat: [laji, kohde, palkkio, lisätiedot].
static func candidates(ms: Dictionary, s: Dictionary, faults_on: bool) -> Array:
	var out := []
	var open := tiers_open(ms.done.size())
	var explored: Array = s.get("explored", [])
	var origin := origin_of(s)
	for tier in open:
		var base: int = TIER_POINTS[tier]
		for body: String in TIERS[tier]:
			var pts := func(kind: String) -> int: return int(roundf(base * float(FACTOR[kind])))
			if not _visited(s, body) and s.get("location") != body and not _taken(ms, "orbit", body):
				out.append(["orbit", body, pts.call("orbit"), {}])
			if not explored.has(body) and not _taken(ms, "survey", body):
				out.append(["survey", body, pts.call("survey"), {}])
			if body in FLYBY_BODIES and not _taken(ms, "flyby", body):
				out.append(["flyby", body, pts.call("flyby"), {}])
			if Landing.can_land(body) and not _taken(ms, "land", body):
				out.append(["land", body, pts.call("land"), {}])
			if Flight.has_low_orbit(body) and not _taken(ms, "aero", body):
				out.append(["aero", body, pts.call("aero"), {}])
			if not Flight.is_moon(body) and body != origin and tier < 2:
				var h := hohmann_estimate(origin, body)
				if not _taken(ms, "fast", body):
					out.append(["fast", body, pts.call("fast"), {"from": origin, "limit": ceilf(float(h.days) * FAST_SHARE)}])
				if not _taken(ms, "frugal", body):
					out.append(["frugal", body, pts.call("frugal"), {"from": origin, "limit": ceilf(float(h.dv) * FRUGAL_MARGIN * 10.0) / 10.0}])
	if faults_on and not ms.active.any(func(m: Dictionary) -> bool: return m.kind == "fault"):
		out.append(["fault", "", FAULT_POINTS, {"limit": FAULT_LEFT_S}])
	return out


## Arpoo seuraavan tehtävän ({} jos ehdokkaita ei ole). Ensimmäinen tehtävä on Kuun kiertorata. Uusimman avatun
## portaan kohteita painotetaan kaksinkertaisesti.
static func generate(ms: Dictionary, s: Dictionary, faults_on: bool, t: float) -> Dictionary:
	var list := candidates(ms, s, faults_on)
	if list.is_empty():
		return {}
	var pick: Array = list[0]
	var first := list.filter(func(c: Array) -> bool: return c[0] == "orbit" and c[1] == "Kuu")
	if int(ms.seq) == 0 and not first.is_empty():
		pick = first[0]
	else:
		var top := tiers_open(ms.done.size()) - 1
		var weights := PackedFloat32Array()
		for c: Array in list:
			weights.append(2.0 if c[1] != "" and tier_of(c[1]) == top and top > 0 else 1.0)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(int(ms.seq) * 7919 + 13)
		pick = list[rng.rand_weighted(weights)]
	var m := {"id": int(ms.seq), "kind": pick[0], "body": pick[1], "points": pick[2], "t": t}
	m.merge(pick[3])
	ms.seq = int(ms.seq) + 1
	return m


## Täydentää aktiiviset tehtävät ACTIVE kappaleeseen. Palauttaa uudet tehtävät.
static func refill(ms: Dictionary, s: Dictionary, faults_on: bool, t: float) -> Array:
	var added := []
	while ms.active.size() < ACTIVE:
		var m := generate(ms, s, faults_on, t)
		if m.is_empty():
			break
		ms.active.append(m)
		added.append(m)
	return added


## Täyttääkö tapahtuma tehtävän ehdon.
static func matches(m: Dictionary, ev: Dictionary) -> bool:
	var body: String = m.get("body", "")
	match m.kind:
		"orbit":
			return ev.type == "capture" and ev.body == body
		"survey":
			return ev.type == "survey" and ev.body == body
		"flyby":
			return ev.type == "flyby" and ev.body == body
		"aero":
			return ev.type == "capture" and ev.body == body and ev.get("aero", false)
		"fast":
			return ev.type == "capture" and ev.body == body and ev.get("from") == m.from and float(ev.get("days", INF)) <= float(m.limit)
		"frugal":
			return ev.type == "capture" and ev.body == body and ev.get("from") == m.from and float(ev.get("dv", INF)) <= float(m.limit) + 1e-9
		"land":
			return ev.type == "land" and ev.body == body
		"fault":
			return ev.type == "fault" and float(ev.get("left", 0.0)) >= float(m.limit)
	return false


## Merkitsee tapahtuman täyttämät tehtävät suoritetuiksi ja lisää pisteet. Palauttaa suoritetut.
static func complete(ms: Dictionary, ev: Dictionary, t: float) -> Array:
	var done := []
	for m: Dictionary in ms.active.duplicate():
		if matches(m, ev):
			ms.active.erase(m)
			m.doneAt = t
			ms.done.append(m)
			ms.points = int(ms.points) + int(m.points)
			done.append(m)
	return done


static func title(m: Dictionary) -> String:
	var body: String = m.get("body", "")
	match m.kind:
		"orbit":
			return "Kiertoradalle: %s" % body
		"survey":
			return "Kartoita %s" % body
		"flyby":
			return "Linkous %s ohi" % Fmt.gen(body)
		"aero":
			return "Ilmajarrutus: %s" % body
		"fast":
			return "Pikalento: %s" % body
		"frugal":
			return "Säästölento: %s" % body
		"land":
			return "Laskeutuminen: %s" % body
		"fault":
			return "Vikapäivystys"
	return String(m.kind)


static func text(m: Dictionary) -> String:
	var body: String = m.get("body", "")
	match m.kind:
		"orbit":
			return "Saavu %s kiertoradalle." % Fmt.gen(body)
		"survey":
			return "Tutki %s kiertoradalta (kartoitus kestää vuorokauden)." % Fmt.par(body)
		"flyby":
			return "Lennä %s ohi matkalla toiseen kohteeseen: valitse reitti, jossa on linkous." % Fmt.gen(body)
		"aero":
			return "Jarruta %s kaasukehässä matalalle kiertoradalle." % Fmt.gen(body)
		"fast":
			return "Lennä %s %s kiertoradalle enintään %s." % [Fmt.from_text(m.from), Fmt.gen(body), Fmt.days(float(m.limit))]
		"frugal":
			return "Lennä %s %s kiertoradalle enintään %s:llä (lähtö, korjaukset ja jarrutus)." % [Fmt.from_text(m.from), Fmt.gen(body), Fmt.dv(float(m.limit))]
		"land":
			return "Laskeudu %s pinnalle." % Fmt.gen(body)
		"fault":
			return "Korjaa seuraava aluksen vika niin, että aikaa jää vähintään %d s." % int(m.limit)
	return ""


## Täyttääkö reittivaihtoehto (Game.options) tehtävän, jos lento päättyy kiertoradalle: linkous-, pika- ja
## säästötehtävät. from: lähtöpaikka (Game.here()), to: kohde.
static func fits_option(m: Dictionary, o: Dictionary, from: Variant, to: String) -> bool:
	match m.kind:
		"flyby":
			return o.get("via", "") == m.body
		"fast":
			return to == m.body and from is String and from == m.from and (float(o.arrive) - float(o.depart)) / Flight.DAY_MS <= float(m.limit)
		"frugal":
			return to == m.body and from is String and from == m.from and float(o.dvTotal) <= float(m.limit) + 1e-9
	return false


## Tehtävän kohde (kohdepainikkeiden merkintä), tyhjä, jos tehtävällä ei ole kohdetta.
static func targets(ms: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for m: Dictionary in ms.get("active", []):
		var b: String = m.get("body", "")
		if b != "" and not out.has(b):
			out.append(b)
	return out
