class_name CockpitScreen
extends Control
## Ohjaamon näytön sisältö SubViewportissa. Sisältö piirretään 1024 × 576 -alueelle, joka skaalataan näytön
## muotoon (view_size) keskelle; tausta ja kehykset täyttävät koko näytön. Hologrammityyli: tummansininen pohja, ruudukko, syaanit
## viivat ja kulmakehykset. Näyttö piirretään uudelleen enintään 20 kertaa sekunnissa (tick), ja SubViewport
## päivitetään vain silloin (UPDATE_ONCE). Tyypit:
##   "nav"      tutka: aurinkokunta ylhäältä, alus, kohde ja lähimmät planeetat
##   "ship"     aluskaavio polttoaineineen ja moottorin liekkeineen sekä päänäytön 1 rivit (aika, päivä, kiihdytys)
##   "target"   tähtäin ja työntö sekä päänäytön 2 rivit (nopeus)
##   "systems"  järjestelmät: etäisyydet planeetoille, mittarit, kohteen hologrammi ja tilarivit
##   "camera"   kohdekamera: kaukoputken kuva kohteesta aluksen paikalta (sama puoli ja valaistus kuin ikkunasta) ja
##              päänäytön 3 rivit (kohde, polttoaine); vaihdettavissa takakameraksi tai 360°-kameraksi (set_feed)
##   "mini"     keskikonsolin pikkunäyttö: aikakiihdytys ja moottori

const SIZE := Vector2(1024, 576)
const ACCENT := Color("#5ed6ff")
const BRIGHT := Color("#d4f4ff")
const DIM := Color(0.37, 0.84, 1.0, 0.22)
const MUTED := Color("#8b9ac0")
const FG := Color("#e8eefc")
const GOOD := Color("#4ade80")
const BAD := Color("#ff7b93")
const WARM := Color("#ffb547")
const BG_TOP := Color("#04163a")
const BG_BOTTOM := Color("#0a2c5e")
## Planeettojen lyhenteet etäisyyspylväisiin.
const SHORT := {"Merkurius": "ME", "Venus": "VE", "Maa": "MA", "Mars": "MR", "Jupiter": "JU", "Saturnus": "SA", "Uranus": "UR", "Neptunus": "NE"}
const REDRAW_MS := 50
## Kohdekameran kohteen keskikohta näytöllä (x, sisältöalueen koordinaateissa; y keskellä).
const TELE_X := 720.0

var kind := "nav"
var view_size := SIZE # SubViewportin koko
var _k := 1.0 # sisällön mittakaava
var _off := Vector2.ZERO # sisällön siirtymä
var title := ""
var rows: Array = []
var bar: Variant = null
var data: Dictionary = {} # muut tiedot: t, ship, aim, fuel, thrust, warp, engine
var font: Font
var mono: Font
var globe: ColorRect = null
var globe_mat: ShaderMaterial = null
var over: Control # päällyskerros pallon päällä
var rear: TextureRect = null # ulkokameran kuva (kohdekameranäytöllä)
## Kameran tila: "kohde" kohdekamera, "taka" takakamera, "360" kääntyvä kamera ("" = ei kuvaa, pallo).
var feed := ""
## Kohdekameran zoom (suhteessa ikkunanäkymään, 0 = lähinäkymä) ja kohteen säde kuvassa (osuus kuvan korkeudesta).
var tele := Vector2(1, 0)
## Kohdekameran lähinäkymä (set_close): kohde suunnattuna pallona, aluksen kohta keskellä; tele_label alareunaan.
var close := false
var tele_label := ""
const GLOBE_MARGIN := 1.18
## 360°-kameran suunta: x = suuntima (rad, myötäpäivään keulasta), y = kallistus (rad), z = zoomauskerroin.
var pan := Vector3(0, 0, 1)
var _globe_name := ""
var _drawn_at := -100000


func _ready() -> void:
	font = load(UiKit.FONT_BOLD)
	mono = load(UiKit.FONT)
	size = view_size
	_k = minf(view_size.x / SIZE.x, view_size.y / SIZE.y)
	_off = (view_size - SIZE * _k) / 2.0
	if kind == "camera" or kind == "systems":
		globe = ColorRect.new()
		globe_mat = ShaderMaterial.new()
		globe_mat.shader = load("res://shaders/globe.gdshader")
		globe.material = globe_mat
		if kind == "camera":
			# Lähinäkymän pallo kohdekameran kohteen paikalla ja koossa (TELE_X, säde 0,34 kuvan korkeudesta).
			var gr := 0.34 * SIZE.y * GLOBE_MARGIN
			globe.position = _off + (Vector2(TELE_X, SIZE.y / 2.0) - Vector2(gr, gr)) * _k
			globe.size = Vector2(gr, gr) * 2.0 * _k
			globe_mat.set_shader_parameter("spin", 0.004)
			globe_mat.set_shader_parameter("margin", GLOBE_MARGIN)
		else:
			globe.position = _off + Vector2(640, 92) * _k
			globe.size = Vector2(300, 300) * _k
			globe_mat.set_shader_parameter("holo", 1.0)
			globe_mat.set_shader_parameter("spin", 0.03)
		add_child(globe)
	if kind == "camera":
		rear = TextureRect.new()
		rear.size = view_size
		rear.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rear.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/rear_camera.gdshader")
		mat.set_shader_parameter("aspect", view_size.x / view_size.y)
		rear.material = mat
		rear.visible = false
		add_child(rear)
	over = Control.new()
	over.size = view_size
	over.mouse_filter = Control.MOUSE_FILTER_IGNORE
	over.draw.connect(_draw_over)
	add_child(over)


## Päänäytön tiedot: otsikko, rivit [[teksti, koko, väri?], ...] ja polttoainepalkki (0–1 tai null).
func set_main(p_title: String, p_rows: Array, p_bar: Variant) -> void:
	title = p_title
	rows = p_rows
	bar = p_bar


func set_data(d: Dictionary) -> void:
	data = d


## Pallon pinta: kappaleen nimi, pintakartta (tai null) ja perusväri. Aurinko hehkuu.
func set_globe(name: String, tex: Texture2D, color: Color) -> void:
	if globe_mat == null:
		return
	if name != _globe_name or globe_mat.get_shader_parameter("tex") != tex:
		_globe_name = name
		globe_mat.set_shader_parameter("tex", tex)
		globe_mat.set_shader_parameter("has_tex", tex != null)
		globe_mat.set_shader_parameter("base_color", color)
		globe_mat.set_shader_parameter("sun", name == "Aurinko")


## Kohdekamera ulkokameraksi: tex on kameran kuva (SubViewportin tekstuuri) ja mode "taka" tai "360";
## null palauttaa kohdekameran.
func set_feed(tex: Texture2D, mode: String = "taka") -> void:
	if rear == null:
		return
	feed = mode if tex != null else ""
	close = false
	globe_mat.set_shader_parameter("oriented", false)
	rear.texture = tex
	rear.visible = tex != null
	globe.visible = tex == null
	(rear.material as ShaderMaterial).set_shader_parameter("grain", 0.3 if mode == "kohde" else 1.0)
	(rear.material as ShaderMaterial).set_shader_parameter("solar", 0.0)
	tick(true)


## Kohdekameran kohteen paikka kamerakuvassa (kuva peittää koko näytön): x, y normalisoituina (−1…1, y ylös) ja
## sisältöalueen korkeus osuutena näytön korkeudesta.
func tele_anchor() -> Vector3:
	var p := _off + Vector2(TELE_X, SIZE.y / 2.0) * _k
	return Vector3((p.x - view_size.x / 2.0) / (view_size.x / 2.0), -(p.y - view_size.y / 2.0) / (view_size.y / 2.0), SIZE.y * _k / view_size.y)


## Kohdekameran lähinäkymä päälle ja pois: params ovat globe-varjostimen suunnatun tilan arvot (view_to_body,
## light_dir, pilvet, yövalot, ilmakehä).
func set_close(on: bool, params: Dictionary = {}) -> void:
	if rear == null:
		return
	if on != close:
		close = on
		globe_mat.set_shader_parameter("oriented", on)
		rear.visible = not on and rear.texture != null
		globe.visible = on or rear.texture == null
		tick(true)
	for k: String in params:
		globe_mat.set_shader_parameter(k, params[k])


func is_rear() -> bool:
	return rear != null and rear.visible


## Piirtää näytön uudelleen, jos edellisestä on kulunut riittävästi aikaa (tai force). Palauttaa true, jos piirrettiin.
func tick(force: bool = false) -> bool:
	var now := Time.get_ticks_msec()
	if not force and now - _drawn_at < REDRAW_MS:
		return false
	_drawn_at = now
	queue_redraw()
	over.queue_redraw()
	var vp := get_viewport() as SubViewport
	if vp != null:
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	return true


func _draw() -> void:
	_background(self)
	draw_set_transform(_off, 0.0, Vector2(_k, _k))
	match kind:
		"nav": _draw_nav(self)
		"ship": _draw_ship(self)
		"target": _draw_target(self)
		"systems": _draw_systems(self)
		"mini": _draw_mini(self)


func _draw_over() -> void:
	over.draw_set_transform(_off, 0.0, Vector2(_k, _k))
	match kind:
		"camera": _draw_camera(over)
		"systems": _draw_systems_over(over)
	over.draw_set_transform(Vector2.ZERO)
	_frame(over)
	_draw_alert(over)


## Vian aikana (#42) näytön yläreunassa vilkkuu punainen VIKA-palkki ja kehys punertuu; tuhon jälkeen näytöillä on
## kohinaa ja teksti SIGNAALI KATKESI.
func _draw_alert(c: CanvasItem) -> void:
	if Game.state.is_empty():
		return
	var w := view_size.x
	var h := view_size.y
	if Game.state.get("destroyed") != null:
		var rng := RandomNumberGenerator.new()
		rng.seed = Time.get_ticks_msec() / 50
		c.draw_rect(Rect2(0, 0, w, h), Color(0.02, 0.02, 0.03, 0.92))
		for i in 260:
			var l := rng.randf()
			c.draw_rect(Rect2(rng.randf() * w, rng.randf() * h, rng.randf_range(2.0, 14.0), 2.0), Color(l, l, l, 0.35))
		var fs := roundi(minf(w / 14.0, h / 5.0))
		_center(c, font, "SIGNAALI KATKESI", w / 2.0, h / 2.0 + fs * 0.35, fs, BAD, w * 0.9)
		return
	var f: Variant = Game.state.get("fault")
	if f == null:
		return
	var on := fmod(Time.get_ticks_msec() / 600.0, 1.0) < 0.55
	var bar := clampf(h * 0.13, 24.0, 70.0)
	c.draw_rect(Rect2(0, 0, w, h), Color(1.0, 0.1, 0.15, 0.10 if on else 0.04))
	c.draw_rect(Rect2(10, 10, w - 20, h - 20), Color(BAD, 0.9 if on else 0.4), false, 4.0)
	c.draw_rect(Rect2(0, 0, w, bar), Color(0.35, 0.02, 0.06, 0.92))
	var left := maxf(0.0, float(f.remaining)) / 1000.0
	var text := "⚠ VIKA · %s · %d:%02d" % [String(Faults.INFO[String(f.kind)].name).to_upper(), int(left) / 60, int(left) % 60]
	_center(c, font, text, w / 2.0, bar * 0.68, roundi(bar * 0.5), Color("#ffd6dc") if on else BAD, w - 40.0)


# --- Yhteiset osat ---

func _background(c: CanvasItem) -> void:
	var w := view_size.x
	var h := view_size.y
	c.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w, h), Vector2(0, h)]),
		PackedColorArray([BG_TOP, BG_TOP, BG_BOTTOM, BG_BOTTOM]))
	var grid := Color(ACCENT, 0.05)
	for x in range(32, int(w), 32):
		c.draw_line(Vector2(x, 0), Vector2(x, h), grid, 1.0)
	for y in range(32, int(h), 32):
		c.draw_line(Vector2(0, y), Vector2(w, y), grid, 1.0)


## Kulmakehykset ja reunaviiva.
func _frame(c: CanvasItem) -> void:
	var w := view_size.x
	var h := view_size.y
	var m := 10.0
	var k := 46.0
	c.draw_rect(Rect2(m, m, w - 2 * m, h - 2 * m), Color(ACCENT, 0.18), false, 2.0)
	for corner: Vector2 in [Vector2(m, m), Vector2(w - m, m), Vector2(w - m, h - m), Vector2(m, h - m)]:
		var sx := 1.0 if corner.x < w / 2.0 else -1.0
		var sy := 1.0 if corner.y < h / 2.0 else -1.0
		c.draw_polyline(PackedVector2Array([corner + Vector2(0, sy * k), corner, corner + Vector2(sx * k, 0)]), ACCENT, 4.0)


func _header(c: CanvasItem, text: String, right: String = "") -> void:
	var room := SIZE.x - 60.0
	if right != "":
		var r: Array = fit_text(mono, right, 22, 260.0)
		_text(c, mono, Vector2(SIZE.x - 30, 50), r[0], r[1], MUTED, -1.0, HORIZONTAL_ALIGNMENT_RIGHT)
		room -= mono.get_string_size(r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, r[1]).x + 24.0
	_text(c, font, Vector2(30, 52), text, 30, ACCENT, room)
	c.draw_line(Vector2(30, 66), Vector2(SIZE.x - 30, 66), Color(ACCENT, 0.35), 2.0)
	for i in 6:
		c.draw_rect(Rect2(30 + i * 14, 72, 8, 4), Color(ACCENT, 0.6 if i < 3 else 0.25))


## Päänäytön rivit sarakkeeseen; palauttaa viimeisen rivin alareunan.
func _rows(c: CanvasItem, x: float, y: float, w: float, k: float = 1.3) -> float:
	for r: Array in rows:
		var size_px: int = roundi(float(r[1]) * k)
		var col: Color = r[2] if r.size() > 2 else FG
		y += size_px * 1.2
		_text(c, font if int(r[1]) >= 34 else mono, Vector2(x, y), String(r[0]), size_px, col, w)
		y += size_px * 0.3
	return y


func _fuel_bar(c: CanvasItem, rect: Rect2) -> void:
	if bar == null:
		return
	var f := clampf(float(bar), 0.0, 1.0)
	c.draw_string(mono, rect.position + Vector2(0, -10), "POLTTOAINE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, MUTED)
	_right(c, mono, "%d %%" % roundi(f * 100.0), rect.end.x, rect.position.y - 10, 20, FG)
	c.draw_rect(rect, Color("#0d2340"))
	var col := GOOD if f > 0.2 else BAD
	var n := 24
	var cw := rect.size.x / n
	for i in n:
		if (i + 0.5) / n <= f:
			c.draw_rect(Rect2(rect.position.x + i * cw + 1, rect.position.y + 2, cw - 3, rect.size.y - 4), col)


func _right(c: CanvasItem, f: Font, text: String, x: float, y: float, fs: int, col: Color, max_w: float = -1.0) -> void:
	_text(c, f, Vector2(x, y), text, fs, col, max_w, HORIZONTAL_ALIGNMENT_RIGHT)


func _center(c: CanvasItem, f: Font, text: String, x: float, y: float, fs: int, col: Color, max_w: float = -1.0) -> void:
	_text(c, f, Vector2(x, y), text, fs, col, max_w, HORIZONTAL_ALIGNMENT_CENTER)


## Teksti kohtaan p (perusviiva; x on vasen reuna, oikea reuna tai keskikohta tasauksen mukaan). Jos max_w > 0, teksti
## sovitetaan leveyteen (fit_text).
func _text(c: CanvasItem, f: Font, p: Vector2, text: String, fs: int, col: Color, max_w: float = -1.0,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	var fit: Array = fit_text(f, text, fs, max_w)
	var tw := f.get_string_size(fit[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fit[1]).x
	var x := p.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x -= tw
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x -= tw / 2.0
	c.draw_string(f, Vector2(x, p.y), fit[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fit[1], col)


## Sovittaa tekstin leveyteen max_w: fonttia pienennetään enintään min_scale-kertaiseksi, ja jos se ei riitä, loppu
## korvataan ellipsillä. Palauttaa [teksti, fonttikoko]. max_w <= 0: ei rajaa.
static func fit_text(f: Font, text: String, fs: int, max_w: float, min_scale: float = 0.6) -> Array:
	if max_w <= 0.0:
		return [text, fs]
	var w := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if w <= max_w:
		return [text, fs]
	var smallest := maxi(1, ceili(fs * min_scale))
	var size := clampi(floori(fs * max_w / w), smallest, fs)
	while size > smallest and f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		size -= 1
	if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x <= max_w:
		return [text, size]
	var t := text
	while t.length() > 1 and f.get_string_size(t.strip_edges() + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		t = t.substr(0, t.length() - 1)
	return [t.strip_edges() + "…", size]


## Rengasmittari: arvo 0–1, otsikko ja teksti keskellä.
func _ring_gauge(c: CanvasItem, p: Vector2, r: float, v: float, label: String, text: String, col: Color) -> void:
	c.draw_arc(p, r, 0, TAU, 64, Color(ACCENT, 0.15), 10.0, true)
	var a0 := -PI / 2.0
	if v > 0.0:
		c.draw_arc(p, r, a0, a0 + TAU * clampf(v, 0.0, 1.0), 64, col, 10.0, true)
	c.draw_arc(p, r - 16, 0, TAU, 48, Color(ACCENT, 0.3), 1.5, true)
	_center(c, font, text, p.x, p.y + 9, 24, FG, (r - 20.0) * 2.0)
	_center(c, mono, label, p.x, p.y + r + 34, 18, MUTED)


func _time_s() -> float:
	return Time.get_ticks_msec() / 1000.0


# --- Tutka ---

func _draw_nav(c: CanvasItem) -> void:
	_header(c, "NAVIGOINTI", "TUTKA")
	if data.is_empty():
		return
	var t: float = data.t
	var ship: PackedFloat64Array = data.ship
	var aim: Variant = data.get("aim")
	var au := Planets.AU_KM
	var cx := 560.0
	var cy := 322.0
	var R := 225.0
	var target: PackedFloat64Array = Flight.body_state(aim, t).r if aim != null else PackedFloat64Array()
	var reach := maxf(0.5, Vector2(ship[0], ship[1]).length() / au)
	if not target.is_empty():
		reach = maxf(reach, Vector2(target[0], target[1]).length() / au)
	reach *= 1.15
	var k := R / reach
	var px := func(r: PackedFloat64Array) -> Vector2: return Vector2(cx + r[0] / au * k, cy - r[1] / au * k)
	# Tutkan kehät, ristikko ja asteikko.
	for i in range(1, 5):
		c.draw_arc(Vector2(cx, cy), R * i / 4.0, 0, TAU, 96, Color(ACCENT, 0.3 if i == 4 else 0.14), 2.0 if i == 4 else 1.0, true)
	c.draw_line(Vector2(cx - R, cy), Vector2(cx + R, cy), Color(ACCENT, 0.18), 1.0)
	c.draw_line(Vector2(cx, cy - R), Vector2(cx, cy + R), Color(ACCENT, 0.18), 1.0)
	for i in 72:
		var a := TAU * i / 72.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(Vector2(cx, cy) + d * R, Vector2(cx, cy) + d * (R + (12.0 if i % 6 == 0 else 6.0)), Color(ACCENT, 0.5), 1.5)
	# Radat ja planeetat.
	var dists := []
	for name in Planets.NAMES:
		var r: PackedFloat64Array = Flight.body_state(name, t).r
		var p: Vector2 = px.call(r)
		var rr := Vector2(r[0], r[1]).length() / au * k
		if rr < R * 1.05:
			c.draw_arc(Vector2(cx, cy), rr, 0, TAU, 96, Color(ACCENT, 0.3), 1.5, true)
			c.draw_circle(p, 8.0 if name == aim else 5.5, Planets.info(name).color)
		dists.append([Flight.surface_distance(ship, name, t), name])
	c.draw_circle(Vector2(cx, cy), 7.0, Color("#ffd27a"))
	var sp: Vector2 = px.call(ship)
	if not target.is_empty():
		var tp: Vector2 = px.call(target)
		c.draw_dashed_line(sp, tp, GOOD, 2.0, 8.0)
		c.draw_arc(tp, 15.0, 0, TAU, 32, GOOD, 2.0, true)
	c.draw_line(sp - Vector2(12, 0), sp + Vector2(12, 0), Color.WHITE, 3.0)
	c.draw_line(sp - Vector2(0, 12), sp + Vector2(0, 12), Color.WHITE, 3.0)
	# Vasen sarake: kohde ja mittakaava.
	var y := 120.0
	for item: Array in [["KOHDE", String(aim).to_upper() if aim != null else "VAPAA", GOOD if aim != null else FG],
			["ETÄISYYS", Fmt.km(Flight.surface_distance(ship, aim, t)) if not target.is_empty() else "–", FG],
			["SÄDE", "%s AU" % (Fmt.num(reach, 1) if reach < 10.0 else Fmt.num(roundf(reach))), FG],
			["AURINGOSTA", "%s AU" % Fmt.num(Flight.norm(ship) / au, 2), FG]]:
		c.draw_string(mono, Vector2(30, y), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED)
		_text(c, font, Vector2(30, y + 32), item[1], 26, item[2], 290.0)
		y += 98.0
	# Oikea sarake: lähimmät planeetat.
	dists.sort()
	c.draw_string(mono, Vector2(818, 120), "LÄHIMMÄT", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED)
	for i in 4:
		var e: Array = dists[i]
		var yy := 158.0 + i * 92.0
		c.draw_circle(Vector2(826, yy - 7), 6.0, Planets.info(e[1]).color)
		_text(c, mono, Vector2(842, yy), e[1], 20, FG, SIZE.x - 30 - 842)
		_text(c, font, Vector2(818, yy + 34), _au_or_km(float(e[0])), 24, ACCENT, SIZE.x - 30 - 818)


## Etäisyys AU:na, lähellä kilometreinä.
static func _au_or_km(km: float) -> String:
	return Fmt.km(km) if km < 0.01 * Planets.AU_KM else "%s AU" % Fmt.num(km / Planets.AU_KM, 2)


# --- Aluskaavio ---

func _draw_ship(c: CanvasItem) -> void:
	_header(c, title, "ALUS")
	var o := Vector2(320, 330)
	var s := 1.25
	var body := PackedVector2Array([Vector2(200, 0), Vector2(150, -22), Vector2(60, -36), Vector2(-60, -40), Vector2(-150, -36),
		Vector2(-178, -22), Vector2(-178, 22), Vector2(-150, 36), Vector2(-60, 40), Vector2(60, 36), Vector2(150, 22)])
	var wing := PackedVector2Array([Vector2(40, -36), Vector2(-50, -150), Vector2(-112, -160), Vector2(-120, -40)])
	var canard := PackedVector2Array([Vector2(120, -26), Vector2(96, -66), Vector2(76, -66), Vector2(70, -32)])
	var tf := func(poly: PackedVector2Array, flip: bool) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p in poly:
			out.append(o + Vector2(p.x, -p.y if flip else p.y) * s)
		return out
	var thrust := clampf(float(data.get("thrust", 0.0)), 0.0, 1.0)
	# Moottorin liekit.
	if thrust > 0.02:
		for ey: float in [-16.0, 16.0]:
			var flick := 0.85 + 0.15 * sin(_time_s() * 40.0 + ey)
			var L := 160.0 * thrust * flick
			c.draw_colored_polygon(tf.call(PackedVector2Array([Vector2(-184, ey - 11), Vector2(-184 - L, ey), Vector2(-184, ey + 11)]), false), Color(WARM, 0.75))
			c.draw_colored_polygon(tf.call(PackedVector2Array([Vector2(-184, ey - 5), Vector2(-184 - L * 0.55, ey), Vector2(-184, ey + 5)]), false), Color(1, 0.95, 0.8, 0.9))
	for part: Array in [[wing, false], [wing, true], [canard, false], [canard, true], [body, false]]:
		var poly: PackedVector2Array = tf.call(part[0], part[1])
		c.draw_colored_polygon(poly, Color(ACCENT, 0.1))
		var closed := poly.duplicate()
		closed.append(poly[0])
		c.draw_polyline(closed, ACCENT, 2.5, true)
	# Moottorit, ohjaamo ja keskilinja.
	for ey: float in [-16.0, 16.0]:
		c.draw_rect(Rect2(o + Vector2(-192, ey - 10) * s, Vector2(14, 20) * s), WARM if thrust > 0.02 else Color(ACCENT, 0.6))
	c.draw_line(o + Vector2(-170, 0) * s, o + Vector2(190, 0) * s, Color(ACCENT, 0.3), 1.0)
	c.draw_colored_polygon(tf.call(PackedVector2Array([Vector2(178, 0), Vector2(150, -12), Vector2(128, -12), Vector2(128, 12), Vector2(150, 12)]), false), Color(BRIGHT, 0.6))
	# Polttoainesäiliö rungossa täyttöasteen mukaan.
	var fuel := clampf(float(data.get("fuel", 0.0)), 0.0, 1.0)
	var tank := Rect2(o + Vector2(-130, -20) * s, Vector2(220, 40) * s)
	c.draw_rect(tank, Color(ACCENT, 0.5), false, 2.0)
	c.draw_rect(Rect2(tank.position + Vector2(3, 3), Vector2((tank.size.x - 6) * fuel, tank.size.y - 6)), Color(GOOD if fuel > 0.2 else BAD, 0.55))
	# Selitteet viivoineen.
	c.draw_line(o + Vector2(-20, 30) * s, Vector2(150, 520), Color(ACCENT, 0.5), 1.5)
	_text(c, mono, Vector2(40, 540), "SÄILIÖ %d %%" % roundi(fuel * 100.0), 20, FG, 580.0)
	c.draw_line(o + Vector2(-190, 0) * s, Vector2(40, 140), Color(ACCENT, 0.5), 1.5)
	c.draw_string(mono, Vector2(30, 130), "MOOTTORI %s" % ("POLTTO" if thrust > 0.02 else "VALMIUS"), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, WARM if thrust > 0.02 else FG)
	# Oikea sarake: päänäytön rivit.
	c.draw_line(Vector2(640, 100), Vector2(640, 540), Color(ACCENT, 0.25), 1.5)
	_rows(c, 664, 100, 340, 1.25)


# --- Tähtäin ---

func _draw_target(c: CanvasItem) -> void:
	_header(c, title, String(data.get("aim", "")).to_upper() if data.get("aim") != null else "VAPAA")
	var p := Vector2(660, 322)
	var R := 185.0
	var tt := _time_s()
	c.draw_arc(p, R, 0, TAU, 128, Color(ACCENT, 0.5), 2.0, true)
	c.draw_arc(p, R * 0.66, 0, TAU, 96, Color(ACCENT, 0.3), 1.5, true)
	c.draw_arc(p, R * 0.3, 0, TAU, 64, Color(ACCENT, 0.6), 2.0, true)
	for i in 4:
		var a := tt * 0.4 + i * PI / 2.0
		c.draw_arc(p, R + 16, a, a + 0.9, 24, ACCENT, 4.0, true)
	for i in 36:
		var a := TAU * i / 36.0
		var d := Vector2(cos(a), sin(a))
		c.draw_line(p + d * (R - (16.0 if i % 9 == 0 else 8.0)), p + d * R, Color(ACCENT, 0.7), 2.0)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		c.draw_line(p + d * R * 0.36, p + d * R * 0.9, Color(ACCENT, 0.55), 2.0)
	# Kohde keskellä: nokka osoittaa kohteeseen.
	var on: bool = data.get("aim") != null
	c.draw_circle(p, 9.0, GOOD if on else Color(ACCENT, 0.4))
	c.draw_arc(p, 22.0 + 4.0 * sin(tt * 4.0), 0, TAU, 32, GOOD if on else Color(ACCENT, 0.4), 2.0, true)
	# Vasen sarake: päänäytön rivit.
	_rows(c, 30, 100, 400, 1.1)
	# Oikea sarake: työntö pystypalkkina.
	var thrust := clampf(float(data.get("thrust", 0.0)), 0.0, 1.0)
	var bar_r := Rect2(906, 130, 40, 360)
	c.draw_string(mono, Vector2(880, 116), "TYÖNTÖ", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED)
	c.draw_rect(bar_r, Color("#0d2340"))
	var n := 18
	for i in n:
		var on_seg := (i + 0.5) / n <= thrust
		c.draw_rect(Rect2(bar_r.position.x + 3, bar_r.end.y - (i + 1) * bar_r.size.y / n + 2, bar_r.size.x - 6, bar_r.size.y / n - 4),
			WARM if on_seg else Color(ACCENT, 0.12))
	_center(c, font, "%d %%" % roundi(thrust * 100.0), bar_r.get_center().x, bar_r.end.y + 34, 22, FG)


# --- Järjestelmät ---

func _draw_systems(c: CanvasItem) -> void:
	_header(c, "JÄRJESTELMÄT", "TILA")
	if data.is_empty():
		return
	# Etäisyydet planeetoille pylväinä (logaritminen asteikko 0,01–50 AU).
	var t: float = data.t
	var ship: PackedFloat64Array = data.ship
	var chart := Rect2(34, 110, 520, 190)
	c.draw_string(mono, chart.position + Vector2(0, -8), "ETÄISYYS PLANEETOILLE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)
	for i in 4:
		var y := chart.position.y + 14 + chart.size.y * i / 4.0
		c.draw_line(Vector2(chart.position.x, y), Vector2(chart.end.x, y), Color(ACCENT, 0.1), 1.0)
	var bw := chart.size.x / Planets.NAMES.size()
	for i in Planets.NAMES.size():
		var name: String = Planets.NAMES[i]
		var d := Flight.norm(Flight.sub(Flight.body_state(name, t).r, ship)) / Planets.AU_KM
		var f := clampf((log(maxf(d, 0.01)) / log(10.0) + 2.0) / 3.7, 0.04, 1.0)
		var hgt := (chart.size.y - 14) * f
		var x := chart.position.x + i * bw + bw * 0.18
		var col := GOOD if name == data.get("aim") else ACCENT
		c.draw_rect(Rect2(x, chart.end.y - hgt, bw * 0.64, hgt), Color(col, 0.35))
		c.draw_rect(Rect2(x, chart.end.y - hgt, bw * 0.64, 4), col)
		_center(c, mono, SHORT[name], x + bw * 0.32, chart.end.y + 24, 16, MUTED)
	# Rengasmittarit.
	var fuel := clampf(float(data.fuel), 0.0, 1.0)
	var thrust := clampf(float(data.get("thrust", 0.0)), 0.0, 1.0)
	var warp := maxf(1.0, float(data.warp))
	var warp_f := log(warp) / log(float(Game.WARPS[-1][0]))
	_ring_gauge(c, Vector2(110, 420), 56, fuel, "POLTTOAINE", "%d %%" % roundi(fuel * 100.0), GOOD if fuel > 0.2 else BAD)
	_ring_gauge(c, Vector2(290, 420), 56, thrust, "TYÖNTÖ", "%d %%" % roundi(thrust * 100.0), WARM)
	_ring_gauge(c, Vector2(470, 420), 56, warp_f, "AIKA", warp_label(warp), ACCENT)
	c.draw_line(Vector2(600, 90), Vector2(600, 546), Color(ACCENT, 0.25), 1.5)


func _draw_systems_over(c: CanvasItem) -> void:
	if data.is_empty():
		return
	var aim: Variant = data.get("aim")
	_center(c, font, String(aim).to_upper() if aim != null else "AURINKO", 790, 420, 24, ACCENT, 340.0)
	var list := [["SUUNTA", String(aim) if aim != null else "vapaa"], ["MOOTTORI", String(data.engine)],
		["AIKAKIIHDYTYS", warp_label(float(data.warp))], ["SÄTEILYSUOJA", "OK"]]
	for i in list.size():
		var y := 462.0 + i * 26.0
		c.draw_string(mono, Vector2(630, y), list[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED)
		var label_w := mono.get_string_size(list[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		_right(c, mono, list[i][1], 990, y, 18, FG, 990.0 - 630.0 - label_w - 16.0)


# --- Kohdekamera ---

func _draw_camera(c: CanvasItem) -> void:
	if feed == "360":
		draw_pan_hud(c, font, mono, SIZE, pan, 1.0)
		_feed_footer(c)
		return
	if feed == "taka":
		_draw_rear(c)
		return
	# Tekstipaneeli kamerakuvan päällä.
	c.draw_rect(Rect2(10, 10, 420, SIZE.y - 20), Color(0.01, 0.04, 0.09, 0.78))
	c.draw_line(Vector2(430, 10), Vector2(430, SIZE.y - 10), Color(ACCENT, 0.4), 2.0)
	_text(c, font, Vector2(30, 52), title, 28, ACCENT, 390.0)
	c.draw_line(Vector2(30, 66), Vector2(410, 66), Color(ACCENT, 0.35), 2.0)
	_rows(c, 30, 90, 390, 1.25)
	_fuel_bar(c, Rect2(30, SIZE.y - 70, 380, 30))
	var blink := fmod(_time_s(), 1.6) < 0.8
	var cam: Array = fit_text(mono, "KOHDEKAMERA  %s" % _globe_name.to_upper(), 20, SIZE.x - 30.0 - 470.0)
	var cam_w := mono.get_string_size(cam[0], HORIZONTAL_ALIGNMENT_LEFT, -1, cam[1]).x
	c.draw_circle(Vector2(SIZE.x - 50 - cam_w, 44), 8.0, BAD if blink else Color(BAD, 0.3))
	_right(c, mono, cam[0], SIZE.x - 30, 52, cam[1], BRIGHT)
	# Tähtäysrasti kohteen keskellä ja kehänmerkit kohteen ympärillä.
	var p := Vector2(TELE_X, SIZE.y / 2.0)
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		c.draw_line(p + d * 14, p + d * 40, Color(BRIGHT, 0.7), 2.0)
	if feed == "kohde" and tele.y > 0.0:
		var rr := tele.y * SIZE.y + 14.0
		for i in 4:
			var a := TAU * i / 4.0 + PI / 4.0
			c.draw_arc(p, rr, a - 0.28, a + 0.28, 16, Color(ACCENT, 0.75), 2.0, true)
	if feed == "kohde" and close:
		# Aluksen kohta pallon keskellä: sykkivä rengas ja merkintä.
		var pulse := fmod(_time_s(), 1.6) / 1.6
		c.draw_arc(p, 6.0 + 22.0 * pulse, 0, TAU, 32, Color(GOOD, 0.8 * (1.0 - pulse)), 2.0, true)
		c.draw_circle(p, 4.0, GOOD)
		c.draw_string(mono, p + Vector2(12, -10), "ALUS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOOD)
	if feed == "kohde":
		var z := tele_label if close else "ZOOM %s×" % (Fmt.num(tele.x, 1) if tele.x < 10.0 else Fmt.num(roundf(tele.x)))
		_right(c, mono, z, SIZE.x - 30, SIZE.y - 30, 18, MUTED, SIZE.x - 470.0)


## Takakamera: kuva täyttää näytön; otsikko ja tallennusvalo ylhäällä, kohde ja polttoaine alareunan palkissa.
func _draw_rear(c: CanvasItem) -> void:
	var blink := fmod(_time_s(), 1.6) < 0.8
	c.draw_rect(Rect2(10, 10, SIZE.x - 20, 64), Color(0.01, 0.04, 0.09, 0.55))
	c.draw_circle(Vector2(40, 42), 9.0, BAD if blink else Color(BAD, 0.3))
	c.draw_string(font, Vector2(60, 52), "TAKAKAMERA", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, BRIGHT)
	_right(c, mono, "180°  •  REC", SIZE.x - 30, 50, 20, MUTED)
	# Tähtäysmerkit kuvan keskellä (kamera osoittaa suoraan taaksepäin).
	var p := SIZE / 2.0 + Vector2(0, 20)
	for d: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		c.draw_polyline(PackedVector2Array([p + d * Vector2(60, 26), p + d * Vector2(60, 40), p + d * Vector2(40, 40)]), Color(BRIGHT, 0.6), 2.0)
	_feed_footer(c)


## Ulkokameran alareunan palkki: kohde ja polttoaine.
func _feed_footer(c: CanvasItem) -> void:
	c.draw_rect(Rect2(10, SIZE.y - 96, SIZE.x - 20, 86), Color(0.01, 0.04, 0.09, 0.62))
	_text(c, font, Vector2(30, SIZE.y - 56), title, 24, ACCENT, 420.0)
	if not rows.is_empty():
		_text(c, mono, Vector2(30, SIZE.y - 24), String(rows[0][0]), 22, FG, 420.0)
	_fuel_bar(c, Rect2(500, SIZE.y - 50, SIZE.x - 530, 26))


## 360°-kameran tähtäin (näytöllä ja koko näytön kuvassa): otsikko ja tallennusvalo, suuntimanauha ylhäällä
## (KEULA 0°, PERÄ 180°), kallistusasteikko vasemmalla ja kulmamerkit keskellä. sz on piirtoalue, s tekstin ja
## viivojen mittakaava, pan = (suuntima, kallistus, zoom) ja y0 yläpalkin yläreuna.
static func draw_pan_hud(c: CanvasItem, font: Font, mono: Font, sz: Vector2, p_pan: Vector3, s: float, y0: float = 0.0) -> void:
	var blink := fmod(Time.get_ticks_msec() / 1000.0, 1.6) < 0.8
	var top := 64.0 * s
	if y0 != 0.0: # näytöllä piirtomuunnos on jo asetettu
		c.draw_set_transform(Vector2(0, y0))
	c.draw_rect(Rect2(10 * s, 10 * s, sz.x - 20 * s, top), Color(0.01, 0.04, 0.09, 0.5))
	c.draw_circle(Vector2(40, 42) * s, 9.0 * s, BAD if blink else Color(BAD, 0.3))
	c.draw_string(font, Vector2(60, 52) * s, "360° KAMERA", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(28 * s), BRIGHT)
	var bearing := fposmod(rad_to_deg(p_pan.x), 360.0)
	var info := "%03d°  %+d°  %s×" % [roundi(bearing) % 360, roundi(rad_to_deg(p_pan.y)), Fmt.num(p_pan.z, 1)]
	var fs := roundi(20 * s)
	var iw := mono.get_string_size(info, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	if sz.x - 30 * s - iw > 60 * s + font.get_string_size("360° KAMERA", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(28 * s)).x + 20 * s:
		c.draw_string(mono, Vector2(sz.x - 30 * s - iw, 50 * s), info, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, MUTED)
	# Suuntimanauha: 10° välein viivat, 30° välein luvut, keskellä osoitin.
	var cx := sz.x / 2.0
	var y := top + 46.0 * s
	var half_w := minf(sz.x / 2.0 - 30.0 * s, 340.0 * s)
	var span := 70.0 / maxf(p_pan.z, 0.2) # nauhan puolileveys asteina
	c.draw_rect(Rect2(cx - half_w, y - 26 * s, half_w * 2.0, 44 * s), Color(0.01, 0.04, 0.09, 0.35))
	c.draw_line(Vector2(cx - half_w, y), Vector2(cx + half_w, y), Color(ACCENT, 0.45), 1.5 * s)
	var d0 := int(floor((bearing - span) / 10.0)) * 10
	var d := d0
	while d <= bearing + span:
		var x := cx + (d - bearing) / span * half_w
		if absf(x - cx) <= half_w:
			var a := 1.0 - absf(x - cx) / half_w * 0.7
			var major := posmod(d, 30) == 0
			c.draw_line(Vector2(x, y), Vector2(x, y - (12.0 if major else 6.0) * s), Color(ACCENT, 0.8 * a), 2.0 * s)
			if major:
				var dd := posmod(d, 360)
				var lab := "KEULA" if dd == 0 else ("PERÄ" if dd == 180 else "%03d" % dd)
				var lw := mono.get_string_size(lab, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * s)).x
				c.draw_string(mono, Vector2(x - lw / 2.0, y - 16 * s), lab, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(16 * s),
					Color(GOOD if dd == 0 else (WARM if dd == 180 else BRIGHT), a))
		d += 10
	c.draw_colored_polygon(PackedVector2Array([Vector2(cx, y + 2 * s), Vector2(cx - 8 * s, y + 14 * s), Vector2(cx + 8 * s, y + 14 * s)]), BRIGHT)
	if y0 != 0.0:
		c.draw_set_transform(Vector2.ZERO)
	top += y0
	# Kallistusasteikko vasemmalla: 15° välein.
	var mid := sz.y / 2.0
	var lx := 34.0 * s
	# Asteikko kuvan mittakaavassa: kuvan korkeus on 360°-kameran pystykuvakulma (64° / zoom).
	var px_deg := sz.y / (64.0 / maxf(p_pan.z, 0.2))
	var step := 5 if px_deg * 5.0 > 40.0 * s else (10 if px_deg * 10.0 > 40.0 * s else 15)
	var el := rad_to_deg(p_pan.y)
	for e in range(-90, 91, step):
		var yy := mid - (e - el) * px_deg
		if yy < top + 80 * s or yy > sz.y - 110 * s:
			continue
		var major := e % (step * 2) == 0 or e == 0
		c.draw_line(Vector2(lx, yy), Vector2(lx + (18.0 if major else 10.0) * s, yy), Color(GOOD if e == 0 else ACCENT, 0.75), 2.0 * s)
		if major:
			c.draw_string(mono, Vector2(lx + 24 * s, yy + 6 * s), "%+d°" % e if e != 0 else "0°", HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(15 * s), Color(BRIGHT, 0.8))
	c.draw_colored_polygon(PackedVector2Array([Vector2(lx - 4 * s, mid), Vector2(lx - 16 * s, mid - 8 * s), Vector2(lx - 16 * s, mid + 8 * s)]), BRIGHT)
	# Kulmamerkit ja piste keskellä.
	var p := Vector2(cx, mid)
	for q: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		c.draw_polyline(PackedVector2Array([p + q * Vector2(60, 26) * s, p + q * Vector2(60, 40) * s, p + q * Vector2(40, 40) * s]), Color(BRIGHT, 0.6), 2.0 * s)
	c.draw_circle(p, 2.5 * s, Color(BRIGHT, 0.8))


# --- Pikkunäyttö ---

func _draw_mini(c: CanvasItem) -> void:
	_header(c, "OHJAUS")
	if data.is_empty():
		return
	var thrust := clampf(float(data.get("thrust", 0.0)), 0.0, 1.0)
	c.draw_string(mono, Vector2(40, 150), "AIKAKIIHDYTYS", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, MUTED)
	_text(c, font, Vector2(40, 240), warp_label(float(data.warp)), 80, WARM, 490.0)
	c.draw_string(mono, Vector2(560, 150), "MOOTTORI", HORIZONTAL_ALIGNMENT_LEFT, -1, 36, MUTED)
	_text(c, font, Vector2(560, 240), String(data.engine).to_upper(), 64, WARM if thrust > 0.02 else FG, SIZE.x - 40.0 - 560.0)
	var r := Rect2(40, 330, SIZE.x - 80, 60)
	c.draw_rect(r, Color("#0d2340"))
	c.draw_rect(Rect2(r.position, Vector2(r.size.x * thrust, r.size.y)), WARM)
	c.draw_string(mono, Vector2(40, 460), "TYÖNTÖ %d %%" % roundi(thrust * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 36, FG)


## Aikakiihdytys tekstinä: pelin porrasnimi (esim. "1 vrk/s"), muuten kerroin.
static func warp_label(warp: float) -> String:
	for w: Array in Game.WARPS:
		if is_equal_approx(float(w[0]), warp):
			return w[1]
	return "%s×" % Fmt.num(maxf(warp, 1.0))
