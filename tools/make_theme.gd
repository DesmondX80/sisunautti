extends SceneTree
## Tallentaa käyttöliittymän teeman (UiKit.make_theme) tiedostoon ui/theme.tres.
## Käyttö: godot --headless -s tools/make_theme.gd


func _init() -> void:
	var err := ResourceSaver.save(UiKit.make_theme(), UiKit.THEME_PATH)
	print("ui/theme.tres: ", "tallennettu" if err == OK else "virhe %d" % err)
	quit(0 if err == OK else 1)
