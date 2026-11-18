extends Node
## Pelin asetukset: grafiikan laatutaso. Tallentuu tiedostoon user://settings.cfg.
## Laatutaso ohjaa myöhemmin varjoja, SSAO:ta, SSR:ää, partikkeleita ja karttojen tarkkuutta (#11).

signal quality_changed(level: int)

enum Quality { LOW, MEDIUM, HIGH, ULTRA }

const QUALITY_NAMES: PackedStringArray = ["Matala", "Keski", "Korkea", "Ultra"]
const PATH := "user://settings.cfg"

var quality: int = Quality.HIGH
## Näkymä: "cockpit" (3D-ohjaamo) tai "map" (lentokartta); vastaa selainversion avainta avaruuslento.view.
var view := "cockpit"
## Sivupaneeli piilotettu; vastaa selainversion avainta avaruuslento.panel.
var panel_hidden := false
var path := PATH # testit vaihtavat polun, jotta oikeat asetukset eivät muutu


func _ready() -> void:
	load_settings()


## Oletustaso: selaimessa (Compatibility) Keski, työpöydällä Korkea.
static func default_quality() -> int:
	if OS.has_feature("web") or is_compatibility():
		return Quality.MEDIUM
	return Quality.HIGH


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


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		quality = default_quality()
		view = "cockpit"
		panel_hidden = false
		return
	quality = clampi(int(cfg.get_value("graphics", "quality", default_quality())), Quality.LOW, max_quality())
	view = String(cfg.get_value("ui", "view", "cockpit"))
	panel_hidden = bool(cfg.get_value("ui", "panel_hidden", false))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", quality)
	cfg.set_value("ui", "view", view)
	cfg.set_value("ui", "panel_hidden", panel_hidden)
	cfg.save(path)
