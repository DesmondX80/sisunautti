class_name StartMenu
extends Control
## Aloitusvalikko: Jatka peliä, Uusi peli, Asetukset ja Lopeta peli (ei selaimessa). Taustalla James Webb
## -avaruusteleskoopin kuva Kosmiset kalliot (NASA, ESA, CSA, STScI, CC BY 4.0) hitaasti liikkuvana
## (shaders/menu_bg.gdshader). Valikko avautuu pelin alussa ja pelistä valikkopainikkeella tai Esc-näppäimellä.
## Signaali closed lähetetään, kun valikosta jatketaan peliin.

signal closed

const BACKGROUND := "res://assets/menu/taustakuva.webp"
const CREDIT := "Taustakuva: Kosmiset kalliot Carinan sumussa, James Webb -avaruusteleskooppi · NASA, ESA, CSA, STScI (CC BY 4.0)"

var continue_button: Button
var new_button: Button
var settings_button: Button
var quit_button: Button
var settings_panel: PanelContainer
var confirm: ConfirmationDialog
var _bg_mat: ShaderMaterial
var _column: VBoxContainer
var _quality_seg: PanelContainer
var _full_button: Button


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(black)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = load("res://shaders/menu_bg.gdshader")
	var tex: Texture2D = load(BACKGROUND)
	_bg_mat.set_shader_parameter("image", tex)
	_bg_mat.set_shader_parameter("image_aspect", float(tex.get_width()) / tex.get_height())
	bg.material = _bg_mat
	add_child(bg)
	_build_column()
	_build_settings()
	_build_footer()
	confirm = ConfirmationDialog.new()
	confirm.title = "Uusi peli"
	confirm.dialog_text = "Aloitetaanko uusi peli? Nykyinen peli korvataan, ja uusi lento lähtee laukaisualustalta Maan pinnalta."
	confirm.dialog_autowrap = true
	confirm.ok_button_text = "Uusi peli"
	confirm.cancel_button_text = "Peru"
	confirm.confirmed.connect(_start_new)
	add_child(confirm)
	resized.connect(_layout)
	_layout()
	refresh()


## Päivittää painikkeet pelin tilan mukaan (Jatka peliä vain, jos peli on tallessa).
func refresh() -> void:
	continue_button.disabled = not Game.has_saved_game
	continue_button.visible = Game.has_saved_game
	(continue_button if Game.has_saved_game else new_button).grab_focus.call_deferred()


func _build_column() -> void:
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(m)
	_column = UiKit.vbox(14)
	_column.alignment = BoxContainer.ALIGNMENT_CENTER
	_column.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	m.add_child(_column)
	var title := Label.new()
	title.text = "SISUNAUTTI"
	title.add_theme_font_override("font", load(UiKit.FONT_BOLD))
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", UiKit.FG)
	title.add_theme_color_override("font_shadow_color", Color(0.37, 0.84, 1.0, 0.28))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 0)
	title.add_theme_constant_override("shadow_outline_size", 10)
	title.name = "Title"
	_column.add_child(title)
	var line := ColorRect.new()
	line.color = UiKit.ACCENT
	line.custom_minimum_size = Vector2(120, 3)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_column.add_child(line)
	var sub := UiKit.label("Maan pinnalta kiertoradalle ja planeetoille\noikeilla taivaanmekaniikan kaavoilla", "MutedLabel", false)
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", UiKit.FG.darkened(0.12))
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	sub.add_theme_constant_override("shadow_outline_size", 6)
	_column.add_child(sub)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	_column.add_child(gap)
	continue_button = _menu_button("Jatka peliä", _continue, true)
	new_button = _menu_button("Uusi peli", _ask_new)
	settings_button = _menu_button("Asetukset", toggle_settings)
	quit_button = _menu_button("Lopeta peli", _quit)
	quit_button.visible = not OS.has_feature("web")


func _menu_button(text: String, on_press: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(300, 52)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.add_theme_font_override("font", load(UiKit.FONT_BOLD))
	b.add_theme_font_size_override("font_size", 20)
	var accent := UiKit.ACCENT if not primary else UiKit.WARM
	for state: String in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var sb := StyleBoxFlat.new()
		var hot := state in ["hover", "pressed", "focus", "hover_pressed"]
		sb.bg_color = Color(0.02, 0.05, 0.11, 0.78 if hot else 0.5)
		sb.border_color = Color(accent, 1.0 if hot else 0.45)
		sb.border_width_left = 4
		sb.border_width_bottom = 1 if hot else 0
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 22 if not hot else 28
		sb.content_margin_right = 22
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
		if state == "focus":
			sb.draw_center = false
			sb.border_width_left = 0
			sb.border_width_bottom = 0
		b.add_theme_stylebox_override(state, sb)
	for k: String in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(k, UiKit.FG)
	for k: String in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, accent.lightened(0.3))
	b.pressed.connect(on_press)
	_column.add_child(b)
	return b


func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	var sb := UiKit.box(Color(0.02, 0.04, 0.09, 0.88), Color(UiKit.ACCENT, 0.35), 12, 22)
	settings_panel.add_theme_stylebox_override("panel", sb)
	settings_panel.visible = false
	add_child(settings_panel)
	var v := UiKit.vbox(12)
	settings_panel.add_child(v)
	v.add_child(UiKit.label("Asetukset", "TitleLabel"))
	v.add_child(UiKit.label("Grafiikan laatu", "MutedLabel"))
	var levels := []
	for i in Settings.max_quality() + 1:
		levels.append([i, Settings.QUALITY_NAMES[i]])
	_quality_seg = UiKit.seg(levels, Settings.quality, func(i: int) -> void: Settings.set_quality(i))
	v.add_child(_quality_seg)
	v.add_child(UiKit.label("Korkea ja Ultra: pehmeät varjot, varjojen peitto ja Ultralla heijastukset sekä 8k-pintakartat. Selaimessa enintään Keski.", "MutedLabel"))
	_full_button = UiKit.button("", _toggle_fullscreen)
	v.add_child(_full_button)
	_update_full_text()
	v.add_child(UiKit.label("Versio %s · %s" % [VoyageUI.version(), "selain" if Settings.is_compatibility() else "työpöytä"], "MutedLabel"))
	v.add_child(UiKit.button("Sulje", toggle_settings))


func _build_footer() -> void:
	var credit := UiKit.label(CREDIT, "MutedLabel", true)
	credit.name = "Credit"
	credit.add_theme_font_size_override("font_size", 11)
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	credit.modulate = Color(1, 1, 1, 0.7)
	add_child(credit)


func _layout() -> void:
	var narrow := size.x < 700.0
	var m := _column.get_parent() as MarginContainer
	m.add_theme_constant_override("margin_left", int(maxf(24.0, size.x * (0.04 if narrow else 0.08))))
	m.add_theme_constant_override("margin_right", 24)
	(_column.get_node("Title") as Label).add_theme_font_size_override("font_size", 44 if narrow else 64)
	var credit := get_node("Credit") as Label
	credit.size = Vector2(minf(size.x - 32.0, 760.0), 0)
	credit.position = Vector2(size.x - credit.size.x - 16.0, size.y - 34.0 - (14.0 if narrow else 0.0))
	var w := minf(420.0, size.x - 32.0)
	settings_panel.custom_minimum_size = Vector2(w, 0)
	settings_panel.size = Vector2(w, 0)
	settings_panel.reset_size()
	if narrow:
		settings_panel.position = Vector2(16, maxf(16.0, (size.y - settings_panel.size.y) / 2.0))
	else:
		settings_panel.position = Vector2(size.x - w - size.x * 0.08, (size.y - settings_panel.size.y) / 2.0)
	_bg_mat.set_shader_parameter("view_aspect", size.x / maxf(1.0, size.y))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and size.x > 0.0:
		var p := (event as InputEventMouseMotion).position / size * 2.0 - Vector2.ONE
		_bg_mat.set_shader_parameter("parallax", p)


func toggle_settings() -> void:
	settings_panel.visible = not settings_panel.visible
	# Kapeassa ikkunassa asetukset peittävät valikon: valikko piiloon siksi aikaa.
	_column.visible = not (settings_panel.visible and size.x < 700.0)
	if settings_panel.visible:
		_quality_seg.queue_free()
		var levels := []
		for i in Settings.max_quality() + 1:
			levels.append([i, Settings.QUALITY_NAMES[i]])
		_quality_seg = UiKit.seg(levels, Settings.quality, func(i: int) -> void: Settings.set_quality(i))
		var v := settings_panel.get_child(0)
		v.add_child(_quality_seg)
		v.move_child(_quality_seg, 2)
		_update_full_text()
		_layout.call_deferred()


func _toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	_update_full_text()


func _update_full_text() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	_full_button.text = "Ikkunaan" if full else "Koko näyttö"


func _continue() -> void:
	close()


func _ask_new() -> void:
	if not Game.has_saved_game:
		_start_new()
		return
	var w := mini(460, int(size.x) - 32)
	confirm.popup_centered(Vector2i(w, 0))


func _start_new() -> void:
	Game.new_game()
	close()


func _quit() -> void:
	Game.park()
	get_tree().quit()


## Häivyttää valikon ja lähettää closed.
func close() -> void:
	settings_panel.visible = false
	_column.visible = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.35)
	tw.tween_callback(func() -> void:
		visible = false
		modulate.a = 1.0
		mouse_filter = Control.MOUSE_FILTER_STOP
		closed.emit())


## Näyttää valikon (pelin alussa ja valikkopainikkeesta).
func open() -> void:
	visible = true
	modulate.a = 0.0
	refresh()
	create_tween().tween_property(self, "modulate:a", 1.0, 0.3)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		if settings_panel.visible:
			toggle_settings()
		elif Game.has_saved_game:
			close()
		get_viewport().set_input_as_handled()
