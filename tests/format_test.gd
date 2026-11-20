extends TestCase
## Suomenkielinen muotoilu (Fmt): luvut kuten JS:n toLocaleString('fi-FI') (vertailuarvot Node.js:stä), Δv,
## vuorokaudet, etäisyydet, valon kulkuaika ja nimien taivutukset.
##   godot --headless -- --formattest

const S := " "


func _ready() -> void:
	for c: Array in [[1234567.891, 2, "1%s234%s567,89" % [S, S]], [3.6, 2, "3,6"], [-5.0, 0, "−5"], [0.005, 2, "0,01"],
			[12.5, 0, "13"], [999.999, 2, "1%s000" % S], [0.1, 1, "0,1"], [149597870.7, 0, "149%s597%s871" % [S, S]], [1000.0, 0, "1%s000" % S]]:
		check("num(%s, %d) = %s" % [c[0], c[1], c[2]], Fmt.num(c[0], c[1]) == c[2])
	check("Δv", Fmt.dv(3.7512) == "3,75 km/s")
	check("vuorokaudet", Fmt.days(258.6) == "259 vrk" and Fmt.days(800.0) == "2 v 70 vrk")
	check("kilometrit", Fmt.km(5000.4) == "5%s000 km" % S and Fmt.km(2.5e6) == "2,5 milj. km")
	check("suuret etäisyydet AU:na", Fmt.km(Planets.AU_KM) == "150 milj. km (1 AU)")
	check("valon kulkuaika", Fmt.light_time(Planets.AU_KM) == "8,3 min" and Fmt.light_time(3e5) == "1 s")
	check("lyhyt kesto", Fmt.short_duration(510000.0) == "00:08:30" and Fmt.short_duration(3 * 86400000.0 + 1000.0) == "3 vrk 00:00:01")
	check("taivutukset", Fmt.gen("Mars") == "Marsin" and Fmt.ill("Kuu") == "Kuuhun" and Fmt.par("Ganymedes") == "Ganymedestä")
	check("lähtöpaikka", Fmt.from_text("Maa") == "Maan kiertoradalta" and Fmt.from_text({"r": [1, 0, 0]}) == "Auringon kiertoradalta")
	check("kiertoradan kuvaus", Fmt.orbit_text("Mars") == "500 km korkeudella" and Fmt.orbit_text("Jupiter") == "5%s000 × 2%s000%s000 km radalla" % [S, S, S])
	var mu: float = Flight.orbit_of("Maa").mu
	var vc := sqrt(mu / 6571.0)
	var free := func(v: float, vr: float) -> Dictionary:
		return {"epoch": 0.0, "arg": 0.0, "rel": {"r": [6571.0, 0.0, 0.0], "v": [vr, v, 0.0]}}
	check("vapaan radan kuvaus", Fmt.orbit_text("Maa", free.call(vc, 0.0)) == "200 km korkeudella"
		and Fmt.orbit_text("Maa", free.call(vc * 1.5, 0.0)).begins_with("pakoradalla (v∞ ")
		and Fmt.orbit_text("Maa", free.call(vc, -1.0)) == "pintaa leikkaavalla radalla"
		and Fmt.orbit_text("Maa", free.call(vc * 1.05, 0.0)).ends_with("km radalla"))
	check("päivämäärän muoto", Fmt.date(1794614400000.0).split(" ").size() == 2 and Fmt.date(1794614400000.0).ends_with(".11.2026"))
	check("kellonajan muoto", Fmt.clock(1794614400000.0).length() == 8 and Fmt.clock(1794614400000.0).ends_with(".00.00"))
	finish()
