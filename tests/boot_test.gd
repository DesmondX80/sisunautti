extends TestCase
## Käynnistystesti: pääscene latautuu, renderöijä on oikea ja ikkunan otsikko on Sisunautti.
##   godot --headless -- --boottest


func _ready() -> void:
	await get_tree().process_frame
	var main := get_parent()
	check("pääscene", main.name == "Main" and main is Node3D)
	check("Settings-autoload", get_node_or_null("/root/Settings") != null)
	check("Game-autoload", get_node_or_null("/root/Game") != null and not Game.state.is_empty())
	check("työpöydän renderöijä Forward+", ProjectSettings.get_setting("rendering/renderer/rendering_method") == "forward_plus")
	check("selaimen renderöijä Compatibility", ProjectSettings.get_setting("rendering/renderer/rendering_method.web") == "gl_compatibility")
	check("tunnistamaton lippu ei ole testi", TestFlags.find(PackedStringArray(["--foo", "--x=1test", "--test"])) == "")
	check("testilippu arvolla", TestFlags.find(PackedStringArray(["--uishotstest=/tmp"])) == "uishots")
	check("testilippu", TestFlags.find(PackedStringArray(["--orbittest"])) == "orbit")
	finish()
