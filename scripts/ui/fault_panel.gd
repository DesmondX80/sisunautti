class_name FaultPanel
extends Control
## Aluksen vika (#42) pelinäkymän päällä: hälytyskortti (vian nimi, ajastin, ohje) ja minipeli. Kortin voi piilottaa,
## jolloin yläreunassa on vilkkuva hälytysbanneri, josta kortti avautuu uudelleen. Minipelit piirretään itse:
## johdotus (WiresGame), koodi (CodeGame) ja venttiilit (ValvesGame). Toiminnot menevät Game.fault_*-funktioille.

const RED := Color("#ff4d5e")
const DEEP := Color("#2a0710")

var _card: PanelContainer
var _kind_label: Label
var _title: Label
var _timer: Label
var _bar: Control
var _help: Label
var _game_box: Control
var _game: Control = null
var _mistakes: Label
var _banner: Button
var _hidden := false
var _kind := ""
var _shake := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", UiKit.box(Color(0.05, 0.02, 0.04, 0.96), Color(RED, 0.8), 14, 18, 2))
	add_child(_card)
	var v := UiKit.vbox(10)
	_card.add_child(v)
	var head := UiKit.hbox(12)
	v.add_child(head)
	var left := UiKit.vbox(2)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(left)
	_kind_label = UiKit.label("", "", false)
	_kind_label.add_theme_color_override("font_color", RED)
	_kind_label.add_theme_font_override("font", load(UiKit.FONT_BOLD))
	left.add_child(_kind_label)
	_title = UiKit.label("", "TitleLabel")
	_title.add_theme_font_size_override("font_size", 22)
	left.add_child(_title)
	_timer = UiKit.label("", "", false)
	_timer.add_theme_font_override("font", load(UiKit.FONT_BOLD))
	_timer.add_theme_font_size_override("font_size", 34)
	_timer.add_theme_color_override("font_color", UiKit.FG)
	_timer.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_timer)
	_bar = Control.new()
	_bar.custom_minimum_size.y = 8
	_bar.draw.connect(_draw_bar)
	v.add_child(_bar)
	_help = UiKit.label("", "MutedLabel")
	v.add_child(_help)
	_game_box = Control.new()
	_game_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_game_box.custom_minimum_size.y = 300
	_game_box.resized.connect(func() -> void:
		if _game != null:
			_game.size = _game_box.size)
	v.add_child(_game_box)
	var foot := UiKit.hbox(10)
	v.add_child(foot)
	_mistakes = UiKit.label("", "MutedLabel")
	_mistakes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(_mistakes)
	var hide := UiKit.button("Piilota", func() -> void:
		_hidden = true
		_sync())
	hide.tooltip_text = "Piilota korjausikkuna (aika kuluu silti)"
	foot.add_child(hide)
	_banner = UiKit.button("", func() -> void:
		_hidden = false
		_sync())
	_banner.add_theme_stylebox_override("normal", UiKit.box(Color(DEEP, 0.95), RED, 18, 14, 2))
	_banner.add_theme_stylebox_override("hover", UiKit.box(Color(0.3, 0.05, 0.1, 0.95), RED, 18, 14, 2))
	_banner.add_theme_color_override("font_color", Color("#ffd6dc"))
	add_child(_banner)
	Game.fault_started.connect(func(_k: String) -> void: _hidden = false)
	Game.fault_mistake.connect(func(_k: String) -> void: _shake = 1.0)
	resized.connect(_place)
	_sync()


## Kortin ja bannerin paikka: kortti keskellä (kapeassa ikkunassa koko leveys), banneri yläreunassa.
func _place() -> void:
	# Kiinteä koko: automaattisesti rivittyvien tekstien vähimmäiskorkeus on ennen asettelua harhaanjohtava.
	var w := minf(size.x - 24.0, 780.0)
	var h := minf(size.y - 24.0, 600.0)
	_card.custom_minimum_size = Vector2(w, h)
	_title.add_theme_font_size_override("font_size", 22 if w > 520.0 else 17)
	_timer.add_theme_font_size_override("font_size", 34 if w > 520.0 else 28)
	_card.size = Vector2(w, h)
	_card.position = ((size - _card.size) / 2.0).floor() + Vector2(randf() - 0.5, randf() - 0.5) * 10.0 * _shake
	_banner.reset_size()
	_banner.position = Vector2(((size.x - _banner.size.x) / 2.0), 64.0).floor()


func _sync() -> void:
	var f: Variant = Game.state.get("fault") if not Game.state.is_empty() else null
	visible = f != null
	if f == null:
		_kind = ""
		if _game != null:
			_game.queue_free()
			_game = null
		return
	if String(f.kind) != _kind:
		_kind = String(f.kind)
		var info: Dictionary = Faults.INFO[_kind]
		_kind_label.text = "⚠  VIKA · %s" % String(info.name).to_upper()
		_title.text = info.title
		_help.text = info.help
		if _game != null:
			_game.queue_free()
		match _kind:
			"johdot": _game = WiresGame.new()
			"koodi": _game = CodeGame.new()
			_: _game = ValvesGame.new()
		_game_box.add_child(_game)
		_game.size = _game_box.size
	_card.visible = not _hidden
	_banner.visible = _hidden
	mouse_filter = Control.MOUSE_FILTER_STOP if not _hidden else Control.MOUSE_FILTER_IGNORE
	_place()


func _process(delta: float) -> void:
	var f: Variant = Game.state.get("fault") if not Game.state.is_empty() else null
	if (f != null) != visible or (f != null and String(f.kind) != _kind) or (f != null and _card.visible == _hidden):
		_sync()
	if f == null:
		return
	var left := maxf(0.0, float(f.remaining)) / 1000.0
	var urgent := left < 20.0
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5
	_timer.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
	_timer.add_theme_color_override("font_color", RED if urgent and blink else UiKit.FG)
	_mistakes.text = "Virheitä %d · jokainen vie %d s" % [int(f.mistakes), roundi(Faults.PENALTY_MS / 1000.0)] if int(f.mistakes) > 0 \
		else "Väärä yritys vie %d s." % roundi(Faults.PENALTY_MS / 1000.0)
	_banner.text = "⚠  %s  %s  ·  Korjaa" % [String(Faults.INFO[_kind].name).to_upper(), _timer.text]
	var pulse := 0.55 + 0.45 * sin(Time.get_ticks_msec() / 1000.0 * (9.0 if urgent else 4.0))
	(_card.get_theme_stylebox("panel") as StyleBoxFlat).border_color = Color(RED, 0.45 + 0.55 * pulse)
	_banner.modulate = Color(1, 1, 1, 0.75 + 0.25 * pulse)
	_shake = maxf(0.0, _shake - delta * 3.0)
	_place()
	_bar.queue_redraw()
	queue_redraw()


func _draw() -> void:
	if _hidden:
		return
	# Himmennys ja punainen hälytyshehku reunoilla.
	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 1000.0 * 4.0)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.02, 0.55))
	var edge := Color(RED, 0.10 + 0.12 * pulse)
	for i in 6:
		var k := 1.0 - i / 6.0
		var m := 18.0 * i
		draw_rect(Rect2(Vector2(m, m), size - Vector2(m, m) * 2.0), Color(edge, edge.a * k * 0.5), false, 18.0)


func _draw_bar() -> void:
	var f: Variant = Game.state.get("fault")
	if f == null:
		return
	var k := clampf(float(f.remaining) / float(f.total), 0.0, 1.0)
	var w := _bar.size.x
	_bar.draw_rect(Rect2(0, 0, w, 8), Color(1, 1, 1, 0.08))
	var col := UiKit.WARM.lerp(RED, clampf(1.0 - k * 2.0, 0.0, 1.0)) if k < 0.5 else UiKit.GOOD.lerp(UiKit.WARM, (1.0 - k) * 2.0)
	_bar.draw_rect(Rect2(0, 0, w * k, 8), col)
	_bar.draw_rect(Rect2(w * k - 3.0, 0, 3.0, 8), Color(1, 1, 1, 0.8))


# --- Johdotus ---

class WiresGame:
	extends Control
	var _drag := -1 # vedettävä johto (vasen indeksi) tai −1
	var _pick := -1 # napautettu johto
	var _mouse := Vector2.ZERO
	var _moved := 0.0
	var _sparks: Array = [] # [kohta, alkuhetki]
	var _fail_at := -10000

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		Game.fault_mistake.connect(_on_mistake)

	func _on_mistake(_k: String) -> void:
		_fail_at = Time.get_ticks_msec()

	func _fault() -> Variant:
		return Game.state.get("fault")

	func _pos(left: bool, i: int, n: int) -> Vector2:
		var top := 34.0
		var h := size.y - top - 18.0
		var y := top + h * (i + 0.5) / n
		return Vector2(70.0 if left else size.x - 96.0, y)

	func _linked(f: Dictionary, left: bool, i: int) -> int:
		for link: Array in f.links:
			if int(link[0 if left else 1]) == i:
				return int(link[1 if left else 0])
		return -1

	func _at(left: bool, p: Vector2, n: int) -> int:
		for i in n:
			if p.distance_to(_pos(left, i, n)) < 34.0:
				return i
		return -1

	func _gui_input(e: InputEvent) -> void:
		var f: Variant = _fault()
		if f == null or f.kind != "johdot":
			return
		var n: int = f.left.size()
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := e as InputEventMouseButton
			_mouse = mb.position
			if mb.pressed:
				var l := _at(true, mb.position, n)
				if l >= 0 and _linked(f, true, l) < 0:
					_drag = l
					_moved = 0.0
				elif _pick >= 0:
					_try(_pick, _at(false, mb.position, n))
					_pick = -1
			else:
				if _drag >= 0:
					var r := _at(false, mb.position, n)
					if r >= 0:
						_try(_drag, r)
					elif _moved < 10.0:
						_pick = _drag
					_drag = -1
			accept_event()
			queue_redraw()
		elif e is InputEventMouseMotion:
			_moved += (e as InputEventMouseMotion).relative.length()
			_mouse = (e as InputEventMouseMotion).position
			queue_redraw()

	func _try(l: int, r: int) -> void:
		var f: Dictionary = _fault()
		if r < 0 or _linked(f, false, r) >= 0:
			return
		var p := _pos(false, r, f.left.size())
		if not Game.fault_wire(l, r):
			_sparks.append([p, Time.get_ticks_msec()])

	func _process(_d: float) -> void:
		queue_redraw()

	func _cable(a: Vector2, b: Vector2, wire: Array, glow: float) -> void:
		var col: Color = wire[1]
		var stripe: Variant = wire[2]
		var pts := PackedVector2Array()
		var dx := (b.x - a.x) * 0.45
		for i in 33:
			var t := i / 32.0
			var u := 1.0 - t
			pts.append(a * u * u * u + (a + Vector2(dx, 0)) * 3.0 * u * u * t + (b - Vector2(dx, 0)) * 3.0 * u * t * t + b * t * t * t)
		if glow > 0.0:
			draw_polyline(pts, Color(col, 0.18 * glow), 22.0, true)
		draw_polyline(pts, col.darkened(0.55), 11.0, true)
		draw_polyline(pts, col, 8.0, true)
		if stripe != null:
			for i in range(0, 32, 4):
				draw_line(pts[i], pts[i + 2], stripe, 8.0, true)
		draw_polyline(pts, Color(1, 1, 1, 0.35), 2.0, true)

	func _draw() -> void:
		var f: Variant = _fault()
		if f == null or f.kind != "johdot":
			return
		var n: int = f.left.size()
		var mono: Font = load(UiKit.FONT)
		# Paneelin pohja: tumma metalli, ruudukko ja otsikot.
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.07))
		for x in range(0, int(size.x), 24):
			draw_line(Vector2(x, 0), Vector2(x, size.y), Color(UiKit.ACCENT, 0.035))
		for y in range(0, int(size.y), 24):
			draw_line(Vector2(0, y), Vector2(size.x, y), Color(UiKit.ACCENT, 0.035))
		draw_string(mono, Vector2(20, 22), "VIRTALÄHDE", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.MUTED)
		draw_string(mono, Vector2(size.x - 20.0 - mono.get_string_size("JAKOTAULU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, 22), "JAKOTAULU", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, UiKit.MUTED)
		var fail := clampf(1.0 - (Time.get_ticks_msec() - _fail_at) / 400.0, 0.0, 1.0)
		if fail > 0.0:
			draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.2, 0.25, 0.18 * fail))
		# Liittimet: vasemmalla johtojen päät, oikealla värikoodatut liitännät.
		for i in n:
			var lw: Array = Faults.WIRES[int(f.left[i])]
			var rw: Array = Faults.WIRES[int(f.right[i])]
			var a := _pos(true, i, n)
			var b := _pos(false, i, n)
			draw_line(Vector2(0, a.y), a, Color(lw[1], 0.9), 10.0)
			draw_circle(a, 15.0, Color(0.12, 0.13, 0.16))
			draw_circle(a, 15.0, lw[1], false, 3.0, true)
			draw_circle(a, 6.0, lw[1])
			if lw[2] != null:
				draw_line(Vector2(6, a.y), a - Vector2(18, 0), lw[2], 4.0)
				draw_arc(a, 10.0, 0, PI, 16, lw[2], 3.0, true)
			draw_string(mono, a + Vector2(-62, -12), lw[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.MUTED)
			var on := _linked(f, false, i) >= 0
			draw_rect(Rect2(b + Vector2(-4, -16), Vector2(88, 32)), Color(0.1, 0.11, 0.14))
			draw_line(b + Vector2(84, 0), Vector2(size.x, b.y), Color(rw[1], 0.5), 6.0)
			draw_circle(b, 15.0, Color(0.06, 0.07, 0.09))
			draw_circle(b, 15.0, rw[1], false, 3.0, true)
			if rw[2] != null:
				draw_arc(b, 10.0, 0, PI, 16, rw[2], 3.0, true)
			draw_circle(b + Vector2(34, 0), 5.0, Color(UiKit.GOOD, 1.0 if on else 0.15))
			draw_string(mono, b + Vector2(44, 5), rw[3], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UiKit.MUTED)
			if i == _pick:
				draw_circle(a, 22.0 + 3.0 * sin(Time.get_ticks_msec() / 120.0), Color(UiKit.ACCENT, 0.9), false, 2.0, true)
		# Kytketyt johdot ja vedettävä johto.
		for link: Array in f.links:
			_cable(_pos(true, int(link[0]), n), _pos(false, int(link[1]), n), Faults.WIRES[int(f.left[int(link[0])])], 1.0)
		if _drag >= 0:
			_cable(_pos(true, _drag, n), _mouse, Faults.WIRES[int(f.left[_drag])], 0.6)
		# Kipinät väärästä kytkennästä.
		var now := Time.get_ticks_msec()
		for s: Array in _sparks:
			var age := (now - int(s[1])) / 500.0
			if age < 1.0:
				for k in 10:
					var ang := k * 2.4 + float(s[1]) * 0.01
					var d := Vector2(cos(ang), sin(ang)) * (10.0 + 40.0 * age)
					draw_line(s[0] + d * 0.6, s[0] + d, Color(1.0, 0.85, 0.4, 1.0 - age), 2.0)
				draw_circle(s[0], 20.0 * (1.0 - age), Color(1.0, 0.9, 0.6, 0.6 * (1.0 - age)))
		_sparks = _sparks.filter(func(s: Array) -> bool: return now - int(s[1]) < 500)


# --- Koodi ---

class CodeGame:
	extends Control
	const KEYWORDS := ["func", "var", "const", "return", "if", "for", "in", "and", "or", "not"]
	var _hover := -1
	var _fail_row := -1
	var _fail_at := -10000
	var _opts: VBoxContainer
	var _shown_line := -2

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		_opts = UiKit.vbox(6)
		add_child(_opts)
		Game.fault_mistake.connect(_on_mistake)

	func _on_mistake(_k: String) -> void:
		_fail_at = Time.get_ticks_msec()

	func _row_h() -> float:
		return 26.0

	func _top() -> float:
		return 40.0

	func _gui_input(e: InputEvent) -> void:
		var f: Variant = Game.state.get("fault")
		if f == null or f.kind != "koodi":
			return
		var c := Faults.code_of(f)
		if e is InputEventMouseMotion:
			var r := int(floor(((e as InputEventMouseMotion).position.y - _top()) / _row_h()))
			_hover = r if r >= 0 and r < c.lines.size() else -1
			queue_redraw()
		elif e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var r := int(floor(((e as InputEventMouseButton).position.y - _top()) / _row_h()))
			if r >= 0 and r < c.lines.size() and int(f.line) < 0:
				if not Game.fault_code_line(r):
					_fail_row = r
			accept_event()
			queue_redraw()

	func _process(_d: float) -> void:
		var f: Variant = Game.state.get("fault")
		if f == null or f.kind != "koodi":
			return
		if int(f.line) != _shown_line:
			_shown_line = int(f.line)
			for ch in _opts.get_children():
				ch.queue_free()
			if _shown_line >= 0:
				var c := Faults.code_of(f)
				_opts.add_child(UiKit.label("Valitse korjaus riville %d:" % (_shown_line + 1), "MutedLabel"))
				for i in c.options.size():
					var idx: int = i
					var b := UiKit.button(String(c.options[i]).strip_edges(), func() -> void: Game.fault_code_fix(idx))
					b.alignment = HORIZONTAL_ALIGNMENT_LEFT
					b.add_theme_font_override("font", load(UiKit.FONT))
					_opts.add_child(b)
		var c := Faults.code_of(f)
		_opts.position = Vector2(0, _top() + _row_h() * c.lines.size() + 14.0)
		_opts.size.x = size.x
		queue_redraw()

	func _draw() -> void:
		var f: Variant = Game.state.get("fault")
		if f == null or f.kind != "koodi":
			return
		var c := Faults.code_of(f)
		var mono: Font = load(UiKit.FONT)
		# Fonttikoko niin, että pisin rivi mahtuu (puhelimessa pienempi).
		var longest := 1.0
		for l: String in c.lines:
			longest = maxf(longest, mono.get_string_size(l.replace("\t", "    "), HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x)
		var fs := clampi(int(15.0 * (size.x - 54.0) / longest), 9, 15)
		var code_h: float = _row_h() * c.lines.size() + 12.0
		draw_rect(Rect2(0, 0, size.x, 30), Color(0.25, 0.04, 0.08, 0.8))
		var err := "VIRHE: %s · %s" % [c.title.to_lower(), c.symptom]
		var efs := clampi(int(13.0 * (size.x - 20.0) / maxf(1.0, mono.get_string_size(err, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x)), 9, 13)
		draw_string(mono, Vector2(10, 20), err, HORIZONTAL_ALIGNMENT_LEFT, size.x - 20.0, efs, Color("#ffb3bd"))
		draw_rect(Rect2(0, _top() - 6.0, size.x, code_h), Color(0.02, 0.03, 0.06))
		var blink := fmod(Time.get_ticks_msec() / 1000.0, 1.0) < 0.5
		var fail := clampf(1.0 - (Time.get_ticks_msec() - _fail_at) / 600.0, 0.0, 1.0)
		for i in c.lines.size():
			var y: float = _top() + i * _row_h()
			if i == int(f.line):
				draw_rect(Rect2(0, y - 3.0, size.x, _row_h()), Color(UiKit.WARM, 0.22))
			elif i == _fail_row and fail > 0.0:
				draw_rect(Rect2(0, y - 3.0, size.x, _row_h()), Color(1.0, 0.25, 0.3, 0.35 * fail))
			elif i == _hover and int(f.line) < 0:
				draw_rect(Rect2(0, y - 3.0, size.x, _row_h()), Color(UiKit.ACCENT, 0.12))
			draw_string(mono, Vector2(8, y + 15), "%2d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.MUTED, 0.6))
			_code_line(mono, String(c.lines[i]), Vector2(44, y + 15), fs)
		if int(f.line) < 0 and blink:
			draw_rect(Rect2(44, _top() + c.lines.size() * _row_h() - 4.0, 9, 2), UiKit.ACCENT)

	## Rivi syntaksivärein: avainsanat, luvut, kommentit ja tavalliset sanat.
	func _code_line(font: Font, line: String, at: Vector2, fs: int) -> void:
		var x := at.x
		var text := line.replace("\t", "    ")
		var comment := text.find("#")
		var parts: Array = []
		var word := ""
		var i := 0
		while i < text.length():
			if comment >= 0 and i == comment:
				if word != "":
					parts.append(word)
					word = ""
				parts.append(text.substr(i))
				break
			var ch := text[i]
			if ch.is_valid_identifier() or ch.is_valid_int() or ch == "." or ch == "_" or (ch >= "a" and ch <= "ö"):
				word += ch
			else:
				if word != "":
					parts.append(word)
					word = ""
				parts.append(ch)
			i += 1
		if word != "":
			parts.append(word)
		for p: String in parts:
			var col := Color("#d6e2ff")
			if p.begins_with("#"):
				col = Color("#6b7a99")
			elif p in KEYWORDS:
				col = Color("#c792ea")
			elif p.is_valid_float():
				col = Color("#ffb547")
			elif p in ["float", "int", "bool", "Array", "Vector3", "INF", "PI"]:
				col = Color("#5ed6ff")
			draw_string(font, Vector2(x, at.y), p, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
			x += font.get_string_size(p, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


# --- Venttiilit ---

class ValvesGame:
	extends Control
	var _shown := [0.0, 0.0, 0.0] # mittarien näytetyt arvot (pehmennetty)
	var _spin := [0.0, 0.0, 0.0, 0.0]

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		var f: Variant = Game.state.get("fault")
		if f != null and f.kind == "paine":
			var p := Faults.pressures(f)
			for g in Faults.GAUGES:
				_shown[g] = float(p[g])

	func _gauge_rect(g: int) -> Rect2:
		var w := minf(70.0, size.x / 8.0)
		var gap := size.x / (Faults.GAUGES + 1)
		var h := size.y * 0.52
		return Rect2(gap * (g + 1) - w / 2.0, 30.0, w, h)

	func _valve_pos(v: int) -> Vector2:
		var gap := size.x / (Faults.VALVES + 1)
		return Vector2(gap * (v + 1), size.y - 46.0)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			for v in Faults.VALVES:
				if (e as InputEventMouseButton).position.distance_to(_valve_pos(v)) < 34.0:
					Game.fault_valve(v)
					accept_event()
					return

	func _process(delta: float) -> void:
		var f: Variant = Game.state.get("fault")
		if f == null or f.kind != "paine":
			return
		var p := Faults.pressures(f)
		for g in Faults.GAUGES:
			_shown[g] = lerpf(_shown[g], float(p[g]), minf(1.0, delta * 6.0))
		for v in Faults.VALVES:
			_spin[v] = lerpf(_spin[v], PI * 0.75 if f.valves[v] else 0.0, minf(1.0, delta * 8.0))
		queue_redraw()

	func _draw() -> void:
		var f: Variant = Game.state.get("fault")
		if f == null or f.kind != "paine":
			return
		var mono: Font = load(UiKit.FONT)
		var bold: Font = load(UiKit.FONT_BOLD)
		var t := Time.get_ticks_msec() / 1000.0
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.04, 0.07))
		# Putket venttiileiltä mittareille, joihin ne vaikuttavat.
		for v in Faults.VALVES:
			var vp := _valve_pos(v)
			for g in Faults.GAUGES:
				if int(f.effects[v][g]) != 0:
					var gr := _gauge_rect(g)
					var top := Vector2(gr.get_center().x + (v - 1.5) * 8.0, gr.end.y)
					var mid_y := lerpf(top.y, vp.y, 0.5) + (v - 1.5) * 6.0
					var col := Color(UiKit.ACCENT, 0.5 if f.valves[v] else 0.16)
					draw_polyline(PackedVector2Array([vp - Vector2(0, 26), Vector2(vp.x, mid_y), Vector2(top.x, mid_y), top]), col, 4.0 if f.valves[v] else 3.0)
					if f.valves[v]:
						var k := fmod(t * 0.8 + v * 0.3, 1.0)
						draw_circle(Vector2(vp.x, lerpf(vp.y - 26.0, mid_y, k)), 3.0, Color(UiKit.ACCENT, 0.9))
		# Mittarit: lasiputki, neste, vihreä alue ja asteikko.
		var labels := ["A", "B", "C"]
		for g in Faults.GAUGES:
			var r := _gauge_rect(g)
			var val: float = _shown[g]
			var ok := val >= Faults.GREEN[0] - 0.05 and val <= Faults.GREEN[1] + 0.05
			draw_rect(r.grow(4.0), Color(0.12, 0.13, 0.16))
			draw_rect(r, Color(0.02, 0.025, 0.04))
			var zy0 := r.end.y - r.size.y * (Faults.GREEN[1] + 0.5) / 11.0
			var zy1 := r.end.y - r.size.y * (Faults.GREEN[0] - 0.5) / 11.0
			draw_rect(Rect2(r.position.x, zy0, r.size.x, zy1 - zy0), Color(UiKit.GOOD, 0.16))
			var level := r.size.y * clampf((val + 0.5) / 11.0, 0.0, 1.0)
			var liquid := UiKit.GOOD if ok else (FaultPanel.RED if val > Faults.GREEN[1] else UiKit.WARM)
			draw_rect(Rect2(r.position.x + 4.0, r.end.y - level, r.size.x - 8.0, level), Color(liquid, 0.75))
			draw_rect(Rect2(r.position.x + 4.0, r.end.y - level, r.size.x - 8.0, 3.0), Color(1, 1, 1, 0.5))
			for b in 4:
				var bx := r.position.x + 10.0 + fmod(b * 17.0, r.size.x - 20.0)
				var by := r.end.y - fmod(t * 30.0 + b * 37.0, maxf(level - 6.0, 1.0)) - 4.0
				draw_circle(Vector2(bx, by), 2.0, Color(1, 1, 1, 0.35))
			for k in 11:
				var y := r.end.y - r.size.y * (k + 0.5) / 11.0
				draw_line(Vector2(r.end.x + 4.0, y), Vector2(r.end.x + (12.0 if k % 5 == 0 else 8.0), y), Color(UiKit.MUTED, 0.7), 1.0)
			draw_line(Vector2(r.position.x - 10.0, zy0), Vector2(r.end.x + 10.0, zy0), Color(UiKit.GOOD, 0.8), 2.0)
			draw_line(Vector2(r.position.x - 10.0, zy1), Vector2(r.end.x + 10.0, zy1), Color(UiKit.GOOD, 0.8), 2.0)
			draw_string(bold, Vector2(r.position.x - 30.0, r.position.y - 10.0), "PAINE %s" % labels[g], HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 60.0, 13, UiKit.MUTED)
			draw_string(bold, Vector2(r.position.x - 20.0, r.end.y + 26.0), "%d" % roundi(val), HORIZONTAL_ALIGNMENT_CENTER, r.size.x + 40.0, 22, liquid)
		# Venttiilit: käsipyörä, joka kääntyy auki.
		for v in Faults.VALVES:
			var p := _valve_pos(v)
			var open: bool = f.valves[v]
			var col := UiKit.GOOD if open else Color(0.75, 0.78, 0.85)
			draw_circle(p, 26.0, Color(0.1, 0.11, 0.14))
			draw_arc(p, 22.0, 0, TAU, 40, col, 4.0, true)
			for s in 4:
				var a: float = _spin[v] + s * PI / 2.0
				draw_line(p, p + Vector2(cos(a), sin(a)) * 20.0, col, 3.0, true)
			draw_circle(p, 6.0, col)
			draw_string(mono, p + Vector2(-30, 44), "V%d %s" % [v + 1, "AUKI" if open else "KIINNI"], HORIZONTAL_ALIGNMENT_CENTER, 60, 11, col)
