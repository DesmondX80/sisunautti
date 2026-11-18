extends Node3D
## Pääscene. Käynnistyslippu --<nimi>test lataa testin tests/<nimi>_test.gd ja liittää sen tämän alle.

const TEST_DIR := "res://tests/"


func _ready() -> void:
	DisplayServer.window_set_title("Sisunautti")
	var test := TestFlags.find(OS.get_cmdline_user_args())
	if test != "":
		var script: GDScript = load(TEST_DIR + test + "_test.gd")
		if script == null:
			push_error("Testiä ei löytynyt: " + test)
			get_tree().quit(2)
			return
		var node: Node = script.new()
		node.name = "Test"
		add_child(node)
