extends Node3D
## Pääscene. Käynnistyslippu --<nimi>test lataa testin tests/<nimi>_test.gd ja liittää sen tämän alle.

const TEST_DIR := "res://tests/"


var ui: VoyageUI
var menu: StartMenu
var sound: GameSound
var radio: Radio


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
	# Työpöydällä peli käynnistyy koko näytön tilassa (ei testeissä, joissa ikkunan koko asetetaan; selaimessa koko
	# näyttö vaatii käyttäjän painalluksen).
	if test == "" and not OS.has_feature("web") and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	# Aloitusvalikko pelin päällä (ei testeissä); pelinäkymä piilotetaan, kun valikko on auki.
	var menu_layer := CanvasLayer.new()
	menu_layer.name = "Menu"
	menu_layer.layer = 5
	add_child(menu_layer)
	menu = StartMenu.new()
	menu.name = "StartMenu"
	menu_layer.add_child(menu)
	sound = GameSound.new()
	sound.name = "Sound"
	add_child(sound)
	radio = Radio.new()
	radio.name = "Radio"
	add_child(radio)
	menu.closed.connect(func() -> void:
		ui.visible = true
		Game.faults_paused = false
		sound.quiet = false)
	ui.menu_requested.connect(show_menu)
	if test != "":
		menu.visible = false
	else:
		ui.visible = false
		Game.faults_paused = true
		sound.quiet = true
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


## Avaa aloitusvalikon pelin päälle (valikkopainike tai Esc).
func show_menu() -> void:
	menu.open()
	Game.faults_paused = true
	sound.quiet = true
	await get_tree().create_timer(0.3).timeout
	if menu.visible:
		ui.visible = false
