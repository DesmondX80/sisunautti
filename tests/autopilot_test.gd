extends TestCase
## Korkeudenvakain (#58): suljetun silmukan lento Flight.fly_air-mallilla eri kappaleilla kuten ohjaamossa: nokka
## kääntyy vakaimen suuntaan enintään 0,6 rad/s, työntö nokan suuntaan vain linjassa (Autopilot.alignment) ja
## nopeuden muutos radalle puolen sekunnin sysäyksinä. 10 %:n kaasu (1 g) riittää ilmakehässä vaakalentoon, ja
## kiertoradalta vakain laskeutuu tavoitekorkeuteen automaattikaasulla.
##   godot --headless -- --autopilottest

const ACCEL := 0.098
const THROTTLE_10 := 0.1 * ACCEL
const RATE := 0.6


func _ready() -> void:
	for c: Array in [
		# kappale, alkukorkeus, tavoite, vaakanopeus (km/s; 0 = ympyräradan nopeus), pelaajan työntö (km/s²), kesto (s)
		["Maa", 10.0, 10.0, 0.25, THROTTLE_10, 240.0],
		["Maa", 10.0, 12.0, 0.25, THROTTLE_10, 240.0],
		["Maa", 30.0, 25.0, 1.2, THROTTLE_10, 240.0],
		["Maa", 10.0, 10.0, 0.25, 0.0, 240.0],
		["Mars", 8.0, 8.0, 0.4, THROTTLE_10, 240.0],
		["Venus", 60.0, 60.0, 0.3, THROTTLE_10, 240.0],
		["Titan", 20.0, 20.0, 0.15, THROTTLE_10, 240.0],
		["Jupiter", 100.0, 100.0, 0.6, THROTTLE_10 * 3.0, 240.0],
		["Kuu", 10.0, 10.0, 0.5, THROTTLE_10, 240.0],
		# Kiertoradalta alas ilman kaasua (palaute: 200 km → 30 km keikkui ylös ja alas).
		["Maa", 200.0, 30.0, 0.0, 0.0, 1500.0],
		["Mars", 150.0, 10.0, 0.0, 0.0, 1500.0],
		["Kuu", 100.0, 10.0, 0.0, 0.0, 1500.0],
		["Maa", 30.0, 150.0, 0.0, 0.0, 1500.0],
	]:
		var res := fly(c[0], c[1], c[2], c[3], c[4], c[5])
		check("%s: %s km → %s km, ero %s km, pystynopeus %s m/s, suunnanvaihtoja %d, polttoaine %s km/s" % [c[0], Fmt.num(c[1]),
			Fmt.num(c[2]), Fmt.num(res.err, 2), Fmt.num(res.vs * 1000.0, 1), res.flips, Fmt.num(res.fuel, 2)],
			not res.hit and absf(res.err) < 0.3 and absf(res.vs) < 0.02 and res.flips <= 4)
	var free := fly("Maa", 10.0, 10.0, 0.25, THROTTLE_10, 60.0, false)
	check("ilman vakainta (nokka menosuuntaan) alus vajoaa", free.hit or free.err < -1.0)
	var turn := fly("Maa", 10.0, 10.0, 0.25, THROTTLE_10, 60.0, true, 1.0)
	check("vakain päällä kallistus kaartaa lentorataa vasemmalle (%d°) korkeuden pysyessä" % roundi(turn.turned),
		turn.turned > 20.0 and turn.left and absf(turn.err) < 0.5)
	check("vaakalennossa nokka hieman menosuunnan yläpuolella",
		_alpha_level("Maa", 10.0, 0.25) > 0.0 and _alpha_level("Maa", 10.0, 0.25) < 0.3)
	var orbit_r := PackedFloat64Array([6371.0 + 200.0, 0.0, 0.0])
	var orbit_v := PackedFloat64Array([0.0, sqrt(398600.4 / 6571.0), 0.0])
	var c0 := Autopilot.control("Maa", orbit_r, orbit_v, 30.0, 0.0, ACCEL)
	check("avaruudessa vakain osoittaa alas ja käyttää automaattikaasua", c0.auto and not c0.air and c0.nose[0] < -0.99
		and float(c0.thrust) > 0.0)
	check("kääntyessä ei polteta väärään suuntaan", Autopilot.alignment(PackedFloat64Array([1, 0, 0]), PackedFloat64Array([0, 1, 0])) == 0.0
		and Autopilot.alignment(PackedFloat64Array([1, 0, 0]), PackedFloat64Array([1, 0, 0])) == 1.0)
	check("pystynopeuden tavoite: lähellä suora, kaukana jarrutusprofiili", absf(Autopilot.vs_command(0.5, 1.0) - 0.05) < 1e-9
		and absf(Autopilot.vs_command(-100.0, 1.0) + sqrt(2.0 * Autopilot.BRAKE * 100.0)) < 1e-9 and Autopilot.vs_command(1e5, 1.0) == 1.0)
	finish()


## Lento duration_s sekuntia: {err: korkeus − tavoite (km), vs, speed, hit, turned: menosuunnan muutos (°),
## flips: pystytyönnön suunnanvaihdot, fuel: poltettu Δv}.
func fly(name: String, alt: float, target: float, speed: float, thrust: float, duration_s: float, hold: bool = true,
		turn: float = 0.0) -> Dictionary:
	var o := Flight.orbit_of(name)
	var radius: float = o.radiusKm
	var r := PackedFloat64Array([radius + alt, 0.0, 0.0])
	var v := PackedFloat64Array([0.0, speed if speed > 0.0 else sqrt(float(o.mu) / (radius + alt)), 0.0])
	var v0 := v
	var dt := 0.1
	var t := 0.0
	var nose_v := Flight.scale(v, 1.0 / Flight.norm(v))
	var sign := 1
	var flips := 0
	var roof := PackedFloat64Array()
	var pending := PackedFloat64Array([0.0, 0.0, 0.0])
	var pending_t := 0.0
	var fuel := 0.0
	while t < duration_s:
		var want := nose_v
		var power := thrust
		if hold:
			var c := Autopilot.control(name, r, v, target, thrust, ACCEL, turn, sign)
			if int(c.sign) != sign:
				flips += 1
			sign = c.sign
			want = c.nose
			nose_v = _rotate_toward(nose_v, want, RATE * dt)
			# Katto vakaimen mukaan, kohtisuoraan todellista nokkaa vastaan.
			var cr: PackedFloat64Array = c.roof
			roof = PackedFloat64Array()
			if cr.size() == 3:
				roof = Flight.sub(cr, Flight.scale(nose_v, Flight.dot(cr, nose_v)))
			power = float(c.thrust) * Autopilot.alignment(nose_v, want)
		else:
			nose_v = Flight.scale(v, 1.0 / Flight.norm(v))
		pending = Flight.add(pending, Flight.scale(nose_v, power * dt))
		fuel += power * dt
		pending_t += dt
		if pending_t >= 0.5:
			v = Flight.add(v, pending)
			pending = PackedFloat64Array([0.0, 0.0, 0.0])
			pending_t = 0.0
		var f := Flight.fly_air(name, r, v, nose_v, dt, roof)
		r = f.r
		v = f.v
		if f.hit:
			return {"err": -alt, "vs": 0.0, "speed": Flight.norm(v), "hit": true, "turned": 0.0, "flips": flips, "fuel": fuel}
		t += dt
	var up := Flight.scale(r, 1.0 / Flight.norm(r))
	var vh := Flight.sub(v, Flight.scale(up, Flight.dot(v, up)))
	var cs := clampf(Flight.dot(vh, v0) / (Flight.norm(vh) * Flight.norm(v0)), -1.0, 1.0)
	return {"err": Flight.norm(r) - radius - target, "vs": Flight.dot(v, up), "speed": Flight.norm(v), "hit": false,
		"turned": rad_to_deg(acos(cs)), "left": Flight.dot(Flight.cross(v0, vh), up) > 0.0, "flips": flips, "fuel": fuel}


## Yksikkövektori a käännettynä kohti b:tä enintään kulman max_angle (rad).
func _rotate_toward(a: PackedFloat64Array, b: PackedFloat64Array, max_angle: float) -> PackedFloat64Array:
	var c := clampf(Flight.dot(a, b), -1.0, 1.0)
	var ang := acos(c)
	if ang <= max_angle:
		return b
	var perp := Flight.sub(b, Flight.scale(a, c))
	if Flight.norm(perp) < 1e-9:
		perp = Flight.cross(a, PackedFloat64Array([0.0, 0.0, 1.0]))
	perp = Flight.scale(perp, 1.0 / Flight.norm(perp))
	return Flight.add(Flight.scale(a, cos(max_angle)), Flight.scale(perp, sin(max_angle)))


func _alpha_level(name: String, alt: float, speed: float) -> float:
	var radius: float = Flight.orbit_of(name).radiusKm
	var r := PackedFloat64Array([radius + alt, 0.0, 0.0])
	var v := PackedFloat64Array([0.0, speed, 0.0])
	var n := Autopilot.nose(name, r, v, alt, THROTTLE_10)
	return n[0]
