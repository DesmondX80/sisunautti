class_name MissionToast
extends Control
## Lennonjohdon tehtäväilmoitus (#44) näkymän yläreunassa: uusi tehtävä tai suoritettu tehtävä. Ilmoitukset
## jonossa; kukin liukuu sisään, hehkuu hetken ja häipyy.

const HOLD_S := 5.5
const IN_S := 0.45
const OUT_S := 0.6

var _queue: Array = [] # [otsake, otsikko, alarivi, väri, merkki]
var _busy := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Game.mission_issued.connect(func(m: Dictionary) -> void:
		push("UUSI TEHTÄVÄ", Missions.title(m), Missions.text(m), MissionUI.color_of(m), MissionUI.icon_of(m)))
	Game.mission_completed.connect(func(m: Dictionary) -> void:
		push("TEHTÄVÄ SUORITETTU", Missions.title(m), "+%d tutkimuspistettä" % int(m.points), UiKit.GOOD, "✓"))


func push(head: String, title: String, sub: String, col: Color, icon: String) -> void:
	_queue.append([head, title, sub, col, icon])
	if not _busy:
		_next()


func pending() -> int:
	return _queue.size() + (1 if _busy else 0)


func _next() -> void:
	if _queue.is_empty():
		_busy = false
		return
	_busy = true
	var it: Array = _queue.pop_front()
	var col: Color = it[3]
	var panel := PanelContainer.new()
	var sb := UiKit.box(Color(UiKit.CARD, 0.92), col, 12, 16, 1)
	sb.shadow_color = Color(col, 0.35)
	sb.shadow_size = 18
	sb.border_width_left = 5
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UiKit.hbox(14)
	panel.add_child(h)
	var icon := UiKit.label(it[4], "BigLabel", false)
	icon.add_theme_color_override("font_color", col)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(icon)
	var v := UiKit.vbox(2)
	var head := UiKit.label(String(it[0]), "MutedLabel", false)
	head.add_theme_color_override("font_color", col.lightened(0.25))
	head.add_theme_constant_override("outline_size", 0)
	v.add_child(head)
	v.add_child(UiKit.label(String(it[1]), "HeadLabel", false))
	var sub := UiKit.label(String(it[2]), "", true)
	sub.custom_minimum_size.x = clampf(size.x - 120.0, 180.0, 420.0)
	v.add_child(sub)
	h.add_child(v)
	add_child(panel)
	# Keskelle yläreunaan, kun koko tiedetään.
	await get_tree().process_frame
	var w := minf(panel.get_combined_minimum_size().x, size.x - 24.0)
	panel.size = Vector2(w, 0)
	var x := (size.x - panel.size.x) / 2.0
	panel.position = Vector2(x, 2.0)
	panel.modulate = Color(1, 1, 1, 0)
	panel.pivot_offset = panel.size / 2.0
	panel.scale = Vector2(0.96, 0.96)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "position:y", 58.0, IN_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, IN_S * 0.8)
	tw.tween_property(panel, "scale", Vector2.ONE, IN_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# Reunan hehku sykähtää kerran.
	tw.chain().tween_method(func(k: float) -> void: sb.shadow_size = int(18.0 + 14.0 * sin(k * PI)), 0.0, 1.0, 0.9)
	tw.chain().tween_interval(HOLD_S)
	tw.chain().tween_property(panel, "modulate:a", 0.0, OUT_S)
	tw.parallel().tween_property(panel, "position:y", 40.0, OUT_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func() -> void:
		panel.queue_free()
		_next())
