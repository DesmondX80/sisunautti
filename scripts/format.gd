class_name Fmt
## Suomenkielinen muotoilu (web/js/voyage.js ja core.js): luvut pilkulla ja tuhaterottimella kuten JS:n
## toLocaleString('fi-FI'), päivät, kellonajat, kestot, etäisyydet ja kappaleiden nimien taivutukset.

const DAY_MS := 86400000.0
const NBSP := "\u00a0"
const MINUS := "−"
const WEEKDAYS: PackedStringArray = ["su", "ma", "ti", "ke", "to", "pe", "la"]

## Kappaleiden nimien taivutukset: [genetiivi, illatiivi, partitiivi].
const NAMES := {
	"Merkurius": ["Merkuriuksen", "Merkuriukseen", "Merkuriusta"], "Venus": ["Venuksen", "Venukseen", "Venusta"],
	"Maa": ["Maan", "Maahan", "Maata"], "Mars": ["Marsin", "Marsiin", "Marsia"], "Jupiter": ["Jupiterin", "Jupiteriin", "Jupiteria"],
	"Saturnus": ["Saturnuksen", "Saturnukseen", "Saturnusta"], "Uranus": ["Uranuksen", "Uranukseen", "Uranusta"],
	"Neptunus": ["Neptunuksen", "Neptunukseen", "Neptunusta"], "Kuu": ["Kuun", "Kuuhun", "Kuuta"],
	"Phobos": ["Phoboksen", "Phobokseen", "Phobosta"], "Io": ["Ion", "Iohon", "Iota"], "Europa": ["Europan", "Europaan", "Europaa"],
	"Ganymedes": ["Ganymedeen", "Ganymedeeseen", "Ganymedestä"], "Titan": ["Titanin", "Titaniin", "Titania"],
	"Enceladus": ["Enceladuksen", "Enceladukseen", "Enceladusta"], "Triton": ["Tritonin", "Tritoniin", "Tritonia"],
}


static func gen(name: String) -> String:
	return NAMES[name][0]


static func ill(name: String) -> String:
	return NAMES[name][1]


static func par(name: String) -> String:
	return NAMES[name][2]


## Luku enintään digits desimaalilla ilman perässä olevia nollia: 1 234 567,89, −5 (puolikkaat poispäin nollasta).
static func num(v: float, digits: int = 0) -> String:
	var k := pow(10.0, digits)
	var r := roundf(absf(v) * k) / k # roundf pyöristää puolikkaat poispäin nollasta kuten Intl.NumberFormat
	var s := String.num(r, digits)
	var int_part := s
	var frac := ""
	var dot := s.find(".")
	if dot >= 0:
		int_part = s.substr(0, dot)
		frac = s.substr(dot + 1).rstrip("0")
	var grouped := ""
	var n := int_part.length()
	for i in n:
		if i > 0 and (n - i) % 3 == 0:
			grouped += NBSP
		grouped += int_part[i]
	var out := grouped + ("," + frac if frac != "" else "")
	return (MINUS if v < 0.0 and r != 0.0 else "") + out


## Nopeus tai Δv: "3,6 km/s".
static func dv(v: float) -> String:
	return "%s km/s" % num(v, 2)


static func days(d: float) -> String:
	if d < 730.0:
		return "%s vrk" % num(roundf(d))
	var y := floorf(d / 365.25)
	return "%d v %s vrk" % [int(y), num(roundf(d - y * 365.25))]


static func km(value: float) -> String:
	if value < 1e6:
		return "%s km" % num(value)
	var au := value / Planets.AU_KM
	return "%s milj. km" % num(value / 1e6, 2) if au < 0.1 else "%s milj. km (%s AU)" % [num(value / 1e6), num(au, 2)]


static func light_time(value_km: float) -> String:
	var minutes := value_km / Planets.AU_KM / Planets.LIGHT_AU_PER_MIN
	if minutes < 1.0:
		return "%s s" % num(minutes * 60.0)
	return "%s min" % num(minutes, 1) if minutes < 120.0 else "%s h" % num(minutes / 60.0, 1)


## Kesto ilman nollapäiviä: "8:30" → "00:08:30" (alle vuorokausi) tai "3 vrk 01:02:03".
static func short_duration(ms: float) -> String:
	var s := Flight.fmt_duration(ms)
	return s.substr(6) if s.begins_with("0 vrk ") else s


## Paikallinen aika (järjestelmän aikavyöhyke) päivämäärän osina.
static func _local(t: float) -> Dictionary:
	var bias := int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	return Time.get_datetime_dict_from_unix_time(int(floor(t / 1000.0)) + bias)


## Päivämäärä: "la 14.11.2026".
static func date(t: float) -> String:
	var d := _local(t)
	return "%s %d.%d.%d" % [WEEKDAYS[d.weekday], d.day, d.month, d.year]


## Kellonaika: "02.00.00".
static func clock(t: float) -> String:
	var d := _local(t)
	return "%02d.%02d.%02d" % [d.hour, d.minute, d.second]


static func from_text(from: Variant) -> String:
	return "%s kiertoradalta" % gen(from) if Flight.is_planet(from) else "Auringon kiertoradalta"


static func orbit_text(name: String) -> String:
	var b := Flight.orbit_of(name)
	var peri: float = b.periKm - b.radiusKm
	var apo: float = b.apoKm - b.radiusKm
	return "%s km korkeudella" % num(peri) if peri == apo else "%s × %s km radalla" % [num(peri), num(apo)]
