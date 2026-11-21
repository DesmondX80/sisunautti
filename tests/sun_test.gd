extends TestCase
## Aurinko oikeassa paikassa ja oikean kirkkaana (Space, Flight._pad_angle) ilman ikkunaa:
## - Maan pyöriminen (IAU): Auringon alapiste (pituus ja leveys) vastaa NOAA:n aurinkokaavoja eri vuodenaikoina
## - laukaisualustan aurinkoaika on Kouroun aurinkoaika
## - planeettojen nollameridiaanit pyörivät oikeaan suuntaan oikealla jaksolla
## - Aurinko piirtyy suuntaan, jossa se aluksesta katsottuna on, ja kiekon kulmakoko on oikea
## - häikäisy ja valo pienenevät etäisyyden mukaan, pimennyksessä häikäisy sammuu
##   godot --headless -- --suntest

const DAY := 86400000.0


func _ready() -> void:
	_subsolar()
	_pad_time()
	_rotation()
	await _render()
	finish()


## Päivän numero (1 = 1.1.) ja UTC-tunti hetkestä t (ms).
func _doy_hour(t: float) -> Array:
	var d := Time.get_datetime_dict_from_unix_time(int(t / 1000.0))
	var start := Time.get_unix_time_from_datetime_dict({"year": d.year, "month": 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	var doy := int((t / 1000.0 - start) / 86400.0) + 1
	return [doy, d.hour + d.minute / 60.0 + d.second / 3600.0]


## NOAA: aurinkoajan yhtälö (min) ja deklinaatio (rad).
func _noaa(t: float) -> Array:
	var dh := _doy_hour(t)
	var g := TAU / 365.0 * (float(dh[0]) - 1.0 + (float(dh[1]) - 12.0) / 24.0)
	var eqt := 229.18 * (0.000075 + 0.001868 * cos(g) - 0.032077 * sin(g) - 0.014615 * cos(2.0 * g) - 0.040849 * sin(2.0 * g))
	var decl := 0.006918 - 0.399912 * cos(g) + 0.070257 * sin(g) - 0.006758 * cos(2.0 * g) + 0.000907 * sin(2.0 * g) \
		- 0.002697 * cos(3.0 * g) + 0.00148 * sin(3.0 * g)
	return [eqt, decl, float(dh[1])]


func _angle_diff(a: float, b: float) -> float:
	return absf(wrapf(a - b, -180.0, 180.0))


func _subsolar() -> void:
	for iso: String in ["2026-03-20T12:00:00", "2026-06-21T06:00:00", "2026-11-14T12:00:00", "2026-12-21T18:30:00", "2031-08-02T03:15:00"]:
		var t := Time.get_unix_time_from_datetime_string(iso) * 1000.0
		var earth: PackedFloat64Array = Flight.planet_state("Maa", t).r
		var s := Space.to_scene(Flight.scale(earth, -1.0)).normalized()
		var pole := Space.to_scene(Space.equatorial(0.0, 90.0)).normalized()
		var m := Space.prime_meridian("Maa", t)
		var east := pole.cross(m)
		var lon := rad_to_deg(atan2(s.dot(east), s.dot(m)))
		var lat := rad_to_deg(asin(s.dot(pole)))
		var n := _noaa(t)
		var want_lon := -15.0 * (float(n[2]) - 12.0 + float(n[0]) / 60.0)
		var want_lat := rad_to_deg(float(n[1]))
		check("Auringon alapiste %s: %s° %s° (NOAA %s° %s°)" % [iso, Fmt.num(lon, 1), Fmt.num(lat, 1), Fmt.num(want_lon, 1), Fmt.num(want_lat, 1)],
			_angle_diff(lon, want_lon) < 1.0 and absf(lat - want_lat) < 0.5)
		check("nollameridiaani päiväntasaajalla " + iso, absf(m.dot(pole)) < 1e-6)


func _pad_time() -> void:
	for iso: String in ["2026-11-14T00:00:00", "2026-11-14T15:00:00", "2027-06-21T09:00:00", "2027-03-01T21:40:00"]:
		var t := Time.get_unix_time_from_datetime_string(iso) * 1000.0
		var pad: PackedFloat64Array = Flight.launch_state(null, t).rel.r
		var earth: PackedFloat64Array = Flight.planet_state("Maa", t).r
		var sun := Flight.scale(earth, -1.0)
		var h := rad_to_deg(atan2(sun[0] * pad[1] - sun[1] * pad[0], sun[0] * pad[0] + sun[1] * pad[1]))
		var local_h := fposmod(12.0 + h / 15.0, 24.0)
		var n := _noaa(t)
		var want := fposmod(float(n[2]) - 52.77 / 15.0 + float(n[0]) / 60.0, 24.0)
		var diff := absf(wrapf(local_h - want, -12.0, 12.0)) * 60.0
		check("alustan aurinkoaika %s: %s (Kourou %s, ero %d min)" % [iso, Fmt.num(local_h, 2), Fmt.num(want, 2), roundi(diff)], diff < 2.0)


func _rotation() -> void:
	var t := Time.get_unix_time_from_datetime_string("2026-11-14T00:00:00") * 1000.0
	for c: Array in [["Maa", 23.9345], ["Mars", 24.6229], ["Jupiter", 9.925], ["Venus", -5832.6]]:
		var period_h: float = c[1]
		var dt := absf(period_h) * 3600000.0
		var a := Space.spin_angle_for(c[0], t)
		var quarter := Space.spin_angle_for(c[0], t + dt / 4.0)
		var full := Space.spin_angle_for(c[0], t + dt)
		var turn := wrapf(quarter - a, -PI, PI)
		check("%s pyörii %s, kierros %s h" % [c[0], "takaperin" if period_h < 0.0 else "eteenpäin", Fmt.num(absf(period_h), 2)],
			absf(absf(turn) - PI / 2.0) < 0.01 and signf(turn) == signf(period_h) and absf(wrapf(full - a, -PI, PI)) < 0.01)


## Space ruudussa: Auringon suunta, kulmakoko ja häikäisy eri etäisyyksiltä sekä pimennys.
func _render() -> void:
	var space := Space.new()
	add_child(space)
	await get_tree().process_frame
	var t := Time.get_unix_time_from_datetime_string("2026-11-14T00:00:00") * 1000.0
	var last_glow := INF
	var last_light := INF
	for c: Array in [["Venus", 0.0], ["Maa", 0.0], ["Jupiter", 0.0], ["Neptunus", 0.0]]:
		var pr: PackedFloat64Array = Flight.planet_state(c[0], t).r
		var ship := Flight.add(pr, Flight.scale(Flight.cross(pr, PackedFloat64Array([0, 0, 1])), 0.02))
		space.update(ship, t, 1000.0)
		var want := Space.to_scene(Flight.scale(ship, -1.0)).normalized()
		var d_km := Flight.norm(ship)
		var ang := space.sun_root.position.angle_to(want)
		var size := asin(space.sun_mesh.scale.x / space.sun_root.position.length())
		check("%s: Aurinko oikeassa suunnassa (%s″) ja kulmasäde %s′" % [c[0], Fmt.num(rad_to_deg(ang) * 3600.0, 2),
			Fmt.num(rad_to_deg(size) * 60.0, 2)], ang < 1e-6 and absf(size - asin(Planets.SUN_RADIUS_KM / d_km)) < 1e-6)
		var glow := space.sun_glow.scale.x / space.sun_root.position.length()
		var light := Space.light_factor(space.sun_distance)
		check("%s: häikäisy (%s) ja valo (%s) pienenevät etäisyyden mukaan" % [c[0], Fmt.num(glow, 4), Fmt.num(light, 2)],
			glow < last_glow and light < last_light and space.sunlit > 0.99)
		last_glow = glow
		last_light = light
	# Pimennys: alus Maan takana sen varjossa.
	var e: PackedFloat64Array = Flight.planet_state("Maa", t).r
	space.update(Flight.add(e, Flight.scale(e, 7000.0 / Flight.norm(e))), t, 1000.0)
	var gm := space.sun_glow.material_override as ShaderMaterial
	check("Maan varjossa Aurinko pimennyksissä ja häikäisy sammuu", space.sunlit == 0.0 and float(gm.get_shader_parameter("visible")) == 0.0)
	space.queue_free()
