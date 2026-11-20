class_name HudLadder
extends Control
## Horisonttiristikko (#58) kuten lentokoneen HUD:ssa: horisonttiviiva, nousukulma-asteikko 5°:n välein nokan
## suuntaan, lentoradan merkki (mihin alus oikeasti menee) ja nokan merkki. Viivat ovat maailmaan kiinnitettyjä
## (kallistus kääntää niitä) ja piirtyvät vain ohjaamon ikkunan kohdalle.

const COLOR := Color(0.45, 1.0, 0.55, 0.9)
const STEP_DEG := 5
const SPAN_DEG := 40 # asteikko ± nokan nousukulmasta
const HALF_WIDTH_DEG := 6.0 # asteikon viivan puolileveys (atsimuuttia)
const HORIZON_HALF_DEG := 40.0
const SAMPLES := 12

## Piirrettävä: [{points: PackedVector2Array, dashed}], [{pos, text}], lentoradan ja nokan merkit (null jos ei näy).
var lines: Array = []
var labels: Array = []
var path_marker: Variant = null
var nose_marker: Variant = null
var font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	font = get_theme_default_font()


## Päivittää ristikon: cam ja ship maailman kantoina, fov pystykulma (°); up, nose ja vel suuntia maailmassa
## (vel nolla = ei lentoradan merkkiä). window(d) kertoo, näkyykö aluksen suunta d ikkunasta.
func update(cam: Basis, ship: Basis, fov: float, up: Vector3, nose: Vector3, vel: Vector3, window: Callable) -> void:
	var r := build(cam, ship, fov, size, up, nose, vel, window)
	lines = r.lines
	labels = r.labels
	path_marker = r.path
	nose_marker = r.nose
	queue_redraw()


## Ruudun piste suunnalle d (maailma) kameran kannasta cam; null kameran takana tai sivuilla.
static func project(cam: Basis, fov: float, view: Vector2, d: Vector3) -> Variant:
	var c := cam.inverse() * d
	if c.z > -1e-4:
		return null
	var f := view.y / 2.0 / tan(deg_to_rad(fov) / 2.0)
	return view / 2.0 + Vector2(c.x, -c.y) * f / -c.z


## Suunta atsimuutilla az ja nousukulmalla el (rad) paikallisen horisontin kannassa (fwd vaakaan, up ylös).
static func dir(fwd: Vector3, up: Vector3, az: float, el: float) -> Vector3:
	var right := fwd.cross(up).normalized()
	return (fwd * cos(az) + right * sin(az)) * cos(el) + up * sin(el)


static func build(cam: Basis, ship: Basis, fov: float, view: Vector2, up: Vector3, nose: Vector3, vel: Vector3, window: Callable) -> Dictionary:
	var out := {"lines": [], "labels": [], "path": null, "nose": null}
	up = up.normalized()
	var fwd := nose - up * nose.dot(up)
	if fwd.length() < 1e-4:
		fwd = -cam.z - up * (-cam.z).dot(up)
	if fwd.length() < 1e-4:
		return out
	fwd = fwd.normalized()
	var pitch := rad_to_deg(asin(clampf(nose.normalized().dot(up), -1.0, 1.0)))
	var visible := func(d: Vector3) -> Variant:
		if not window.call(ship.inverse() * d):
			return null
		return project(cam, fov, view, d)
	var first := int(ceil((pitch - SPAN_DEG) / STEP_DEG)) * STEP_DEG
	for e in range(maxi(first, -85), mini(int(pitch + SPAN_DEG), 85) + 1, STEP_DEG):
		var half := deg_to_rad(HORIZON_HALF_DEG if e == 0 else HALF_WIDTH_DEG)
		var el := deg_to_rad(e)
		# Viivan keskellä aukko (horisontissa ei), negatiiviset katkoviivoina.
		for side: float in ([-1.0, 1.0] if e != 0 else [0.0]):
			var a0 := -half if e == 0 else side * half * 0.3
			var a1 := half if e == 0 else side * half
			var seg := PackedVector2Array()
			for i in SAMPLES + 1:
				var az := lerpf(a0, a1, float(i) / SAMPLES)
				var p: Variant = visible.call(dir(fwd, up, az, el))
				if p == null:
					if seg.size() >= 2:
						out.lines.append({"points": seg, "dashed": e < 0, "horizon": e == 0})
					seg = PackedVector2Array()
				else:
					seg.append(p)
			if seg.size() >= 2:
				out.lines.append({"points": seg, "dashed": e < 0, "horizon": e == 0})
			if e != 0:
				var lp: Variant = visible.call(dir(fwd, up, side * half * 1.25, el))
				if lp != null:
					out.labels.append({"pos": lp, "text": str(absi(e))})
	if vel.length() > 1e-6:
		out.path = visible.call(vel.normalized())
	out.nose = visible.call(nose.normalized())
	return out


func _draw() -> void:
	for l: Dictionary in lines:
		var pts: PackedVector2Array = l.points
		var w := 2.0 if l.get("horizon", false) else 1.5
		if l.dashed:
			for i in range(0, pts.size() - 1, 2):
				draw_line(pts[i], pts[i + 1], COLOR, w, true)
		else:
			draw_polyline(pts, COLOR, w, true)
	for lb: Dictionary in labels:
		var w := font.get_string_size(lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string(font, lb.pos + Vector2(-w / 2.0, 5), lb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR)
	if path_marker != null:
		# Lentoradan merkki: ympyrä siivillä ja evällä.
		var p: Vector2 = path_marker
		draw_arc(p, 7.0, 0.0, TAU, 20, COLOR, 1.8, true)
		draw_line(p + Vector2(7, 0), p + Vector2(19, 0), COLOR, 1.8, true)
		draw_line(p - Vector2(7, 0), p - Vector2(19, 0), COLOR, 1.8, true)
		draw_line(p - Vector2(0, 7), p - Vector2(0, 14), COLOR, 1.8, true)
	if nose_marker != null:
		# Nokan merkki (W): mihin nokka osoittaa.
		var n: Vector2 = nose_marker
		draw_polyline(PackedVector2Array([n + Vector2(-18, 0), n + Vector2(-9, 0), n + Vector2(-4.5, 6), n,
			n + Vector2(4.5, 6), n + Vector2(9, 0), n + Vector2(18, 0)]), COLOR, 1.8, true)
