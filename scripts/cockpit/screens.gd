class_name CockpitScreen
extends Control
## Ohjaamon näytön sisältö SubViewportissa (web/js/cabin.js: display ja screen). Tyyppi:
##   "main"     otsikko, rivit ja polttoainepalkki (kolme päänäyttöä)
##   "nav"      navigointi: aurinkokunta ylhäältä, alus ja suunta kohteeseen
##   "systems"  järjestelmät: polttoaine, aikakiihdytys, suunta, moottori

const ACCENT := Color("#5ed6ff")
const MUTED := Color("#8b9ac0")
const FG := Color("#e8eefc")
const GOOD := Color("#4ade80")
const BAD := Color("#ff7b93")
const BG := Color("#020509")

var kind := "main"
var title := ""
var rows: Array = []
var bar: Variant = null
var nav: Dictionary = {}
var systems: Dictionary = {}
var _key := ""
var font: Font
var mono: Font


func _ready() -> void:
	font = load(UiKit.FONT_BOLD)
	mono = load(UiKit.FONT)


## Päivittää sisällön; piirtää uudelleen vain, jos jokin muuttui. Palauttaa true, jos piirrettiin.
func set_main(p_title: String, p_rows: Array, p_bar: Variant) -> bool:
	var key := "%s|%s|%s" % [p_title, p_rows, p_bar]
	if key == _key:
		return false
	_key = key
	title = p_title
	rows = p_rows
	bar = p_bar
	queue_redraw()
	return true


func set_nav(data: Dictionary) -> void:
	nav = data
	queue_redraw()


func set_systems(data: Dictionary) -> bool:
	var key := str(data)
	if key == _key:
		return false
	_key = key
	systems = data
	queue_redraw()
	return true


func _draw() -> void:
	var w := size.x
	var h := size.y
	draw_rect(Rect2(0, 0, w, h), BG)
	match kind:
		"main": _draw_main(w, h)
		"nav": _draw_nav(w, h)
		"systems": _draw_systems(w, h)


func _draw_main(w: float, h: float) -> void:
	draw_string(font, Vector2(18, 38), title, HORIZONTAL_ALIGNMENT_LEFT, w - 36, 24, ACCENT)
	draw_line(Vector2(18, 50), Vector2(w - 18, 50), Color(ACCENT, 0.3), 2.0)
	var y := 100.0
	for r: Array in rows:
		var size_px: int = r[1]
		var col: Color = r[2] if r.size() > 2 else FG
		draw_string(font if size_px >= 34 else mono, Vector2(18, y), String(r[0]), HORIZONTAL_ALIGNMENT_LEFT, w - 36, size_px, col)
		y += size_px * 1.45
	if bar != null:
		var f: float = bar
		draw_rect(Rect2(18, h - 30, w - 36, 12), Color("#1d2740"))
		draw_rect(Rect2(18, h - 30, (w - 36) * clampf(f, 0.0, 1.0), 12), GOOD if f > 0.2 else BAD)


func _draw_nav(w: float, h: float) -> void:
	draw_string(font, Vector2(18, 36), "NAVIGOINTI", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ACCENT)
	if nav.is_empty():
		return
	var t: float = nav.t
	var ship: PackedFloat64Array = nav.ship
	var aim: Variant = nav.aim
	var au := Planets.AU_KM
	var cx := w / 2.0
	var cy := h / 2.0 + 14.0
	var target: PackedFloat64Array = Flight.body_state(aim, t).r if aim != null else PackedFloat64Array()
	var reach := maxf(0.5, Vector2(ship[0], ship[1]).length() / au)
	if not target.is_empty():
		reach = maxf(reach, Vector2(target[0], target[1]).length() / au)
	reach *= 1.15
	var k := (h / 2.0 - 30.0) / reach
	var px := func(r: PackedFloat64Array) -> Vector2: return Vector2(cx + r[0] / au * k, cy - r[1] / au * k)
	var label := "säde %s AU" % (Fmt.num(reach, 1) if reach < 10.0 else Fmt.num(roundf(reach)))
	_right(mono, label, w - 18, 34, 18, MUTED)
	for name in Planets.NAMES:
		var r: PackedFloat64Array = Flight.body_state(name, t).r
		var p: Vector2 = px.call(r)
		var rr := Vector2(r[0], r[1]).length() / au * k
		if rr < w:
			draw_arc(Vector2(cx, cy), rr, 0, TAU, 96, Color(ACCENT, 0.22), 1.5, true)
		draw_circle(p, 6.0 if name == aim else 4.0, Planets.info(name).color)
	draw_circle(Vector2(cx, cy), 6.0, Color("#ffd27a"))
	var sp: Vector2 = px.call(ship)
	if not target.is_empty():
		var tp: Vector2 = px.call(target)
		draw_dashed_line(sp, tp, GOOD, 1.5, 6.0)
		draw_arc(tp, 11.0, 0, TAU, 32, GOOD, 1.5, true)
		draw_string(mono, tp + Vector2(15, 5), String(aim).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOOD)
	draw_line(sp - Vector2(9, 0), sp + Vector2(9, 0), Color.WHITE, 2.0)
	draw_line(sp - Vector2(0, 9), sp + Vector2(0, 9), Color.WHITE, 2.0)


func _draw_systems(w: float, _h: float) -> void:
	draw_string(font, Vector2(18, 36), "JÄRJESTELMÄT", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, ACCENT)
	if systems.is_empty():
		return
	var fuel: float = systems.fuel
	var warp: float = systems.warp
	var warp_text := "1×" if warp <= 1.0 else ("%s×" % Fmt.num(warp) if warp < 1e4 else "%.0e×" % warp)
	var list := [["POLTTOAINE", "%d %%" % roundi(fuel * 100.0), fuel], ["AIKAKIIHDYTYS", warp_text, null],
		["SUUNTA", String(systems.aim) if systems.aim != null else "vapaa", null], ["MOOTTORI", systems.engine, null], ["SÄTEILYSUOJA", "OK", null]]
	for i in list.size():
		var r: Array = list[i]
		var y := 78.0 + i * 42.0
		draw_string(mono, Vector2(18, y), r[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, MUTED)
		var low: bool = r[2] != null and float(r[2]) <= 0.2
		_right(mono, r[1], w - 18, y, 20, BAD if low else FG)
		if r[2] != null:
			draw_rect(Rect2(200, y - 15, w - 300, 14), Color("#1d2740"))
			draw_rect(Rect2(200, y - 15, (w - 300) * clampf(r[2], 0.0, 1.0), 14), BAD if low else GOOD)


func _right(f: Font, text: String, x: float, y: float, fs: int, col: Color) -> void:
	var tw := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(f, Vector2(x - tw, y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
