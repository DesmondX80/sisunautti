class_name TestFlags
## Testilippujen tulkinta: --orbittest → "orbit" (tiedosto tests/orbit_test.gd).


static func find(args: PackedStringArray) -> String:
	for arg in args:
		if arg.begins_with("--") and arg.ends_with("test") and not "=" in arg:
			return arg.substr(2, arg.length() - 6)
	return ""
