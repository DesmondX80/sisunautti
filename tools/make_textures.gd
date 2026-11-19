extends SceneTree
## Tekee ladatuista lähdekuvista pelin tekstuurit (WebP) hakemistoon assets/textures/.
## Käyttö: godot --headless -s tools/make_textures.gd -- /polku/lähdekuviin
## Lähteet (Wikimedia Commons, ks. README):
##   clouds8k.jpg   Solarsystemscope texture 8k earth clouds.jpg (CC BY 4.0)
## Maan päiväkartta, merimaski, yövalot ja 8k-pilvet: tools/make_earth_textures.py (NASA Blue Marble ja Black Marble).
##   milkyway.jpg   Deep Star Maps 2020 – Milkyway 2020 (NASA/GSFC SVS, public domain, 3840 px esikatselukuva)

const OUT := "res://assets/textures/"


func _init() -> void:
	var src: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "."
	make(src.path_join("clouds8k.jpg"), "maa-pilvet", [4096, 2048], 0.8, true)
	make(src.path_join("milkyway.jpg"), "linnunrata", [4096], 0.85)
	quit()


## Pienentää kuvan annettuihin leveyksiin (korkeus puolet) ja tallentaa WebP:nä. Leveimmästä tulee
## nimi-8k/-4k, 2048:sta perusnimi. gray: harmaasävykuva (pilvet, meret) tallennetaan yksikanavaisena tietona.
func make(path: String, name: String, widths: Array, quality: float, gray: bool = false) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		push_error("Kuvaa ei voitu ladata: " + path)
		return
	img.convert(Image.FORMAT_RGB8)
	for w: int in widths:
		var copy := img.duplicate() as Image
		copy.resize(w, w / 2, Image.INTERPOLATE_LANCZOS)
		if gray:
			copy.convert(Image.FORMAT_L8)
			copy.convert(Image.FORMAT_RGB8)
		var suffix := "" if w <= 2048 else "-%dk" % (w / 1024)
		var out := OUT + name + suffix + ".webp"
		var err := copy.save_webp(out, true, quality)
		print("%s %dx%d %s" % [out, copy.get_width(), copy.get_height(), "ok" if err == OK else "virhe %d" % err])
