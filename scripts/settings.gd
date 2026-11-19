extends Node
## Pelin asetukset: grafiikan laatutaso ja äänet (voimakkuus, mykistys). Tallentuu tiedostoon user://settings.cfg.
## Laatutaso ohjaa myöhemmin varjoja, SSAO:ta, SSR:ää, partikkeleita ja karttojen tarkkuutta (#11).

signal quality_changed(level: int)
signal audio_changed

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const QUALITY_NAMES: PackedStringArray = ["Matala", "Keski", "Korkea", "Ultra"]
const PATH := "user://settings.cfg"

var quality: int = Quality.HIGH
## Näkymä: "cockpit" (3D-ohjaamo) tai "map" (lentokartta); vastaa selainversion avainta avaruuslento.view.
var view := "cockpit"
## Sivupaneeli piilotettu; vastaa selainversion avainta avaruuslento.panel.
var panel_hidden := false
## Äänenvoimakkuus 0–1 ja mykistys (pääväylä).
var volume := 0.8
var muted := false
## Radio: musiikin voimakkuus 0–1 ja valittu kanava (−1 pois).
var music_volume := 0.6
var radio_channel := -1
var path := PATH # testit vaihtavat polun, jotta oikeat asetukset eivät muutu


func _ready() -> void:
	load_settings()


## Oletustaso näytönohjaimen mukaan: erillinen näytönohjain Korkea, integroitu Keski, ohjelmallinen (esim.
## llvmpipe) Matala. Selaimessa (Compatibility) enintään Keski.
static func default_quality() -> int:
	var level: int = adapter_quality(RenderingServer.get_video_adapter_type())
	return mini(level, max_quality())


static func adapter_quality(device_type: int) -> int:
	match device_type:
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU: return Quality.HIGH
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU, RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU: return Quality.MEDIUM
		RenderingDevice.DEVICE_TYPE_CPU: return Quality.LOW
	return Quality.MEDIUM


static func is_compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == "gl_compatibility"


## Selaimessa Korkea ja Ultra eivät ole käytettävissä (ei SSAO:ta eikä SSR:ää).
static func max_quality() -> int:
	return Quality.MEDIUM if OS.has_feature("web") or is_compatibility() else Quality.ULTRA


func quality_name() -> String:
	return QUALITY_NAMES[quality]


func set_quality(level: int) -> void:
	level = clampi(level, Quality.LOW, max_quality())
	if level == quality:
		return
	quality = level
	save_settings()
	quality_changed.emit(quality)


func set_view(v: String) -> void:
	view = v
	save_settings()


func set_panel_hidden(hidden: bool) -> void:
	panel_hidden = hidden
	save_settings()


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	apply_audio()
	save_settings()


func set_muted(m: bool) -> void:
	muted = m
	apply_audio()
	save_settings()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	audio_changed.emit()
	save_settings()


func set_radio_channel(c: int) -> void:
	radio_channel = c
	save_settings()


## Pääväylän voimakkuus ja mykistys.
func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))
	AudioServer.set_bus_mute(0, muted or volume <= 0.0)
	audio_changed.emit()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		quality = default_quality()
		view = "cockpit"
		panel_hidden = false
		volume = 0.8
		muted = false
		music_volume = 0.6
		radio_channel = -1
		apply_audio()
		return
	quality = clampi(int(cfg.get_value("graphics", "quality", default_quality())), Quality.LOW, max_quality())
	view = String(cfg.get_value("ui", "view", "cockpit"))
	panel_hidden = bool(cfg.get_value("ui", "panel_hidden", false))
	volume = clampf(float(cfg.get_value("audio", "volume", 0.8)), 0.0, 1.0)
	muted = bool(cfg.get_value("audio", "muted", false))
	music_volume = clampf(float(cfg.get_value("audio", "music_volume", 0.6)), 0.0, 1.0)
	radio_channel = int(cfg.get_value("audio", "radio_channel", -1))
	apply_audio()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("ui", "view", view)
	cfg.set_value("ui", "panel_hidden", panel_hidden)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("audio", "muted", muted)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "radio_channel", radio_channel)
	cfg.save(path)
