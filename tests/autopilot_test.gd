extends TestCase
## Korkeudenvakain (#58): suljetun silmukan lento Flight.fly_air-mallilla eri kappaleilla, nokka vakaimen mukaan ja
## työntö nokan suuntaan. 10 %:n kaasu (1 g) riittää ilmakehässä vaakalentoon.
##   godot --headless -- --autopilottest

const THROTTLE_10 := 0.1 * 0.098


func _ready() -> void:
	for c: Array in [
		# kappale, alkukorkeus, tavoite, vaakanopeus (km/s), työntö (km/s²)
		["Maa", 10.0, 10.0, 0.25, THROTTLE_10],
		["Maa", 10.0, 12.0, 0.25, THROTTLE_10],
		["Maa", 30.0, 25.0, 1.2, THROTTLE_10],
		["Mars", 8.0, 8.0, 0.4, THROTTLE_10],
		["Venus", 60.0, 60.0, 0.3, THROTTLE_10],
		["Titan", 20.0, 20.0, 0.15, THROTTLE_10],
		["Jupiter", 100.0, 100.0, 0.6, THROTTLE_10 * 3.0],
		["Kuu", 10.0, 10.0, 0.5, THROTTLE_10],
	]:
		var res := fly(c[0], c[1], c[2], c[3], c[4], 240.0)
		check("%s: %s km → %s km, ero %s km, nopeus %s km/s" % [c[0], Fmt.num(c[1]), Fmt.num(c[2]), Fmt.num(res.err, 2),
			Fmt.num(res.speed, 2)], not res.hit and absf(res.err) < 0.3 and res.speed > 0.05)
	var free := fly("Maa", 10.0, 10.0, 0.25, THROTTLE_10, 60.0, false)
	check("ilman vakainta (nokka menosuuntaan) alus vajoaa", free.hit or free.err > 1.0)
	var turn := fly("Maa", 10.0, 10.0, 0.25, THROTTLE_10, 60.0, true, 1.0)
	check("vakain päällä kääntö kaartaa lentorataa (%d°) korkeuden pysyessä" % roundi(turn.turned),
		turn.turned > 20.0 and absf(turn.err) < 0.5)
	check("vaakalennossa nokka hieman menosuunnan yläpuolella",
		_alpha_level("Maa", 10.0, 0.25) > 0.0 and _alpha_level("Maa", 10.0, 0.25) < 0.3)
	finish()


## Lento duration_s sekuntia: palauttaa {err: korkeus − tavoite (km), speed, hit, turned: menosuunnan muutos (°)}.
func fly(name: String, alt: float, target: float, speed: float, thrust: float, duration_s: float, hold: bool = true,
		turn: float = 0.0) -> Dictionary:
	var radius: float = Flight.orbit_of(name).radiusKm
	var r := PackedFloat64Array([radius + alt, 0.0, 0.0])
	var v := PackedFloat64Array([0.0, speed, 0.0])
	var v0 := v
	var dt := 0.1
	var t := 0.0
	while t < duration_s:
		var n: PackedFloat64Array = Autopilot.nose(name, r, v, target, thrust, turn) if hold else Flight.scale(v, 1.0 / Flight.norm(v))
		v = Flight.add(v, Flight.scale(n, thrust * dt))
		var f := Flight.fly_air(name, r, v, n, dt)
		r = f.r
		v = f.v
		if f.hit:
			return {"err": -alt, "speed": Flight.norm(v), "hit": true, "turned": 0.0}
		t += dt
	var up := Flight.scale(r, 1.0 / Flight.norm(r))
	var vh := Flight.sub(v, Flight.scale(up, Flight.dot(v, up)))
	var c := clampf(Flight.dot(vh, v0) / (Flight.norm(vh) * Flight.norm(v0)), -1.0, 1.0)
	return {"err": Flight.norm(r) - radius - target, "speed": Flight.norm(v), "hit": false, "turned": rad_to_deg(acos(c))}


func _alpha_level(name: String, alt: float, speed: float) -> float:
	var radius: float = Flight.orbit_of(name).radiusKm
	var r := PackedFloat64Array([radius + alt, 0.0, 0.0])
	var v := PackedFloat64Array([0.0, speed, 0.0])
	var n := Autopilot.nose(name, r, v, alt, THROTTLE_10)
	return n[0]
