class_name PlanetInfo
## Planeettojen ja kuiden tietokortit (assets/data/planet_info.json, siirretty web/js/planetinfo.js:stä).
## Lähteet: NASA Planetary Fact Sheet ja NASA/JPL:n kuuluettelot (tilanne 2025).
## Planeetoilla: diameter, mass, gravity, day, year, temperature, atmosphere, moons, facts.
## Kuilla lisäksi parent ja orbit.

const PATH := "res://assets/data/planet_info.json"
static var _data: Dictionary = {}


static func all() -> Dictionary:
	if _data.is_empty():
		_data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return _data


static func of(name: String) -> Dictionary:
	return all().get(name, {})
