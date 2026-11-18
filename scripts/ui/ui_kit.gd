class_name UiKit
## Käyttöliittymän teema ja rakennuspalikat. Värit ovat selainversion (web/styles.css): tumma tausta ja
## #5ed6ff-korostus. Teema rakennetaan koodissa (make_theme) ja tallennetaan tiedostoon ui/theme.tres
## (tools/make_theme.gd), jota projekti käyttää oletusteemana.
## Tyyppivariaatiot: GoButton (päätoiminto), SegButton (valintaryhmä), Card, Stat, MutedLabel, TitleLabel,
## BigLabel (kello ja lähtölaskenta), HeadLabel (otsikko) ja WarnLabel.

const BG := Color("#05070f")
const CARD := Color("#0d1220")
const RAISED := Color("#121a2e")
const LINE := Color("#1d2740")
const FG := Color("#e8eefc")
const MUTED := Color("#8b9ac0")
const ACCENT := Color("#5ed6ff")
const WARM := Color("#ffb547")
const GOOD := Color("#4ade80")
const BAD := Color("#ff7b93")
const MAP_BG := Color("#03050b")
const FONT := "res://assets/fonts/DejaVuSans.ttf"
const FONT_BOLD := "res://assets/fonts/DejaVuSans-Bold.ttf"
const THEME_PATH := "res://ui/theme.tres"


static func box(bg: Color, border: Color = Color.TRANSPARENT, radius: int = 10, pad: int = 10, border_w: int = 1) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w if border.a > 0.0 else 0)
	s.set_corner_radius_all(radius)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.7
	s.content_margin_bottom = pad * 0.7
	s.anti_aliasing = true
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	var font := load(FONT) as FontFile
	var bold := load(FONT_BOLD) as FontFile
	t.default_font = font
	t.default_font_size = 14
	t.set_color("font_color", "Label", FG)
	# Painikkeet: reunallinen tumma (sky-btn)
	for state in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		var bg := BG
		var border := LINE
		match state:
			"hover", "hover_pressed": bg = RAISED
			"pressed": bg = RAISED; border = MUTED
			"focus": bg = Color.TRANSPARENT; border = ACCENT
			"disabled": bg = BG.lerp(CARD, 0.5)
		var sb := box(bg, border, 8, 10)
		if state == "focus":
			sb.draw_center = false
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", FG)
	t.set_color("font_hover_color", "Button", FG)
	t.set_color("font_pressed_color", "Button", FG)
	t.set_color("font_hover_pressed_color", "Button", FG)
	t.set_color("font_focus_color", "Button", FG)
	t.set_color("font_disabled_color", "Button", MUTED.darkened(0.3))
	t.set_font_size("font_size", "Button", 13)
	# Päätoiminto (voyage-go): korostusvärinen
	t.set_type_variation("GoButton", "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var c := ACCENT
		if state == "hover" or state == "hover_pressed":
			c = ACCENT.lightened(0.15)
		elif state == "pressed":
			c = ACCENT.darkened(0.15)
		elif state == "disabled":
			c = ACCENT.darkened(0.6)
		t.set_stylebox(state, "GoButton", box(c, Color.TRANSPARENT, 10, 14))
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		t.set_color(k, "GoButton", Color("#04121a"))
	t.set_font("font", "GoButton", bold)
	t.set_font_size("font_size", "GoButton", 15)
	# Valintaryhmän painike (seg)
	t.set_type_variation("SegButton", "Button")
	t.set_stylebox("normal", "SegButton", box(Color.TRANSPARENT, Color.TRANSPARENT, 7, 4))
	t.set_stylebox("hover", "SegButton", box(RAISED.darkened(0.3), Color.TRANSPARENT, 7, 4))
	t.set_stylebox("pressed", "SegButton", box(RAISED, Color.TRANSPARENT, 7, 4))
	t.set_stylebox("hover_pressed", "SegButton", box(RAISED, Color.TRANSPARENT, 7, 4))
	t.set_stylebox("disabled", "SegButton", box(Color.TRANSPARENT, Color.TRANSPARENT, 7, 4))
	t.set_color("font_color", "SegButton", MUTED)
	t.set_color("font_hover_color", "SegButton", FG)
	t.set_color("font_pressed_color", "SegButton", FG)
	t.set_color("font_hover_pressed_color", "SegButton", FG)
	t.set_color("font_disabled_color", "SegButton", MUTED.darkened(0.5))
	t.set_font_size("font_size", "SegButton", 12)
	t.set_type_variation("Seg", "PanelContainer")
	t.set_stylebox("panel", "Seg", box(BG, LINE, 10, 3))
	# Kortit ja mittarit
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", box(CARD, LINE, 12, 14))
	t.set_type_variation("Stat", "PanelContainer")
	t.set_stylebox("panel", "Stat", box(CARD, LINE, 10, 10))
	t.set_type_variation("TopBar", "PanelContainer")
	var top := box(CARD, Color.TRANSPARENT, 0, 16)
	t.set_stylebox("panel", "TopBar", top)
	t.set_type_variation("Overlay", "PanelContainer")
	t.set_stylebox("panel", "Overlay", box(Color(BG, 0.8), LINE, 8, 4))
	t.set_stylebox("panel", "PanelContainer", box(BG, Color.TRANSPARENT, 0, 0))
	t.set_stylebox("panel", "Panel", box(BG, Color.TRANSPARENT, 0, 0))
	# Tekstit
	for v: Array in [["MutedLabel", MUTED, 13, font], ["TitleLabel", FG, 15, bold], ["BigLabel", FG, 26, bold],
			["HeadLabel", FG, 16, bold], ["WarnLabel", BAD, 13, font], ["AccentLabel", ACCENT, 13, bold], ["WarmLabel", WARM, 13, bold],
			["GoodLabel", GOOD, 13, bold], ["BrandLabel", FG, 18, bold]]:
		t.set_type_variation(v[0], "Label")
		t.set_color("font_color", v[0], v[1])
		t.set_font_size("font_size", v[0], v[2])
		t.set_font("font", v[0], v[3])
	t.set_font("normal_font", "RichTextLabel", font)
	t.set_font("bold_font", "RichTextLabel", bold)
	t.set_color("default_color", "RichTextLabel", FG)
	# Edistymispalkki
	t.set_stylebox("background", "ProgressBar", box(LINE, Color.TRANSPARENT, 3, 0))
	t.set_stylebox("fill", "ProgressBar", box(ACCENT, Color.TRANSPARENT, 3, 0))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 8)
	# Vierityspalkki ja dialogit
	t.set_stylebox("scroll", "VScrollBar", box(Color.TRANSPARENT, Color.TRANSPARENT, 4, 0))
	t.set_stylebox("grabber", "VScrollBar", box(LINE, Color.TRANSPARENT, 4, 3))
	t.set_stylebox("grabber_highlight", "VScrollBar", box(MUTED.darkened(0.4), Color.TRANSPARENT, 4, 3))
	t.set_stylebox("grabber_pressed", "VScrollBar", box(MUTED, Color.TRANSPARENT, 4, 3))
	t.set_stylebox("panel", "AcceptDialog", box(CARD, LINE, 16, 18))
	t.set_stylebox("panel", "ConfirmationDialog", box(CARD, LINE, 16, 18))
	t.set_stylebox("embedded_border", "Window", box(CARD, LINE, 16, 0))
	t.set_stylebox("embedded_unfocused_border", "Window", box(CARD, LINE, 16, 0))
	t.set_color("title_color", "Window", FG)
	t.set_font("title_font", "Window", bold)
	t.set_color("font_color", "TooltipLabel", FG)
	t.set_stylebox("panel", "TooltipPanel", box(RAISED, LINE, 6, 8))
	return t


static func theme() -> Theme:
	if ResourceLoader.exists(THEME_PATH):
		return load(THEME_PATH)
	return make_theme()


# --- Rakennuspalikat ---

static func label(text: String, variation: String = "", wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 40
	return l


static func button(text: String, on_press: Callable, variation: String = "") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(on_press)
	b.custom_minimum_size.y = 34 if variation != "GoButton" else 44
	return b


static func vbox(sep: int = 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	return v


static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	return h


## Kortti (voyage-info / voyage-option): paneeli, jonka sisällä pystylaatikko. Palauttaa [paneeli, sisältö].
static func card(variation: String = "Card") -> Array:
	var p := PanelContainer.new()
	p.theme_type_variation = variation
	var v := vbox(6)
	p.add_child(v)
	return [p, v]


## Rivit nimi–arvo kahdessa sarakkeessa.
static func rows(items: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 12)
	g.add_theme_constant_override("v_separation", 4)
	for r: Array in items:
		var k := label(String(r[0]), "MutedLabel", false)
		k.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		g.add_child(k)
		var v := label(String(r[1]))
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		g.add_child(v)
	return g


## Valintaryhmä: painikkeet vierekkäin, valittu korostettuna. items: [[arvo, nimi], ...].
## compact: tekstit saavat lyhentyä kapeassa paneelissa; columns > 0: ruudukko (esim. kaksi riviä).
static func seg(items: Array, value: Variant, pick: Callable, compact: bool = false, columns: int = 0) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Seg"
	var h: Container
	if columns > 0:
		var g := GridContainer.new()
		g.columns = columns
		g.add_theme_constant_override("h_separation", 2)
		g.add_theme_constant_override("v_separation", 2)
		h = g
	else:
		h = hbox(2)
	p.add_child(h)
	for it: Array in items:
		var b := Button.new()
		b.text = String(it[1])
		b.theme_type_variation = "SegButton"
		b.toggle_mode = true
		b.button_pressed = it[0] == value
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 32
		if compact:
			b.custom_minimum_size.x = 24
			b.clip_text = true
			b.tooltip_text = String(it[1])
		var v: Variant = it[0]
		b.pressed.connect(func() -> void: pick.call(v))
		h.add_child(b)
	return p


static func progress(value: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.step = 0.0
	bar.value = value
	bar.show_percentage = false
	bar.custom_minimum_size.y = 6
	return bar


## Mittari: otsikko, arvo ja lisärivi. Palauttaa [paneeli, arvo, lisärivi].
static func stat(title: String, value: String = "", sub: String = "") -> Array:
	var c := card("Stat")
	var v: VBoxContainer = c[1]
	v.add_theme_constant_override("separation", 2)
	v.add_child(label(title, "MutedLabel"))
	var val := label(value, "TitleLabel")
	v.add_child(val)
	var s := label(sub, "MutedLabel")
	s.visible = sub != ""
	v.add_child(s)
	return [c[0], val, s]
