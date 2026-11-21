class_name Landing
## Laskeutuminen kuun pinnalle ja nousu takaisin kiertoradalle (#45). Kaikki laskut kappaleen keskipisteen suhteen
## (km, ekliptikan koordinaatit) kuten pysäköintiradoilla.
##
## Kuun pintakoordinaatisto pyörii kuun mukana: pituusaste 0 osoittaa emoplaneettaan (kuu kääntää aina saman puolen
## planeettaansa kohti, kuten Space piirtää), akseli on ekliptikan pohjoinen ja itä on kiertosuuntaan.
##
## Automaattilasku kuten Apollossa:
##   1. Radan laskupoltto (DOI) pysäköintiradalla: alus siirtyy ellipsille, jonka perikeskus on 15 km korkeudella
##      kohdassa P ennen laskeutumispaikkaa.
##   2. Liuku puolikas ellipsiä perikeskukseen (vapaa rata, Game propagoi sen).
##   3. Laskeutumispoltto (PDI) perikeskuksessa: jarrutus- ja lähestymisvaihe isoympyrää pitkin paikan ylle tasaisella
##      hidastuvuudella, korkeus 15 km → 100 m, ja pystylasku 100 m → pinta (TERMINAL_S).
## Nousu: isoympyrää pitkin laukaisupaikasta pysäköintiradan kohtaan Q kiihtyen ratanopeuteen, korkeus 0 → 100 km.
## Δv: radan muutokset Keplerin mukaan, painovoimahäviöt (moottori kannattelee alusta kuun painovoimaa vastaan) ja
## suunnanmuutos, jos paikka ei ole pysäköintiradan tasossa (ekliptika): napa-alueelle laskeutuminen on kallista.
##
## Tila Game.state.orbit (JSON): {"descent": {...}} laskeutumispolton ajan, {"surface": {"lat", "lon", "site"}}
## pinnalla ja {"ascent": {...}} nousun ajan. Flight.parking_state laskee niistä aluksen paikan.

## Laskeutumispaikat: nimi, leveys (°, pohjoinen +) ja pituus (°, itä +).
const SITES := [
	["Rauhallisuuden meri (Apollo 11)", 0.674, 23.473],
	["Myrskyjen valtameri (Apollo 12)", -3.012, -23.422],
	["Hadley–Apenniinit (Apollo 15)", 26.132, 3.634],
	["Taurus–Littrow (Apollo 17)", 20.191, 30.772],
	["Kopernikuksen kraatteri", 9.62, -20.08],
	["Tychon kraatteri", -43.31, -11.36],
	["Shackleton, etelänapa", -89.54, 0.0],
]
## Kappaleet, joille voi laskeutua.
const BODIES := ["Kuu"]
const PDI_ALT_KM := 15.0
const HOVER_KM := 0.1
const TERMINAL_S := 50.0
## Laskeutumispolton kantama (isoympyrän kulma) ja nousun kantama.
const PD_RANGE := deg_to_rad(16.0)
const ASCENT_RANGE := deg_to_rad(10.0)
## Laskeutumisen ja nousun kesto lisäksi: polton aloitus aikaisintaan näin pian (ms).
const LEAD_MS := 60000.0
## Pehmeä kosketus käsin: suurin pystynopeus ja vaakanopeus pinnan suhteen (km/s).
const SAFE_VS := 0.004
const SAFE_VH := 0.003
## Painovoimahäviön osuus jarrutusvaiheen kestosta (moottori kannattelee osittain painovoimaa vastaan).
const BRAKE_GRAVITY := 0.3
const ASCENT_GRAVITY := 0.35


static func can_land(body: Variant) -> bool:
	return body is String and body in BODIES


static func _mu(body: String) -> float:
	return float(Flight.orbit_of(body).mu)


static func _radius(body: String) -> float:
	return float(Flight.orbit_of(body).radiusKm)


static func _park(body: String) -> float:
	return float(Flight.orbit_of(body).periKm)


## Kuun pyörimiskulma (rad): suunta kuusta emoplaneettaan ekliptikan tasossa, ja pyörimisnopeus (rad/s).
static func _spin(body: String, t: float) -> Array:
	var m: Dictionary = Flight.MOONS[body]
	var r: PackedFloat64Array = Flight.moon_rel(body, t).r
	return [atan2(-r[1], -r[0]), TAU / (float(m.periodDays) * Flight.DAY_S)]


## Pinnan suunta (yksikkövektori) leveydellä lat ja pituudella lon (°) hetkellä t.
static func site_dir(body: String, lat: float, lon: float, t: float) -> PackedFloat64Array:
	var a: float = float(_spin(body, t)[0]) + deg_to_rad(lon)
	var la := deg_to_rad(lat)
	return Flight.vec(cos(la) * cos(a), cos(la) * sin(a), sin(la))


## Leveys ja pituus (°) suunnasta rel_r hetkellä t.
static func lat_lon(body: String, rel_r: PackedFloat64Array, t: float) -> Vector2:
	var n := Flight.norm(rel_r)
	var a := atan2(rel_r[1], rel_r[0]) - float(_spin(body, t)[0])
	return Vector2(rad_to_deg(asin(clampf(rel_r[2] / n, -1.0, 1.0))), rad_to_deg(wrapf(a, -PI, PI)))


## Pinnan piste korkeudella alt_km: paikka ja nopeus (pyörii kuun mukana).
static func surface_rel(body: String, lat: float, lon: float, t: float, alt_km: float = 0.0) -> Dictionary:
	var d := site_dir(body, lat, lon, t)
	var r := Flight.scale(d, _radius(body) + alt_km)
	var w: float = _spin(body, t)[1]
	return {"r": r, "v": Flight.vec(-w * r[1], w * r[0], 0.0)}


## Pintanopeus kohdassa rel_r (kuun pyöriminen).
static func ground_velocity(body: String, rel_r: PackedFloat64Array, t: float) -> PackedFloat64Array:
	var w: float = _spin(body, t)[1]
	return Flight.vec(-w * rel_r[1], w * rel_r[0], 0.0)


## Pysty- ja vaakanopeus pinnan suhteen (km/s; pysty + ylös).
static func surface_speeds(body: String, rel_r: PackedFloat64Array, rel_v: PackedFloat64Array, t: float) -> Vector2:
	var v := Flight.sub(rel_v, ground_velocity(body, rel_r, t))
	var up := Flight.scale(rel_r, 1.0 / Flight.norm(rel_r))
	var vs := Flight.dot(v, up)
	return Vector2(vs, Flight.norm(Flight.sub(v, Flight.scale(up, vs))))


static func _unit(v: PackedFloat64Array) -> PackedFloat64Array:
	return Flight.scale(v, 1.0 / maxf(Flight.norm(v), 1e-12))


## Isoympyrän suunta pisteestä a kohti pistettä b (yksikkövektori a:n tangenttitasossa).
static func _toward(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var g := Flight.sub(b, Flight.scale(a, Flight.dot(a, b)))
	if Flight.norm(g) < 1e-9:
		return _unit(Flight.cross(Flight.vec(0.0, 0.0, 1.0), a))
	return _unit(g)


## Ekliptikan ympyrän kohta, josta kulma isoympyrää pitkin pisteeseen s on range (tai vähintään s:n leveys):
## sign −1 ennen paikkaa (laskeutuminen), +1 paikan jälkeen (nousu).
static func _circle_point(s: PackedFloat64Array, range_rad: float, sign: float) -> float:
	var lam := atan2(s[1], s[0])
	var cl := sqrt(maxf(s[0] * s[0] + s[1] * s[1], 0.0))
	var c := cos(range_rad) / maxf(cl, 1e-9)
	var d := acos(c) if c < 1.0 else 0.0
	return lam + sign * d


## Automaattilaskun suunnitelma pysäköintiradalta (orbit = {epoch, arg} tai null) hetken now jälkeen: polttojen
## hetket, Δv:t ja laskeutumispolton isoympyrä. {} jos lasku ei ole mahdollinen.
static func plan_descent(body: String, orbit: Variant, lat: float, lon: float, now: float, site: String = "") -> Dictionary:
	if not can_land(body) or Flight.is_free_orbit(orbit) or is_special(orbit):
		return {}
	var mu := _mu(body)
	var R := _radius(body)
	var r1 := _park(body)
	var rp := R + PDI_ALT_KM
	var a := (r1 + rp) / 2.0
	var n := sqrt(mu / (r1 * r1 * r1))
	var coast := PI * sqrt(a * a * a / mu) * 1000.0
	var vp := sqrt(mu * (2.0 / rp - 1.0 / a))
	var epoch := Flight._orbit_epoch(orbit)
	var arg := Flight._orbit_arg(orbit)
	var t_land := now + LEAD_MS + coast + 600000.0
	var plan := {}
	for i in 3:
		var s := site_dir(body, lat, lon, t_land)
		var phi_p := _circle_point(s, PD_RANGE, -1.0)
		var p_hat := Flight.vec(cos(phi_p), sin(phi_p), 0.0)
		var theta := acos(clampf(Flight.dot(p_hat, s), -1.0, 1.0))
		# DOI vastapäätä P:tä: seuraava hetki, jolloin alus on kulmassa φ_P − π.
		var now_angle := arg + n * (now + LEAD_MS - epoch) / 1000.0
		var turn := fposmod(phi_p - PI - now_angle, TAU)
		var t_doi := now + LEAD_MS + turn / n * 1000.0
		var t_pdi := t_doi + coast
		var brake := 2.0 * theta * (rp - PDI_ALT_KM / 2.0) / vp * 1000.0
		var t_hover := t_pdi + brake
		t_land = t_hover + TERMINAL_S * 1000.0
		var g := _toward(p_hat, s)
		var prograde := Flight.vec(-sin(phi_p), cos(phi_p), 0.0)
		var di := acos(clampf(Flight.dot(prograde, g), -1.0, 1.0))
		var g0 := mu / (R * R)
		var dv_doi := sqrt(mu / r1) - sqrt(mu * (2.0 / r1 - 1.0 / a))
		var dv_pd := vp + 2.0 * vp * sin(di / 2.0) + g0 * (BRAKE_GRAVITY * brake / 1000.0 + TERMINAL_S)
		plan = {"body": body, "site": site, "lat": lat, "lon": lon, "tDoi": t_doi, "tPdi": t_pdi, "tHover": t_hover,
			"tLand": t_land, "p": p_hat, "g": g, "theta": theta, "dvDoi": dv_doi, "dvPd": dv_pd, "dvTotal": dv_doi + dv_pd,
			"planeDeg": rad_to_deg(di), "phase": "armed"}
	return plan


## Ellipsin alku laskupolton jälkeen: vapaa rata {epoch, arg, rel} (Flight.is_free_orbit).
static func doi_orbit(body: String, plan: Dictionary) -> Dictionary:
	var mu := _mu(body)
	var r1 := _park(body)
	var rp := _radius(body) + PDI_ALT_KM
	var a := (r1 + rp) / 2.0
	var p: PackedFloat64Array = PackedFloat64Array(plan.p)
	var d := Flight.scale(p, -1.0)
	var va := sqrt(mu * (2.0 / r1 - 1.0 / a))
	var tangent := Flight.vec(-d[1], d[0], 0.0)
	return {"epoch": plan.tDoi, "arg": atan2(d[1], d[0]), "rel": {"r": Flight.scale(d, r1), "v": Flight.scale(tangent, va)}}


## Laskeutumispolton paikka hetkellä t (ilman nopeutta).
static func _descent_pos(body: String, d: Dictionary, t: float) -> PackedFloat64Array:
	var R := _radius(body)
	var t_pdi: float = d.tPdi
	var t_hover: float = d.tHover
	if t < t_hover:
		var s := clampf((t - t_pdi) / maxf(t_hover - t_pdi, 1.0), 0.0, 1.0)
		var f := 2.0 * s - s * s
		var ang: float = float(d.theta) * f
		var p := PackedFloat64Array(d.p)
		var g := PackedFloat64Array(d.g)
		var dir := Flight.add(Flight.scale(p, cos(ang)), Flight.scale(g, sin(ang)))
		var h := HOVER_KM + (PDI_ALT_KM - HOVER_KM) * (1.0 - (3.0 * s * s - 2.0 * s * s * s))
		return Flight.scale(dir, R + h)
	var sb := clampf((t - t_hover) / (TERMINAL_S * 1000.0), 0.0, 1.0)
	var site := site_dir(body, d.lat, d.lon, d.tLand)
	return Flight.scale(site, R + HOVER_KM * (1.0 - (3.0 * sb * sb - 2.0 * sb * sb * sb)))


## Nousun paikka hetkellä t.
static func _ascent_pos(body: String, a: Dictionary, t: float) -> PackedFloat64Array:
	var R := _radius(body)
	var s := clampf((t - float(a.t0)) / maxf(float(a.t1) - float(a.t0), 1.0), 0.0, 1.0)
	var ang: float = float(a.theta) * s * s
	var s0 := PackedFloat64Array(a.s)
	var g := PackedFloat64Array(a.g)
	var dir := Flight.add(Flight.scale(s0, cos(ang)), Flight.scale(g, sin(ang)))
	var h := (_park(body) - R) * (3.0 * s * s - 2.0 * s * s * s)
	return Flight.scale(dir, R + h)


## Onko rata laskeutumisen, pinnan tai nousun tila.
static func is_special(orbit: Variant) -> bool:
	return orbit is Dictionary and (orbit.has("surface") or orbit.has("descent") or orbit.has("ascent"))


static func is_surface(orbit: Variant) -> bool:
	return orbit is Dictionary and orbit.has("surface")


## Aluksen paikka ja nopeus kappaleen suhteen erikoistilassa (Flight.parking_state).
static func rel_state(body: String, orbit: Dictionary, t: float) -> Dictionary:
	if orbit.has("surface"):
		var sf: Dictionary = orbit.surface
		return surface_rel(body, sf.lat, sf.lon, t)
	var pos := func(tt: float) -> PackedFloat64Array:
		return _descent_pos(body, orbit.descent, tt) if orbit.has("descent") else _ascent_pos(body, orbit.ascent, tt)
	var r: PackedFloat64Array = pos.call(t)
	# Nopeus erotusosamäärästä; alun ja lopun kohdalla yksipuolisesti, jotta nopeus jatkuu vaiheiden rajalla.
	var start: float = float(orbit.descent.tPdi) if orbit.has("descent") else float(orbit.ascent.t0)
	var end: float = float(orbit.descent.tLand) if orbit.has("descent") else float(orbit.ascent.t1)
	var t1 := clampf(t - 250.0, start, end - 500.0)
	var a: PackedFloat64Array = pos.call(t1)
	var b: PackedFloat64Array = pos.call(t1 + 500.0)
	return {"r": r, "v": Flight.add(Flight.scale(Flight.sub(b, a), 1.0 / 0.5), ground_velocity(body, r, t) if orbit.has("descent") and t >= end else Flight.vec(0, 0, 0))}


## Laskeutumisen vaihe ja työntö (ohjaamo ja näytöt).
static func descent_phase(d: Dictionary, t: float) -> Array:
	if t >= float(d.tHover):
		return ["Pystylasku", 0.35]
	var s := (t - float(d.tPdi)) / maxf(float(d.tHover) - float(d.tPdi), 1.0)
	return ["Jarrutusvaihe", 1.0] if s < 0.7 else ["Lähestymisvaihe", 0.6]


## Nousun suunnitelma paikasta (lat, lon) hetkellä t0: {t0, t1, s, g, theta, arg (pysäköintiradan perikeskus), dv}.
static func plan_ascent(body: String, lat: float, lon: float, t0: float) -> Dictionary:
	var mu := _mu(body)
	var R := _radius(body)
	var r2 := _park(body)
	var v2 := sqrt(mu / r2)
	var s := site_dir(body, lat, lon, t0)
	var lq := _circle_point(s, ASCENT_RANGE, 1.0)
	var q := Flight.vec(cos(lq), sin(lq), 0.0)
	var theta := maxf(acos(clampf(Flight.dot(s, q), -1.0, 1.0)), deg_to_rad(2.0))
	var g := _toward(s, q)
	if Flight.dot(s, q) > cos(deg_to_rad(2.0)):
		g = Flight.vec(-s[1], s[0], 0.0)
		g = _unit(g)
	var dur := 2.0 * theta * r2 / v2 * 1000.0
	# Saapumissuunta isoympyrää pitkin vs. pysäköintiradan menosuunta Q:ssa.
	var end_dir := Flight.add(Flight.scale(s, -sin(theta)), Flight.scale(g, cos(theta)))
	var prograde := Flight.vec(-sin(lq), cos(lq), 0.0)
	var di := acos(clampf(Flight.dot(_unit(end_dir), prograde), -1.0, 1.0))
	var g0 := mu / (R * R)
	var dv := v2 + 2.0 * v2 * sin(di / 2.0) + g0 * ASCENT_GRAVITY * dur / 1000.0
	return {"t0": t0, "t1": t0 + dur, "s": s, "g": g, "theta": theta, "arg": lq, "dv": dv, "planeDeg": rad_to_deg(di)}


## Ohjaamon asento laskeutuessa, pinnalla ja noustessa: nokka vaakatasossa menosuuntaan (pinnalla kohti
## emoplaneettaa), hieman alaspäin, jotta pinta näkyy ikkunasta, ja katto ylös. {nose, up}
static func attitude(body: String, orbit: Dictionary, rel: Dictionary, t: float) -> Dictionary:
	var up := _unit(PackedFloat64Array(rel.r))
	var fwd: PackedFloat64Array
	var down := 0.0
	if orbit.has("surface"):
		var to_parent := Flight.scale(PackedFloat64Array(Flight.moon_rel(body, t).r), -1.0)
		fwd = Flight.sub(to_parent, Flight.scale(up, Flight.dot(to_parent, up)))
		down = 0.0
	else:
		var v := Flight.sub(PackedFloat64Array(rel.v), ground_velocity(body, rel.r, t))
		fwd = Flight.sub(v, Flight.scale(up, Flight.dot(v, up)))
		if Flight.norm(fwd) < 1e-4:
			fwd = PackedFloat64Array(orbit.descent.g) if orbit.has("descent") else PackedFloat64Array(orbit.ascent.g)
			fwd = Flight.sub(fwd, Flight.scale(up, Flight.dot(fwd, up)))
		down = deg_to_rad(8.0)
	fwd = _unit(fwd)
	var nose := _unit(Flight.add(Flight.scale(fwd, cos(down)), Flight.scale(up, -sin(down))))
	var roof := _unit(Flight.add(Flight.scale(up, cos(down)), Flight.scale(fwd, sin(down))))
	return {"nose": nose, "up": roof}
