extends TestCase
## Asetusten testi: laatutasot, oletus, rajaus ja tallennus.
##   godot --headless -- --settingstest


func _ready() -> void:
	var path := "user://settings_test.cfg"
	DirAccess.remove_absolute(path)
	var s: Node = Settings
	var original_path: String = s.path
	s.path = path
	s.load_settings()
	check("oletustaso ilman tiedostoa", s.quality == s.default_quality())
	check("neljä laatutasoa", s.QUALITY_NAMES.size() == 4 and s.QUALITY_NAMES[0] == "Matala" and s.QUALITY_NAMES[3] == "Ultra")
	check("työpöydän oletus Korkea", OS.has_feature("web") or s.is_compatibility() or s.default_quality() == s.Quality.HIGH)
	var got: Array[int] = []
	s.quality_changed.connect(func(level: int) -> void: got.append(level))
	s.set_quality(s.Quality.LOW)
	check("tason vaihto ja signaali", s.quality == s.Quality.LOW and got == [s.Quality.LOW])
	s.set_quality(99)
	check("taso rajataan ylärajaan", s.quality == s.max_quality())
	s.quality = s.Quality.LOW
	s.load_settings()
	check("taso tallentui", s.quality == s.max_quality())
	check("tason nimi", s.quality_name() == s.QUALITY_NAMES[s.quality])
	check("ikkunan otsikko", ProjectSettings.get_setting("application/config/name") == "Sisunautti")
	check("versio", ProjectSettings.get_setting("application/config/version") == "0.2.0")
	DirAccess.remove_absolute(path)
	s.path = original_path
	s.load_settings()
	finish()
