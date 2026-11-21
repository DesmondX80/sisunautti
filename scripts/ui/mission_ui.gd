class_name MissionUI
## Lennonjohdon tehtävät (#44) sivupaneelissa: pisteet ja aktiiviset tehtävät kortteina (lajin väri reunassa,
## palkkio ja luopuminen) sekä viimeksi suoritetut.

## Lajin väri ja merkki.
const KIND_STYLE := {"orbit": [UiKit.ACCENT, "◎"], "survey": [Color("#a78bfa"), "◉"], "flyby": [Color("#f472b6"), "↝"],
	"aero": [UiKit.WARM, "≋"], "fast": [Color("#facc15"), "»"], "frugal": [UiKit.GOOD, "◆"], "land": [Color("#e2e8f0"), "▼"], "fault": [UiKit.BAD, "⚠"]}


static func color_of(m: Dictionary) -> Color:
	return KIND_STYLE.get(m.kind, [UiKit.ACCENT, ""])[0]


static func icon_of(m: Dictionary) -> String:
	return KIND_STYLE.get(m.kind, [UiKit.ACCENT, "•"])[1]


## Tehtäväkortti: lajin värinen reunaviiva vasemmalla, merkki, otsikko ja ohje, palkkio oikealla.
static func mission_row(m: Dictionary, on_discard: Callable) -> Control:
	var col := color_of(m)
	var p := PanelContainer.new()
	var sb := UiKit.box(UiKit.RAISED, UiKit.LINE, 8, 10)
	sb.border_width_left = 4
	sb.border_color = col
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.bg_color = UiKit.RAISED.lerp(col, 0.06)
	p.add_theme_stylebox_override("panel", sb)
	var h := UiKit.hbox(10)
	p.add_child(h)
	var icon := UiKit.label(icon_of(m), "TitleLabel", false)
	icon.add_theme_color_override("font_color", col)
	icon.custom_minimum_size.x = 18
	icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(icon)
	var v := UiKit.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(UiKit.label(Missions.title(m), "TitleLabel"))
	v.add_child(UiKit.label(Missions.text(m), "MutedLabel"))
	h.add_child(v)
	var right := UiKit.vbox(4)
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var pts := UiKit.label("+%d TP" % int(m.points), "TitleLabel", false)
	pts.add_theme_color_override("font_color", col.lightened(0.2))
	pts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.add_child(pts)
	var x := UiKit.button("Luovu", on_discard)
	x.tooltip_text = "Luovu tehtävästä: lennonjohto antaa tilalle uuden"
	x.custom_minimum_size = Vector2(56, 26)
	x.add_theme_font_size_override("font_size", 11)
	right.add_child(x)
	h.add_child(right)
	return p


## Paneelin tehtäväosio: content-laatikkoon pisteet, aktiiviset ja viimeksi suoritetut.
static func fill(v: VBoxContainer, ms: Dictionary) -> void:
	var head := UiKit.hbox(8)
	var pts := UiKit.label("%s tutkimuspistettä" % Fmt.num(int(ms.points)), "TitleLabel", false)
	pts.add_theme_color_override("font_color", UiKit.ACCENT)
	pts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(pts)
	head.add_child(UiKit.label("suoritettu %d" % ms.done.size(), "MutedLabel", false))
	v.add_child(head)
	if ms.active.is_empty():
		v.add_child(UiKit.label("Lennonjohdolla ei ole uusia tehtäviä.", "MutedLabel"))
	for m: Dictionary in ms.active:
		var id := int(m.id)
		v.add_child(mission_row(m, func() -> void: Game.discard_mission(id)))
	var done: Array = ms.done
	if not done.is_empty():
		v.add_child(UiKit.label("Suoritetut", "MutedLabel"))
		for i in range(done.size() - 1, maxi(-1, done.size() - 6), -1):
			var m: Dictionary = done[i]
			var row := UiKit.hbox(8)
			var ok := UiKit.label("✓", "", false)
			ok.add_theme_color_override("font_color", UiKit.GOOD)
			row.add_child(ok)
			var t := UiKit.label(Missions.title(m))
			t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(t)
			row.add_child(UiKit.label("+%d" % int(m.points), "MutedLabel", false))
			v.add_child(row)
