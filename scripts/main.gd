extends Node3D
## Pääscene. Käynnistyslippu --<nimi>test lataa testin tests/<nimi>_test.gd ja liittää sen tämän alle.

const TEST_DIR := "res://tests/"


var ui: VoyageUI


func _ready() -> void:
	DisplayServer.window_set_title("Sisunautti")
	# Käyttöliittymä on oikeissa pikseleissä (ei venytystä); tarkoilla näytöillä (selain, puhelin) skaalataan.
	get_window().content_scale_factor = maxf(1.0, DisplayServer.screen_get_scale())
	var layer := CanvasLayer.new()
	layer.name = "UI"
	add_child(layer)
	ui = VoyageUI.new()
	ui.name = "VoyageUI"
	layer.add_child(ui)
	var test := TestFlags.find(OS.get_cmdline_user_args())
	if test != "":
		var path := TEST_DIR + test + "_test.gd"
		if not ResourceLoader.exists(path):
			push_error("Testiä ei löytynyt: " + test)
			get_tree().quit(2)
			return
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			push_error("Testiä ei voitu ladata: " + path)
			get_tree().quit(2)
			return
		var node: Node = script.new()
		node.name = "Test"
		add_child(node)
