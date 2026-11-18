class_name TestFlags
## Testilippujen tulkinta: --orbittest → "orbit" (tiedosto tests/orbit_test.gd). Lipulla voi olla arvo:
## --uishotstest=/polku → "uishots".


static func find(args: PackedStringArray) -> String:
	for arg in args:
		var name := arg.split("=")[0]
		if name.begins_with("--") and name.ends_with("test") and name.length() > 6:
			return name.substr(2, name.length() - 6)
	return ""
