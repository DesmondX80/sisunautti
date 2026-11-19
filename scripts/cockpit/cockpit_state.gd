class_name CockpitState
## Ohjaamon tila pelin tilasta (web/js/voyage.js: cockpitState): aluksen paikka ja nopeus Auringon suhteen (km),
## kohde, johon nokka osoittaa (aim) tai nokan ja katon suunnat (nose, up), kiihdytys, tärinä, moottorin hehku,
## taivaan kirkkaus ja väri sekä kolmen päänäytön rivit.
## Näyttörivit: [otsikko, [[teksti, koko, väri?], ...], polttoaine 0–1 tai null].

## Ohjaamokuvan "suoraan eteen" on kojelaudan näyttöjen yläreunassa, joten kohde nostetaan ikkunan keskelle (rad).
const AIM_RAISE := 0.227 # 13°
## Matalalla radalla horisontti ikkunan alaosassa (rad näkymän keskeltä ylöspäin).
const HORIZON_RAISE := 0.262 # 15°
const DEG := PI / 180.0
const MUTED := Color("#8b9ac0")
const WARM := Color("#ffb547")
const FG := Color("#e8eefc")


static func _shake_left(at: float, dur: float) -> float:
	return clampf(1.0 - (Game.real_ms() - at) / dur, 0.0, 1.0)


static func make() -> Dictionary:
	var s: Dictionary = Game.state
	var t := Game.sim_now()
	var burn := _shake_left(Game.burn_at, Game.BURN_SHAKE_MS)
	var aero := _shake_left(Game.aero_at, Game.AERO_MS)
	var warp_name: String = Game.WARPS[Game.warp_index()][1]
	var fuel_frac := clampf(float(s.fuel) / Game.fuel_max(), 0.0, 1.0)
	var base := {"t": t, "warp": float(Game.WARPS[Game.warp_index()][0]), "shake": maxf(burn * 0.7, aero * 0.95), "thrust": burn,
		"sky": aero * 0.3 if aero > 0.0 else 0.0, "sky_color": Color("#ff6a1f") if aero > 0.0 else null, "aero": aero,
		"phase": "", "fuel": fuel_frac, "low_orbit": s.get("lowOrbit") != null}
	if s.pad:
		var lift: Variant = s.ascent.liftoff if s.ascent != null else null
		var L := Flight.launch_state(lift, t)
		var r: PackedFloat64Array = L.r
		var rn := Flight.norm(r)
		var sun_dir := Flight.scale(r, -1.0 / rn)
		var rel_r: PackedFloat64Array = L.rel.r
		var up_dir := Flight.scale(rel_r, 1.0 / Flight.norm(rel_r))
		# Taivaan kirkkaus: päivällä sininen, hämärtyy Auringon laskiessa ja ilmakehän ohetessa korkeuden mukana.
		var day := clampf((Flight.dot(sun_dir, up_dir) + 0.1) / 0.3, 0.0, 1.0)
		base.merge({"ship": {"r": L.r, "v": L.v}, "aim": "Maa", "nose": L.nose, "up": L.up, "shake": L.shake, "thrust": L.thrust,
			"sky": day * exp(-float(L.alt) / 14.0), "sky_color": null, "phase": L.phase, "alt": L.alt, "tau": L.tau,
			"screens": [
				["NOUSU" if float(L.tau) >= 0.0 else "LAUKAISUALUSTA", [[VoyageUI.pad_clock(L.tau), 36], [String(L.phase).to_upper(), 28, WARM], [Fmt.date(t), 26, MUTED]]],
				["NOPEUS", [["%s km/s" % Fmt.num(L.speed, 2), 44], ["%s km/h" % Fmt.num(float(L.speed) * 3600.0), 28, MUTED],
					["korkeus %s km" % (Fmt.num(L.alt, 1) if float(L.alt) < 10.0 else Fmt.num(L.alt)), 26, MUTED]]],
				["KIIHTYVYYS", [["%s g" % Fmt.num(L.g, 1), 44], ["polttoaine %s km/s" % Fmt.num(s.fuel, 2), 26, MUTED]], fuel_frac],
			]}, true)
		return base
	# Manuaalikaasu näkyy työntönä (hehku, ääni, tehovipu) ja pienenä tärinänä.
	if Game.manual_throttle > 0.0:
		base.thrust = maxf(float(base.thrust), Game.manual_throttle)
		base.shake = maxf(float(base.shake), Game.manual_throttle * 0.25)
	var f: Variant = s.flight
	var tr: Variant = f if f != null else s.plan
	if tr == null:
		var name: Variant = s.location
		var ship: Dictionary = Flight.parking_state(name, t, s.orbit) if name != null else Flight.departure_state(s.drift, t)
		var date := [Fmt.date(t), 28, MUTED]
		var warp := [warp_name, 28, WARM]
		var speed_rows: Array
		if name != null:
			var rel: Dictionary = ship.rel
			speed_rows = [["%s km/s" % Fmt.num(Flight.norm(rel.v), 2), 44], ["%s km/h" % Fmt.num(Flight.norm(rel.v) * 3600.0), 28, MUTED],
				["%s %s km" % [name, Fmt.num(Flight.norm(rel.r) - float(Flight.orbit_of(name).radiusKm))], 26, MUTED]]
		else:
			speed_rows = [["%s km/s" % Fmt.num(Flight.norm(ship.v), 2), 44], ["Auringon suhteen", 28, MUTED]]
		var status := ""
		if s.survey != null:
			status = "kartoitus käynnissä"
		elif name != null:
			status = "tutkittu" if s.explored.has(name) else "tutkimatta"
		# Auringon kiertoradalla nokka menosuuntaan (kartan nuoli).
		if name == null:
			base.heading = ship.v
		base.merge({"ship": ship, "aim": name, "screens": [
			["KIERTORATA" if name != null else "AURINGON KIERTORATA", [[Fmt.clock(t), 36], date, warp]],
			["NOPEUS", speed_rows],
			[String(name).to_upper() if name != null else "POLTTOAINE", [[status, 30], ["polttoaine %s km/s" % Fmt.num(s.fuel, 2), 26, MUTED]], fuel_frac],
		]}, true)
		return base
	var ship: Dictionary
	if f != null:
		ship = Flight.ship_view(tr, t)
	elif Flight.is_planet(tr.from):
		ship = Flight.parking_state(tr.from, t, s.orbit)
	else:
		ship = Flight.departure_state(tr.from, t)
	# Kun lähtöpoltto on päällä, alus on kiertoradalla nokka menosuuntaan ja katto poispäin planeetasta (body_frame).
	if f == null and tr.get("armed", false):
		base.burn_frame = true
	# Lennolla nokka osoittaa menosuuntaan kuten kartan nuoli (heading, #32). Kappaleiden lähellä asennon määrää rata
	# (body_frame): lähtiessä planeetta jää hiljalleen alle ja taakse, ohittaessa ja saapuessa se on alla.
	# aim on näyttöjen kohde (kohdekamera, tutka).
	if f != null:
		base.heading = Flight.heading_velocity(f, t)
	var aim: String = tr.to
	if f != null:
		var fb: Variant = tr.get("flyby")
		if fb is Dictionary and t < float(fb.t):
			aim = fb.body
	elif Flight.is_planet(tr.from):
		aim = tr.from
	var ro := _readouts(t)
	base.merge({"ship": ship, "aim": aim, "screens": [
		["LENTOAIKA" if f != null else ("LÄHTÖPOLTTO" if tr.get("armed", false) else "LAUKAISUIKKUNA"), [[ro.met, 36], [Fmt.date(t), 28, MUTED], [warp_name, 28, WARM]]],
		["NOPEUS", [["%s km/s" % Fmt.num(ro.speed, 2), 44], ["%s km/h" % Fmt.num(float(ro.speed) * 3600.0), 28, MUTED],
			["%s %s km/s" % [ro.near.name, Fmt.num(ro.near.speed, 2)] if f != null else "pysäköintirata", 26, MUTED]]],
		["KOHDE: %s" % String(tr.to).to_upper(), [[ro.dist, 34], ["polttoaine %s km/s" % Fmt.num(s.fuel, 2), 26, MUTED]], fuel_frac],
	]}, true)
	return base


# Lennon mittarit (sama kuin paneelissa).
static func _readouts(t: float) -> Dictionary:
	var s: Dictionary = Game.state
	var f: Variant = s.flight
	var tr: Dictionary = f if f != null else s.plan
	var ship: Dictionary = Flight.ship_state(f, t) if f != null else Flight.departure_state(tr.from, t)
	var local: bool = f != null and f.get("local", false)
	var speed := Flight.norm(ship.rel.v) if local else Flight.norm(ship.v)
	var near: Dictionary
	if local:
		near = {"name": f.parent, "speed": Flight.norm(ship.rel.v)}
	elif f != null or not Flight.is_planet(tr.from):
		near = Flight.nearest_planet(ship.r, ship.v, t)
	else:
		near = {"name": tr.from, "speed": 0.0}
	return {"met": "T+ %s" % Flight.fmt_duration(t - float(f.depart)) if f != null else "T− %s" % Flight.fmt_duration(float(tr.depart) - t),
		"speed": speed, "near": near, "dist": Fmt.km(Flight.surface_distance(_view_r(f, ship, t), tr.to, t))}


## Aluksen paikka näkymässä (lennolla saapumis- ja lähtöhyperbelit, #41): etäisyydet lasketaan tästä, jotta
## lukema vastaa ikkunasta näkyvää ja on perillä pysäköintiradan korkeus.
static func _view_r(f: Variant, ship: Dictionary, t: float) -> PackedFloat64Array:
	return Flight.ship_view(f, t).r if f != null else ship.r


## Asento kappaleen lähellä kuten lentokoneella (follow_velocity: lennolla nokka seuraa nopeutta myös lähestyessä): nokka menosuuntaan ja katto poispäin kappaleesta, ja kappale näkyy
## kaarevana aluksen alla. rel_r ja rel_v: aluksen paikka (km) ja nopeus kappaleen suhteen, ekliptikan koordinaatit.
## Ratatasossa e1 osoittaa kappaleen keskipisteeseen ja e2 menosuuntaan (ratanopeuden suunta). Nokka on kulmassa φ
## e1:stä e2:een päin, katto kohtisuorassa poispäin kappaleesta, ja kappaleen keskipiste näkyy korkeudella c = −φ.
## Matalalla radalla (kulmasäde ρ suuri) horisontti on ikkunan alaosassa; kaukana kappaleen keskipiste on ikkunan
## keskellä. Etääntyessä (lähtö) nokka seuraa nopeutta, ja kappale jää hiljalleen alle ja taakse.
## Palauttaa {nose, up, weight}: weight 0–1 kertoo, kuinka paljon asento seuraa rataa kohteeseen osoittamisen sijaan.
static func body_frame(rel_r: PackedFloat64Array, rel_v: PackedFloat64Array, radius_km: float, follow_velocity: bool = false) -> Dictionary:
	var dist := Flight.norm(rel_r)
	var rho := asin(clampf(radius_km / dist, 0.0, 1.0))
	var r_hat := Flight.scale(rel_r, 1.0 / dist)
	var e1 := Flight.scale(r_hat, -1.0)
	var n := Flight.cross(rel_r, rel_v)
	if Flight.norm(n) < 1e-9 * dist * maxf(Flight.norm(rel_v), 1e-9):
		n = Flight.vec(0.0, 0.0, 1.0)
	var e2 := Flight.cross(n, r_hat)
	if Flight.norm(e2) < 1e-12:
		e2 = Flight.cross(Flight.vec(0.0, 0.0, 1.0), r_hat) if absf(r_hat[2]) < 0.99 else Flight.vec(1.0, 0.0, 0.0)
	e2 = Flight.scale(e2, 1.0 / Flight.norm(e2))
	var alpha := atan2(Flight.dot(rel_v, e2), Flight.dot(rel_v, e1)) if Flight.norm(rel_v) > 1e-9 else PI / 2.0
	# Keskipisteen korkeus näkymässä: kaukana ikkunan keskellä, lähellä niin, että yläreuna (horisontti) on ikkunan alaosassa.
	var c := lerpf(AIM_RAISE, HORIZON_RAISE - rho, smoothstep(10.0 * DEG, 40.0 * DEG, rho))
	var phi := -c
	# Etääntyessä nokka seuraa nopeutta hieman alaspäin kallistettuna; kallistus häviää kappaleen pienentyessä. Lähellä
	# horisontti pysyy ikkunassa, ja kappale vajoaa alle vasta, kun se on pienentynyt (kulmasäde alle 30°).
	var pitch_down := clampf(PI / 2.0 + c, 0.0, 25.0 * DEG) * smoothstep(0.0, 20.0 * DEG, rho)
	var leaving := minf(alpha - pitch_down, rho - HORIZON_RAISE + (1.0 - smoothstep(5.0 * DEG, 30.0 * DEG, rho)) * PI)
	phi = lerpf(phi, maxf(phi, leaving), smoothstep(PI / 2.0, PI / 2.0 + 20.0 * DEG, alpha))
	# Lennolla (follow_velocity) myös lähestyttäessä nokka seuraa nopeutta kappaleen suhteen: kappale on alla ja
	# horisontti nousee ikkunaan vasta ohitettaessa (perikeskuksessa sama asento kuin kiertoradalla).
	if follow_velocity and alpha < PI / 2.0:
		phi = alpha - pitch_down
	var nose := Flight.add(Flight.scale(e1, cos(phi)), Flight.scale(e2, sin(phi)))
	var up := Flight.add(Flight.scale(e1, -sin(phi)), Flight.scale(e2, cos(phi)))
	return {"nose": nose, "up": up, "weight": smoothstep(3.0 * DEG, 20.0 * DEG, rho), "rho": rho}
