class_name GameOver
extends Control
## Aluksen tuhoutuminen (#42): välähdys, punainen hehku ja kortti, jossa syy, lennon yhteenveto ja uusi peli.

var _card: PanelContainer
var _cause: Label
var _summary: Label
var _shown_at := -1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiKit.box(Color(0.04, 0.01, 0.02, 0.94), Color(FaultPanel.RED, 0.9), 16, 26, 2))
	add_child(_card)
	var v := UiKit.vbox(14)
	_card.add_child(v)
	var title := UiKit.label("ALUS TUHOUTUI", "", false)
	title.add_theme_font_override("font", load(UiKit.FONT_BOLD))
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", FaultPanel.RED)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_cause = UiKit.label("")
	_cause.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cause.add_theme_font_size_override("font_size", 18)
	v.add_child(_cause)
	_summary = UiKit.label("", "MutedLabel")
	_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_summary)
	var go := UiKit.button("Aloita uusi peli", func() -> void: Game.new_game(), "GoButton")
	go.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	go.custom_minimum_size.x = 240
	v.add_child(go)
	resized.connect(_place)
	visible = false


func _place() -> void:
	var w := minf(size.x - 32.0, 560.0)
	_card.size = Vector2(w, 0)
	_card.reset_size()
	_card.size.x = w
	_card.position = ((size - _card.size) / 2.0).floor()


func _process(_delta: float) -> void:
	var d: Variant = Game.state.get("destroyed") if not Game.state.is_empty() else null
	if (d != null) != visible:
		visible = d != null
		_shown_at = Time.get_ticks_msec() / 1000.0
		if visible:
			_fill(d)
	if visible:
		queue_redraw()


func _fill(d: Dictionary) -> void:
	_cause.text = String(d.text)
	var s: Dictionary = Game.state
	var flown: int = s.flights.size()
	var explored: int = s.explored.size()
	_summary.text = "%s · %d %s · %d tutkittua kohdetta" % [Fmt.date(float(d.t)), flown, "lento" if flown == 1 else "lentoa", explored]
	_place.call_deferred()


func _draw() -> void:
	var age := Time.get_ticks_msec() / 1000.0 - _shown_at
	var pulse := 0.5 + 0.5 * sin(age * 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.0, 0.01, minf(0.85, 0.3 + age * 0.4)))
	for i in 8:
		var m := 22.0 * i
		draw_rect(Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0), Color(FaultPanel.RED, (0.12 + 0.06 * pulse) * (1.0 - i / 8.0)), false, 22.0)
	# Räjähdyksen välähdys ensimmäisellä sekunnilla.
	var flash := clampf(1.0 - age / 1.2, 0.0, 1.0)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.6, flash * flash))
