class_name Faults
## Aluksen häiriöt (#42): vikatyypit, pulmien luonti ja tarkistus. Tila on Game.state.fault (JSON-yhteensopiva
## sanakirja), ja Game hoitaa ajastimen, aikasakot ja tuhoutumisen. Tyypit ja minipelit:
##   "johdot"  sähkövika: irronneet johdot kytketään oikeisiin liittimiin (värit), väärä kytkentä kipinöi
##   "koodi"   navigointitietokoneen ohjelmavirhe: virheellinen rivi etsitään ja korvataan oikealla
##   "paine"   jäähdytysvuoto: venttiileillä tasataan kolmen paineen lukemat vihreälle alueelle
## Väärä yritys vie aikaa (PENALTY_MS); kun aika loppuu, alus tuhoutuu.

const KINDS := ["johdot", "koodi", "paine"]
## Nimi, kuvaus, aika (ms) ja tuhon syy.
const INFO := {
	"johdot": {"name": "Sähkövika", "title": "Virranjakelun johdotus on irronnut",
		"help": "Kytke jokainen johto samanväriseen liittimeen: vedä tai napauta johtoa ja sitten liitintä.",
		"ms": 75000.0, "doom": "Virranjakelu romahti, ja alus menetti elintoimintonsa."},
	"koodi": {"name": "Ohjelmavirhe", "title": "Navigointitietokone laskee väärin",
		"help": "Etsi virheellinen rivi napauttamalla sitä ja valitse oikea korjaus.",
		"ms": 100000.0, "doom": "Navigointitietokone ohjasi aluksen tuhoon."},
	"paine": {"name": "Jäähdytysvuoto", "title": "Jäähdytysnesteen paineet karkaavat",
		"help": "Avaa ja sulje venttiilejä, kunnes kaikki kolme painetta ovat vihreällä alueella.",
		"ms": 80000.0, "doom": "Jäähdytysjärjestelmän paine räjäytti moottoritilan."},
}
const PENALTY_MS := 8000.0
## Johtojen värit: nimi, väri, raidan väri (sama perusväri erottuu raidasta) ja lyhenne liittimissä.
const WIRES := [["punainen", Color("#ff4d5e"), null, "PU"], ["keltainen", Color("#ffd23f"), null, "KE"], ["sininen", Color("#3d8bff"), null, "SI"],
	["vihreä", Color("#3ddc84"), null, "VI"], ["valkoinen", Color("#e8eefc"), null, "VA"], ["oranssi", Color("#ff9533"), null, "OR"],
	["punavalkoinen", Color("#ff4d5e"), Color("#e8eefc"), "PU/VA"], ["sinikeltainen", Color("#3d8bff"), Color("#ffd23f"), "SI/KE"]]
const WIRE_COUNT := 5
## Paineet: mittareita 3, venttiileitä 4, vihreä alue GREEN[0]…GREEN[1] asteikolla 0…10.
const GAUGES := 3
const VALVES := 4
const GREEN := [4, 6]
## Koodivirheet: otsikko, oire, rivit, virheellisen rivin indeksi ja vaihtoehdot (ensimmäinen oikea).
const CODE := [
	{"title": "Polttoaineen riittoaika", "symptom": "riittoaika 2,4 milj. s, odotettu 600 s",
		"lines": ["func riittoaika(massa_kg: float, kulutus_kg_s: float) -> float:", "\t# Polttoaineen riittoaika sekunteina",
			"\tif kulutus_kg_s == 0.0:", "\t\treturn INF", "\treturn massa_kg * kulutus_kg_s"],
		"bug": 4, "options": ["\treturn massa_kg / kulutus_kg_s", "\treturn kulutus_kg_s / massa_kg", "\treturn massa_kg - kulutus_kg_s"]},
	{"title": "Etäisyys kohteeseen", "symptom": "etäisyys heittelee, kun alus nousee ratatason yläpuolelle",
		"lines": ["func etaisyys(a: Vector3, b: Vector3) -> float:", "\tvar d := b - a", "\t# Pythagoraan lause kolmessa ulottuvuudessa",
			"\treturn sqrt(d.x * d.x + d.y * d.y + d.z * d.y)"],
		"bug": 3, "options": ["\treturn sqrt(d.x * d.x + d.y * d.y + d.z * d.z)", "\treturn sqrt(d.x + d.y + d.z)", "\treturn d.x * d.x + d.y * d.y + d.z * d.z"]},
	{"title": "Nopeuden yksikkö", "symptom": "nopeusnäyttö 7 790 000 km/s",
		"lines": ["func km_s(m_s: float) -> float:", "\t# Metrit sekunnissa kilometreiksi sekunnissa", "\treturn m_s * 1000.0"],
		"bug": 2, "options": ["\treturn m_s / 1000.0", "\treturn m_s * 3.6", "\treturn m_s / 3.6"]},
	{"title": "Jarrutuspoltto", "symptom": "jarrutus kiihdyttää alusta",
		"lines": ["func jarruta(v: float, dv: float) -> float:", "\t# Jarrutuspoltto pienentää nopeutta", "\tvar uusi := v + dv",
			"\treturn maxf(uusi, 0.0)"],
		"bug": 2, "options": ["\tvar uusi := v - dv", "\tvar uusi := v * dv", "\tvar uusi := dv - v"]},
	{"title": "Anturien keskiarvo", "symptom": "ensimmäinen lämpöanturi puuttuu keskiarvosta",
		"lines": ["func keskiarvo(anturit: Array) -> float:", "\tvar summa := 0.0", "\tfor i in range(1, anturit.size()):",
			"\t\tsumma += anturit[i]", "\treturn summa / anturit.size()"],
		"bug": 2, "options": ["\tfor i in range(anturit.size()):", "\tfor i in range(1, anturit.size() + 1):", "\tfor i in range(anturit.size() - 1):"]},
	{"title": "Ylikuumenemishälytys", "symptom": "hälytys soi kylmällä moottorilla ja vaikenee kuumalla",
		"lines": ["func ylikuumeneminen(lampo_c: float) -> bool:", "\tconst RAJA := 120.0", "\t# Hälytys, kun lämpö ylittää rajan",
			"\treturn lampo_c < RAJA"],
		"bug": 3, "options": ["\treturn lampo_c > RAJA", "\treturn lampo_c == RAJA", "\treturn RAJA > lampo_c"]},
	{"title": "Kulman muunnos", "symptom": "ohjaus kääntää aluksen 0,02° eikä 90°",
		"lines": ["func asteiksi(rad: float) -> float:", "\t# Radiaanit asteiksi", "\treturn rad * PI / 180.0"],
		"bug": 2, "options": ["\treturn rad * 180.0 / PI", "\treturn rad / PI * 360.0", "\treturn rad * 360.0"]},
	{"title": "Hapen tarve", "symptom": "happivarasto näyttää riittävän vuosiksi",
		"lines": ["func hapen_tarve(miehisto: int, tunnit: float) -> float:", "\tconst KG_TUNNISSA := 0.035",
			"\t# Happea kuluu henkeä ja tuntia kohden", "\treturn KG_TUNNISSA * miehisto + tunnit"],
		"bug": 3, "options": ["\treturn KG_TUNNISSA * miehisto * tunnit", "\treturn KG_TUNNISSA + miehisto * tunnit", "\treturn KG_TUNNISSA / miehisto * tunnit"]},
]


## Uusi vika: tyyppi, aikaa jäljellä (ms) ja pulma. rng antaa toistettavan pulman.
static func make(kind: String, rng: RandomNumberGenerator) -> Dictionary:
	var info: Dictionary = INFO[kind]
	var f := {"kind": kind, "remaining": info.ms, "total": info.ms, "mistakes": 0}
	match kind:
		"johdot":
			f.merge(_wires(rng))
		"koodi":
			f.merge(_code(rng))
		"paine":
			f.merge(_valves(rng))
	return f


static func _shuffled(n: int, rng: RandomNumberGenerator) -> Array:
	var a := range(n)
	for i in range(n - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = a[i]
		a[i] = a[j]
		a[j] = tmp
	return a


static func _wires(rng: RandomNumberGenerator) -> Dictionary:
	var colors: Array = _shuffled(WIRES.size(), rng).slice(0, WIRE_COUNT)
	var order := _shuffled(WIRE_COUNT, rng)
	# Oikea järjestys ei saa olla sama kuin vasen (pulma olisi liian helppo).
	if order == range(WIRE_COUNT):
		order.push_back(order.pop_front())
	var right := []
	for i in WIRE_COUNT:
		right.append(colors[order[i]])
	return {"left": colors, "right": right, "links": []}


static func _code(rng: RandomNumberGenerator) -> Dictionary:
	var id := rng.randi_range(0, CODE.size() - 1)
	var c: Dictionary = CODE[id]
	var order := _shuffled(c.options.size(), rng)
	return {"code": id, "order": order, "line": -1}


## Venttiilien vaikutukset: kukin venttiili muuttaa kahta mittaria (−2…+2). Aloituslukemat lasketaan arvotusta
## ratkaisusta, joten pulma on aina ratkaistavissa, eikä se ole valmiiksi ratkaistu.
static func _valves(rng: RandomNumberGenerator) -> Dictionary:
	var effects := []
	for v in VALVES:
		var e := [0, 0, 0]
		var pick := _shuffled(GAUGES, rng)
		e[pick[0]] = [-2, -1, 1, 2][rng.randi_range(0, 3)]
		e[pick[1]] = [-2, -1, 1, 2][rng.randi_range(0, 3)]
		effects.append(e)
	for attempt in 50:
		var open := []
		for v in VALVES:
			open.append(rng.randf() < 0.5)
		if not open.has(true):
			open[rng.randi_range(0, VALVES - 1)] = true
		var start := []
		var ok := true
		for g in GAUGES:
			var target := rng.randi_range(GREEN[0], GREEN[1])
			var s := target
			for v in VALVES:
				if open[v]:
					s -= int(effects[v][g])
			ok = ok and s >= 0 and s <= 10
			start.append(s)
		var f := {"effects": effects, "start": start, "valves": [false, false, false, false]}
		if ok and not pressures_ok(f):
			return f
	# Varalle: yksinkertainen ratkaistava tila.
	return {"effects": [[2, -1, 0], [0, 2, -1], [-1, 0, 2], [1, 1, 0]], "start": [3, 3, 3], "valves": [false, false, false, false]}


## Mittarien lukemat venttiilien asennoilla.
static func pressures(f: Dictionary) -> Array:
	var out := []
	for g in GAUGES:
		var s := int(f.start[g])
		for v in VALVES:
			if f.valves[v]:
				s += int(f.effects[v][g])
		out.append(s)
	return out


static func pressures_ok(f: Dictionary) -> bool:
	for p: int in pressures(f):
		if p < GREEN[0] or p > GREEN[1]:
			return false
	return true


## Johto vasemmalta l oikeaan liittimeen r: oikein, jos värit täsmäävät.
static func wire_ok(f: Dictionary, l: int, r: int) -> bool:
	return l >= 0 and r >= 0 and l < f.left.size() and r < f.right.size() and int(f.left[l]) == int(f.right[r])


static func wires_done(f: Dictionary) -> bool:
	return f.links.size() >= f.left.size()


## Koodipulman rivit, virheellinen rivi ja vaihtoehdot näyttöjärjestyksessä (oikea = oikean vaihtoehdon paikka).
static func code_of(f: Dictionary) -> Dictionary:
	var c: Dictionary = CODE[int(f.code)]
	var opts := []
	var right := 0
	for i in f.order.size():
		opts.append(c.options[int(f.order[i])])
		if int(f.order[i]) == 0:
			right = i
	return {"title": c.title, "symptom": c.symptom, "lines": c.lines, "bug": c.bug, "options": opts, "right": right}


## Tuhon syy tekstinä.
static func doom(kind: String) -> String:
	return INFO[kind].doom if INFO.has(kind) else "Alus tuhoutui."
