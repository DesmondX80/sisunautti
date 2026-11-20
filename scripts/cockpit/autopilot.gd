class_name Autopilot
## Korkeudenvakain (#58): pitää aluksen lukitussa korkeudessa. Korkeuden erosta lasketaan tavoiteltu pystynopeus
## (lähellä suoraan verrannollinen, kaukana jarrutusprofiili) ja siitä pystykiihtyvyys (kriittisesti vaimennettu).
## - Ilmakehässä (dynaaminen paine vähintään Q_AIR) nokka käännetään pystytasossa: kohtauskulma haetaan puolitushaulla
##   niin, että painovoima, nostovoima, ilmanvastus ja nokan suuntainen työntö antavat juuri sen pystykiihtyvyyden.
##   Jos pelaajan kaasu ei riitä nousuun, automaattikaasu lisää työntöä.
## - Avaruudessa ja ohuessa yläilmakehässä nostovoimaa ei ole: nokka pysyy vaakatasossa menosuuntaan siivet vaakana
##   kuten lentokoneella, ja ohjausraketit antavat tarvittavan pystytyönnön ylös tai alas (automaattikaasu). Pelaajan
##   kaasu polttaa nokan suuntaan. Pystytyönnön suunta vaihtuu vasta selvällä marginaalilla (SIGN_BAND).

## Pystynopeuden vahvistus korkeuden erosta (1/s), jarrutusprofiilin hidastuvuus (km/s²) ja suurin tavoiteltu
## pystynopeus (km/s) avaruudessa ja ilmakehässä.
const ALT_GAIN := 0.1
const BRAKE := 0.0049
const VS_LIMIT := 1.0
const VS_LIMIT_AIR := 0.15
## Pystykiihtyvyyden vahvistus pystynopeuden erosta (1/s) ja suurin pystykiihtyvyys (km/s², 2 g).
const VS_GAIN := 0.4
const ACCEL_MAX := 0.0196
## Kohtauskulman rajat (rad): −20° … 35°.
const ALPHA_MIN := -0.35
const ALPHA_MAX := 0.61
## Suurin kallistus (rad, 35°) kaarrettaessa vakaimen ollessa päällä.
const BANK_MAX := 0.61
## Dynaaminen paine (Pa), jota ohuemmassa ilmassa ohjataan pystytyönnöllä.
const Q_AIR := 2000.0
## Pystytyönnön suunnan vaihdon marginaali (km/s², 0,2 g).
const SIGN_BAND := 0.002


## Tavoiteltu pystynopeus (km/s) korkeuden erosta err (km): lähellä err·ALT_GAIN, kaukana √(2·BRAKE·|err|), enintään limit.
static func vs_command(err: float, limit: float) -> float:
	var a := absf(err)
	return signf(err) * minf(minf(a * ALT_GAIN, sqrt(2.0 * BRAKE * a)), limit)


## Ohjaus kappaleen name ympärillä tilassa (r, v) (km, km/s kappaleen suhteen), kun tavoitekorkeus on target_km
## pinnasta, pelaajan kaasun työntö thrust ja suurin työntö thrust_max (km/s²). turn −1…1 kallistaa ilmakehässä
## alusta (vasemmalle +) koordinoituun kaartoon: nostovoima kääntyy sivulle ja kaartaa lentorataa, ja kohtauskulmaa
## kasvatetaan niin, että korkeus pysyy. prev_sign on edellisen pystytyönnön suunta.
## Palauttaa {nose: nokan suunta (ekliptika), roof: katon suunta, thrust: työntö (km/s²), dir: työnnön suunta
## (ilmakehässä nokka, avaruudessa nokan suuntaisen kaasun ja pystytyönnön summa), sign, auto: automaattikaasu
## käytössä, air}.
static func control(name: String, r: PackedFloat64Array, v: PackedFloat64Array, target_km: float, thrust: float,
		thrust_max: float, turn: float = 0.0, prev_sign: int = 1) -> Dictionary:
	var rn := Flight.norm(r)
	var up := Flight.scale(r, 1.0 / rn)
	var vs := Flight.dot(v, up)
	var alt := rn - float(Flight.orbit_of(name).radiusKm)
	var plain := Flight.aero(name, r, v, PackedFloat64Array())
	var air := float(plain.q) >= Q_AIR
	var vs_cmd := vs_command(target_km - alt, VS_LIMIT_AIR if air else VS_LIMIT)
	var a_cmd := clampf((vs_cmd - vs) * VS_GAIN, -ACCEL_MAX, ACCEL_MAX)
	var mu: float = Flight.orbit_of(name).mu
	var g := Flight.scale(up, -mu / (rn * rn))
	# Pystynopeuden muutos: kiihtyvyyden pystykomponentti + vaakanopeuden keskeisliike (v_h² / r).
	var vh2 := Flight.dot(v, v) - vs * vs
	if not air:
		var base := Flight.dot(Flight.add(g, plain.a), up) + vh2 / rn
		var need := a_cmd - base
		var sign := prev_sign if prev_sign != 0 else 1
		if sign > 0 and need < -SIGN_BAND:
			sign = -1
		elif sign < 0 and need > SIGN_BAND:
			sign = 1
		# Nokka vaakatasossa menosuuntaan (pelkkä vaakasuunta, jotta pystynopeus ei kallista nokkaa).
		var fwd: PackedFloat64Array = frame(up, Flight.sub(v, Flight.scale(up, vs))).vhat
		var main := minf(thrust, thrust_max)
		var vert := clampf(need * float(sign), 0.0, sqrt(maxf(thrust_max * thrust_max - main * main, 0.0)))
		var vec := Flight.add(Flight.scale(fwd, main), Flight.scale(up, vert * float(sign)))
		var mag := Flight.norm(vec)
		return {"nose": fwd, "roof": up, "thrust": mag, "dir": Flight.scale(vec, 1.0 / mag) if mag > 1e-12 else fwd,
			"sign": sign, "auto": vert > 0.0, "air": false}
	var fr := frame(up, v)
	var vhat: PackedFloat64Array = fr.vhat
	var p: PackedFloat64Array = fr.p
	var side := Flight.cross(up, vhat)
	side = Flight.scale(side, 1.0 / maxf(Flight.norm(side), 1e-9))
	# Kallistus kääntää siipien tason (nokan ja katon taso) menosuunnan ympäri.
	var bank := clampf(turn, -1.0, 1.0) * BANK_MAX
	var pb := Flight.add(Flight.scale(p, cos(bank)), Flight.scale(side, sin(bank)))
	var accel_up := func(alpha: float, t: float) -> float:
		var n := _dir(vhat, pb, alpha)
		var a := Flight.add(g, Flight.add(Flight.aero(name, r, v, n, _roof(vhat, pb, alpha)).a, Flight.scale(n, t)))
		return Flight.dot(a, up) + vh2 / rn - a_cmd
	var out := {"thrust": thrust, "sign": 1, "auto": false, "air": true}
	if float(accel_up.call(ALPHA_MAX, thrust)) < 0.0:
		# Nousuun ei riitä nostovoima pelaajan kaasulla: automaattikaasu lisää työntöä.
		var lo_t := thrust
		var hi_t := maxf(thrust, thrust_max)
		if float(accel_up.call(ALPHA_MAX, hi_t)) > 0.0:
			for i in 20:
				var mid := (lo_t + hi_t) / 2.0
				if float(accel_up.call(ALPHA_MAX, mid)) > 0.0:
					hi_t = mid
				else:
					lo_t = mid
		out.thrust = hi_t
		out.auto = hi_t > thrust + 1e-9
		out.nose = _dir(vhat, pb, ALPHA_MAX)
		out.roof = _roof(vhat, pb, ALPHA_MAX)
		out.dir = out.nose
		return out
	if float(accel_up.call(ALPHA_MIN, thrust)) > 0.0:
		out.nose = _dir(vhat, pb, ALPHA_MIN)
		out.roof = _roof(vhat, pb, ALPHA_MIN)
		out.dir = out.nose
		return out
	var lo := ALPHA_MIN
	var hi := ALPHA_MAX
	for i in 24:
		var mid := (lo + hi) / 2.0
		if float(accel_up.call(mid, thrust)) > 0.0:
			hi = mid
		else:
			lo = mid
	out.nose = _dir(vhat, pb, (lo + hi) / 2.0)
	out.roof = _roof(vhat, pb, (lo + hi) / 2.0)
	out.dir = out.nose
	return out


## Pelkkä nokan suunta (ks. control) pelaajan kaasulla thrust.
static func nose(name: String, r: PackedFloat64Array, v: PackedFloat64Array, target_km: float, thrust: float,
		turn: float = 0.0) -> PackedFloat64Array:
	return control(name, r, v, target_km, thrust, thrust, turn).nose


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


static func _dir(vhat: PackedFloat64Array, p: PackedFloat64Array, alpha: float) -> PackedFloat64Array:
	return Flight.add(Flight.scale(vhat, cos(alpha)), Flight.scale(p, sin(alpha)))


static func _roof(vhat: PackedFloat64Array, p: PackedFloat64Array, alpha: float) -> PackedFloat64Array:
	return Flight.add(Flight.scale(vhat, -sin(alpha)), Flight.scale(p, cos(alpha)))


## Työnnön osuus, kun aluksen nokka actual ei vielä osoita vakaimen suuntaan want: täysi linjassa, ei lainkaan yli
## 60°:n kulmassa (alus ei polta väärään suuntaan kääntyessään).
static func alignment(actual: PackedFloat64Array, want: PackedFloat64Array) -> float:
	var c := Flight.dot(actual, want) / maxf(Flight.norm(actual) * Flight.norm(want), 1e-12)
	return clampf((c - 0.5) / 0.5, 0.0, 1.0) ** 2
