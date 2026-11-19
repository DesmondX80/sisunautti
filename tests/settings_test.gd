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
	check("oletus näytönohjaimen mukaan", s.adapter_quality(RenderingDevice.DEVICE_TYPE_DISCRETE_GPU) == s.Quality.HIGH
		and s.adapter_quality(RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU) == s.Quality.MEDIUM and s.adapter_quality(RenderingDevice.DEVICE_TYPE_CPU) == s.Quality.LOW)
	check("oletus enintään yläraja", s.default_quality() <= s.max_quality())
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
	s.set_volume(0.5)
	s.set_muted(true)
	s.volume = 1.0
	s.muted = false
	s.load_settings()
	check("äänet tallentuivat", absf(s.volume - 0.5) < 1e-6 and s.muted and AudioServer.is_bus_mute(0))
	s.set_volume(2.0)
	s.set_muted(false)
	check("voimakkuus rajataan", s.volume == 1.0 and not AudioServer.is_bus_mute(0))
	check("ikkunan otsikko", ProjectSettings.get_setting("application/config/name") == "Sisunautti")
	check("versio", ProjectSettings.get_setting("application/config/version") == "1.11.0")
	DirAccess.remove_absolute(path)
	s.path = original_path
	s.load_settings()
	finish()
