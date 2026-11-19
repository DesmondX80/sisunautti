class_name FlightMap
extends Control
## Lentokartta (web/js/solarsystem.js ja voyage.js: draw): aurinkokunta oikeassa mittakaavassa ylhäältä ekliptikan
## pohjoispuolelta katsottuna (kevätpiste oikealle), alus, kuljettu reitti, tuleva rata, ohilento, kuut emoplaneetan
## ympärillä, kurssikorjauksen esikatselu, zoomaus ja seuranta. Piirto AU-koordinaateista; laskut 64-bittisinä.

const SHIP_COLOR := UiKit.WARM
const AU := Planets.AU_KM
const ORBIT_N := 720
const PATH_N := 240
const AU_STEPS := [20.0, 10.0, 5.0, 2.0, 1.0, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01]
const KM_STEPS := [1e6, 5e5, 2e5, 1e5, 5e4, 2e4, 1e4, 5000.0, 2000.0, 1000.0]
const REDRAW_S := 0.05

## Kartan rajaus (AU, kartan puolikas lyhyempi sivu) tai < 0 = sovitus lentoon; seuranta keskittää alukseen.
var radius := -1.0
var follow := false
## Kurssikorjauksen esikatselu (lento) tai tyhjä.
var preview: Dictionary = {}

var _orbit_cache := {} # planeetta → [epoch, PackedVector2Array (AU), el]
var _path_key := ""
var _path_pts: Array = [] # [[t, Vector2 AU]]
var _preview_key := ""
var _preview_pts: PackedVector2Array = []
var _since := 0.0
var _pinch_start := 0.0
var _touches := {}


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_CLICK


func _process(delta: float) -> void:
	_since += delta
	if is_visible_in_tree() and _since >= REDRAW_S:
		_since = 0.0
		queue_redraw()


func zoom(factor: float) -> void:
	radius = clampf((radius if radius > 0.0 else fit_radius()) * factor, 0.0005, 40.0)
	queue_redraw()


func set_follow(on: bool) -> void:
	follow = on
	radius = 0.05 if on else -1.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom(1.0 / 1.15)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom(1.15)
			accept_event()
	elif event is InputEventMagnifyGesture:
		zoom(1.0 / event.factor)
		accept_event()
	elif event is InputEventPanGesture:
		zoom(1.0 + event.delta.y * 0.05)
		accept_event()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_start = _pinch_distance()
	elif event is InputEventScreenDrag:
		_touches[event.index] = event.position
		var d := _pinch_distance()
		if _pinch_start > 0.0 and d > 0.0:
			zoom(_pinch_start / d)
			_pinch_start = d
			accept_event()


func _pinch_distance() -> float:
	if _touches.size() < 2:
		return 0.0
	var p: Array = _touches.values()
	return (p[0] as Vector2).distance_to(p[1])


# --- Sovitus ---

func _flight() -> Variant:
	var s: Dictionary = Game.state
	return s.flight if s.flight != null else s.plan


## Kuiden luona kartta keskitetään emoplaneettaan.
func local_parent() -> String:
	var f: Variant = _flight()
	if f != null and f.get("local", false):
		return f.parent
	var loc: Variant = Game.state.location
	if f == null and Flight.is_moon(loc):
		return Flight.MOONS[loc].parent
	return ""


func fit_radius() -> float:
	var f: Variant = _flight()
	var parent := local_parent()
	if parent != "":
		var best := 0.0
		for m in Flight.moons_of(parent):
			if f != null and (f.to == m or f.from == m) or Game.state.location == m:
				best = maxf(best, Flight.MOONS[m].aKm)
		return best * 1.3 / AU
	if f == null:
		return maxf(1.6, Flight.norm(Flight.departure_state(Game.here(), Game.sim_now()).r) / AU * 1.25)
	var r1: Variant = f.get("r1")
	var a := Flight.norm(r1) if r1 != null else Flight.norm(Flight.departure_state(f.from, f.depart).r)
	return maxf(a, Flight.norm(Flight.body_state(f.to, f.arrive).r)) / AU * 1.12


# --- Piirto ---

static func _au(r: PackedFloat64Array) -> Vector2:
	return Vector2(r[0] / AU, r[1] / AU)


func _draw() -> void:
	if Game.state.is_empty():
		return
	var w := size.x
	var h := size.y
	if w <= 0.0 or h <= 0.0:
		return
	var s: Dictionary = Game.state
	var f: Variant = _flight()
	var t := Game.sim_now()
	var ship: Dictionary
	if f == null:
		ship = Flight.departure_state(Game.here(), t)
	elif t > float(f.depart):
		ship = Flight.ship_state(f, t)
	else:
		ship = Flight.departure_state(f.from, t)
	var ship_au: Vector2 = _au(ship.r)
	var r := radius if radius > 0.0 else fit_radius()
	var k := minf(w, h) / 2.0 / r
	var parent := local_parent()
	var center := Vector2.ZERO
	if follow:
		center = ship_au
	elif parent != "":
		center = _au(Flight.planet_state(parent, t).r)
	var to_px := func(p: Vector2) -> Vector2: return Vector2(w / 2.0 + (p.x - center.x) * k, h / 2.0 - (p.y - center.y) * k)
	var selected: String = f.to if f != null else (s.location if s.location != null else "")
	_draw_scene(t, to_px, w, h, k, selected)
	if parent != "":
		_draw_moons(parent, t, to_px, w, h)
	if f != null:
		_draw_transfer(f, t, to_px, w)
	if not preview.is_empty() and s.flight != null:
		_draw_preview(t, to_px)
	# Nuoli: menosuunta kartan koordinaatistossa (kuiden luona emoplaneetan suhteen), sama kuin ohjaamon nokka.
	var arrow: PackedFloat64Array = ship.v if parent == "" else Flight.sub(ship.v, Flight.planet_state(parent, t).v)
	_draw_ship(to_px.call(ship_au), arrow)


func _font() -> Font:
	return get_theme_default_font()


func _text(pos: Vector2, text: String, color: Color, align: int = HORIZONTAL_ALIGNMENT_CENTER, outline: bool = true) -> void:
	var font := _font()
	var fs := 11
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var x := pos.x - tw / 2.0 if align == HORIZONTAL_ALIGNMENT_CENTER else (pos.x - tw if align == HORIZONTAL_ALIGNMENT_RIGHT else pos.x)
	if outline:
		draw_string_outline(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, UiKit.MAP_BG)
	draw_string(font, Vector2(x, pos.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, color)


func _orbit_points(name: String, t: float) -> Array:
	# Rata-alkiot muuttuvat hitaasti: rata lasketaan uudelleen, kun pelin aikaa on kulunut yli 30 vrk.
	var c: Variant = _orbit_cache.get(name)
	if c == null or absf(t - float(c[0])) > 30.0 * Flight.DAY_MS:
		var el := Planets.elements(name, t)
		var pts := PackedVector2Array()
		pts.resize(ORBIT_N + 1)
		for i in ORBIT_N + 1:
			var p := Planets.orbit_point(el, i * 2.0 * PI / ORBIT_N)
			pts[i] = Vector2(p[0], p[1])
		c = [t, pts, el]
		_orbit_cache[name] = c
	return c


# Kiertorata: vain kartalle osuvat perusvälit, ja ne jaetaan muutaman pikselin paloihin, jotta rata pysyy
# tarkkana myös lähelle zoomattuna.
func _orbit_path(name: String, t: float, to_px: Callable, w: float, h: float, color: Color, width: float) -> void:
	var c := _orbit_points(name, t)
	var pts: PackedVector2Array = c[1]
	var el: Dictionary = c[2]
	var step := 2.0 * PI / ORBIT_N
	var margin := 20.0
	var line := PackedVector2Array()
	var prev: Vector2 = to_px.call(pts[0])
	for i in range(1, ORBIT_N + 1):
		var p: Vector2 = to_px.call(pts[i])
		var off := maxf(prev.x, p.x) < -margin or minf(prev.x, p.x) > w + margin or maxf(prev.y, p.y) < -margin or minf(prev.y, p.y) > h + margin
		if off:
			if line.size() > 1:
				draw_polyline(line, color, width, true)
			line = PackedVector2Array()
			prev = p
			continue
		if line.is_empty():
			line.append(prev)
		var parts := mini(4000, ceili(prev.distance_to(p) / 3.0))
		for j in range(1, parts):
			var q := Planets.orbit_point(el, (i - 1 + float(j) / parts) * step)
			line.append(to_px.call(Vector2(q[0], q[1])))
		line.append(p)
		prev = p
	if line.size() > 1:
		draw_polyline(line, color, width, true)


func _scale_step(max_au: float) -> Array:
	for au: float in AU_STEPS:
		if au <= max_au:
			return [au, "%s AU" % Fmt.num(au, 2)]
	var km := 1000.0
	for v: float in KM_STEPS:
		if v <= max_au * AU:
			km = v
			break
	return [km / AU, "%s km" % Fmt.num(km)]


func _draw_scene(t: float, to_px: Callable, w: float, h: float, k: float, selected: String) -> void:
	draw_rect(Rect2(0, 0, w, h), UiKit.MAP_BG)
	for name in Planets.NAMES:
		var col: Color = Planets.info(name).color
		var sel := name == selected
		_orbit_path(name, t, to_px, w, h, Color(col, 0.8 if sel else 0.35), 1.5 if sel else 1.0)
	# Kohteet todellisen kokoisina, mutta vähintään pisteenä, jotta ne näkyvät kaukaa.
	var bodies: Array = [{"name": "Aurinko", "color": Color("#ffd75e"), "pos": Vector2.ZERO, "radius_km": Planets.SUN_RADIUS_KM, "min": 5.0}]
	for name in Planets.NAMES:
		var info := Planets.info(name)
		var hp := Planets.helio(name, t) # AU
		bodies.append({"name": name, "color": info.color, "pos": Vector2(hp[0], hp[1]), "radius_km": info.radius_km, "min": 3.5})
	var hits: Array = []
	for b: Dictionary in bodies:
		var p: Vector2 = to_px.call(b.pos)
		var rr := maxf(b.min, b.radius_km / AU * k)
		hits.append({"name": b.name, "p": p, "r": rr})
		if p.x < -rr or p.x > w + rr or p.y < -rr or p.y > h + rr:
			continue
		if b.name == "Aurinko":
			for i in 6:
				draw_circle(p, rr * (3.0 - i * 0.4), Color(1.0, 0.84, 0.37, 0.06))
		draw_circle(p, rr, b.color, true, -1.0, true)
		if b.name == selected:
			draw_arc(p, rr + 5.0, 0, TAU, 48, Color.WHITE, 1.5, true)
	# Nimet: valittu ja Maa ensin, eikä päällekkäisiä piirretä.
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ka := (2 if a.name == selected else 0) + (1 if a.name == "Maa" else 0)
		var kb := (2 if b.name == selected else 0) + (1 if b.name == "Maa" else 0)
		return ka > kb)
	var taken: Array[Rect2] = []
	var font := _font()
	for hit: Dictionary in hits:
		var p: Vector2 = hit.p
		if p.x < 0 or p.x > w or p.y < 0 or p.y > h:
			continue
		var tw := font.get_string_size(hit.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		var x := clampf(p.x, tw / 2.0 + 4.0, w - tw / 2.0 - 4.0)
		var y: float = p.y - hit.r - 6.0
		var rect := Rect2(x - tw / 2.0 - 2.0, y - 11.0, tw + 4.0, 14.0)
		if taken.any(func(o: Rect2) -> bool: return o.intersects(rect)):
			continue
		taken.append(rect)
		_text(Vector2(x, y), hit.name, Color.WHITE if hit.name == selected else Color("#c9d3ec"))
	var sc := _scale_step(w / 4.0 / k)
	var len: float = sc[0] * k
	draw_polyline(PackedVector2Array([Vector2(10, h - 14), Vector2(10, h - 10), Vector2(10 + len, h - 10), Vector2(10 + len, h - 14)]), UiKit.MUTED, 1.0)
	_text(Vector2(10 + len / 2.0, h - 16), sc[1], UiKit.MUTED, HORIZONTAL_ALIGNMENT_CENTER, false)
	_text(Vector2(w - 8, h - 56), "kevätpiste →", UiKit.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)


# Katkoviiva murtoviivan pisteistä.
func _dashed(points: PackedVector2Array, color: Color, width: float, dash: float, gap: float) -> void:
	var on := true
	var left := dash
	for i in range(1, points.size()):
		var a := points[i - 1]
		var b := points[i]
		var seg_len := a.distance_to(b)
		var pos := 0.0
		while pos < seg_len:
			var step := minf(left, seg_len - pos)
			if on:
				draw_line(a.lerp(b, pos / seg_len), a.lerp(b, (pos + step) / seg_len), color, width, true)
			pos += step
			left -= step
			if left <= 0.0:
				on = not on
				left = dash if on else gap
	return


func _dashed_circle(c: Vector2, r: float, color: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 49:
		pts.append(c + Vector2.from_angle(i * TAU / 48.0) * r)
	_dashed(pts, color, width, 2.0, 3.0)


func _flight_key(f: Dictionary) -> String:
	var legs: Variant = f.get("legs")
	return "%s %s %s %s %d" % [f.from, f.to, f.depart, f.arrive, legs.size() if legs is Array else 0]


func _draw_transfer(f: Dictionary, t: float, to_px: Callable, w: float) -> void:
	# Lennon rata lasketaan kerran (PATH_N näytettä), kuljettu osuus yhtenäisenä ja tuleva katkoviivana.
	var key := _flight_key(f)
	if key != _path_key:
		_path_key = key
		_path_pts = []
		var a: float = f.depart
		var b: float = f.arrive
		for i in PATH_N + 1:
			var ti := a + (b - a) * i / PATH_N
			_path_pts.append([ti, _au(Flight.ship_state(f, ti).r)])
	var past := PackedVector2Array()
	var future := PackedVector2Array()
	var now_au: Vector2 = _au(Flight.ship_state(f, clampf(t, f.depart, f.arrive)).r)
	for e: Array in _path_pts:
		if float(e[0]) <= t:
			past.append(to_px.call(e[1]))
		else:
			if future.is_empty():
				future.append(to_px.call(now_au))
			future.append(to_px.call(e[1]))
	if t > float(f.depart):
		past.append(to_px.call(now_au))
		if past.size() > 1:
			draw_polyline(past, Color(SHIP_COLOR, 0.9), 2.0, true)
	if t < float(f.arrive) and future.size() > 1:
		_dashed(future, Color(SHIP_COLOR, 0.6), 1.5, 5.0, 5.0)
	# Linkousplaneetta ohitushetkellä.
	var fb: Variant = f.get("flyby")
	if fb is Dictionary and t < float(fb.t):
		_dashed_circle(to_px.call(_au(Flight.planet_state(fb.body, fb.t).r)), 6.0, UiKit.GOOD, 1.2)
	# Kohdeplaneetan paikka saapumishetkellä.
	if t < float(f.arrive):
		var ap: Vector2 = to_px.call(_au(Flight.body_state(f.to, f.arrive).r))
		_dashed_circle(ap, 7.0, Color.WHITE, 1.2)
		var label := "%s %s" % ["ohitus" if f.get("miss", false) else "saapuminen", Fmt.date(f.arrive).substr(3)]
		var tw := _font().get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_text(Vector2(clampf(ap.x, tw / 2.0 + 4.0, w - tw / 2.0 - 4.0), ap.y + 20.0), label, Color("#c9d3ec"))


func _draw_preview(t: float, to_px: Callable) -> void:
	var key := "%s %s" % [_flight_key(preview), preview.get("missKm")]
	if key != _preview_key:
		_preview_key = key
		_preview_pts = PackedVector2Array()
		var b := maxf(t, preview.arrive)
		for i in 201:
			var ti := t + (b - t) * i / 200.0
			var p: Vector2 = _au(Flight.ship_state(preview, ti).r)
			_preview_pts.append(p)
	var pts := PackedVector2Array()
	for p in _preview_pts:
		pts.append(to_px.call(p))
	_dashed(pts, Color(UiKit.GOOD, 0.8), 1.5, 3.0, 4.0)


func _draw_moons(parent: String, t: float, to_px: Callable, w: float, h: float) -> void:
	var p: PackedFloat64Array = Flight.planet_state(parent, t).r
	var c: Vector2 = to_px.call(_au(p))
	for m in Flight.moons_of(parent):
		var md: Dictionary = Flight.MOONS[m]
		var col := Color(md.color)
		var edge: Vector2 = to_px.call(Vector2((p[0] + float(md.aKm)) / AU, p[1] / AU))
		draw_arc(c, absf(edge.x - c.x), 0, TAU, 128, Color(col, 0.35), 1.0, true)
		var mp: Vector2 = to_px.call(_au(Flight.body_state(m, t).r))
		if mp.x < -20 or mp.x > w + 20 or mp.y < -20 or mp.y > h + 20:
			continue
		draw_circle(mp, 3.0, col, true, -1.0, true)
		_text(Vector2(mp.x, mp.y - 7.0), m, Color("#c9d3ec"), HORIZONTAL_ALIGNMENT_CENTER, false)


# Alus kolmiona nopeuden suuntaan.
func _draw_ship(p: Vector2, v: PackedFloat64Array) -> void:
	var ang := atan2(-v[1], v[0])
	var pts := PackedVector2Array([Vector2(9, 0), Vector2(-6, 5), Vector2(-3, 0), Vector2(-6, -5)])
	var out := PackedVector2Array()
	for q in pts:
		out.append(p + q.rotated(ang))
	draw_colored_polygon(out, SHIP_COLOR)
	out.append(out[0])
	draw_polyline(out, UiKit.MAP_BG, 1.0, true)
