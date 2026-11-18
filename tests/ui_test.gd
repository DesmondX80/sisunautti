extends TestCase
## Käyttöliittymätesti ilman ikkunaa: koko peli pelataan paneelin painikkeilla (laukaisu, lento Marsiin,
## kartoitus ja paluu Maahan) ja tarkistetaan paneelin tekstit, asettelu ja kartta. Kello asetetaan käsin.
##   godot --headless -- --uitest

const START_REAL := 1794643200000.0

var G: Node
var ui: VoyageUI


func _ready() -> void:
	G = Game
	ui = get_parent().ui
	G.fake_real_ms = START_REAL
	G.new_game()
	refresh()
	_play()
	_layout()
	check("versio Tietoa-ikkunan otsikossa", ui._about.title == "Sisunautti " + VoyageUI.version())
	G.fake_real_ms = -1.0
	DirAccess.remove_absolute(G.TEST_SAVE_PATH)
	finish()


func refresh() -> void:
	ui._process(0.0)


func buttons() -> Array[Button]:
	var out: Array[Button] = []
	for n in ui.find_children("*", "Button", true, false):
		var b := n as Button
		if b.is_visible_in_tree() and not b.is_queued_for_deletion():
			out.append(b)
	return out


func find_button(text: String) -> Button:
	for b in buttons():
		if b.text == text:
			return b
	return null


## Painaa paneelin painiketta tekstin perusteella (kuten hiiri tai kosketus).
func press(text: String) -> bool:
	var b := find_button(text)
	if b == null or b.disabled:
		check("painike '%s' löytyi ja on käytössä" % text, false)
		return false
	if b.toggle_mode:
		b.button_pressed = true
	b.pressed.emit()
	refresh()
	return true


func panel_text() -> String:
	var parts: PackedStringArray = []
	for n in ui._body.find_children("*", "Label", true, false):
		if (n as Label).is_visible_in_tree():
			parts.append((n as Label).text)
	return "\n".join(parts)


func advance(ms: float, step: float = 100.0) -> void:
	var end: float = G.fake_real_ms + ms
	while G.fake_real_ms < end:
		G.fake_real_ms = minf(end, G.fake_real_ms + step)
		G.tick()
		refresh()


## Lentää perille painamalla aikakiihdytyspainikkeita (1 v/s kaukana, 1 vrk/s lähellä).
func fly_with_buttons() -> void:
	var guard := 0
	while G.sim_now() < float(G.state.flight.arrive) and guard < 20000:
		if G.warp_index() == 0:
			var left: float = float(G.state.flight.arrive) - G.sim_now()
			press("1 v/s" if left > 400.0 * G.DAY else "1 vrk/s")
		G.fake_real_ms += 100.0
		G.tick()
		guard += 1
	refresh()


func pick_target(name: String) -> void:
	var b := find_button(name)
	if b == null:
		b = find_button(name + " •")
	check("kohdepainike " + name, b != null)
	if b != null:
		b.pressed.emit()
		refresh()
	check("haku näkyy", panel_text().contains("Haetaan laukaisuikkunoita"))
	G.finish_search()
	refresh()


func _play() -> void:
	check("alussa laukaisualusta", panel_text().contains("Laukaisualustalla") and find_button("Aloita lähtölaskenta") != null)
	check("telakka alustalla", find_button("Ionialus") != null)
	press("Aloita lähtölaskenta")
	check("lähtölaskenta näkyy", panel_text().contains("T− 00.10") and find_button("Keskeytä lähtölaskenta") != null)
	advance(10500)
	check("nousussa", panel_text().contains("Nousussa kiertoradalle") and find_button("10×") != null)
	press("10×")
	advance(52000)
	check("kiertoradalla", panel_text().contains("Maan kiertoradalla") and panel_text().contains("Valitse kohde"))
	check("tietokortti Maa", panel_text().contains("Tutkimuksen löydöt"))
	pick_target("Mars")
	check("reittivaihtoehdot", panel_text().contains("Lento Marsiin") and panel_text().contains("Halvin"))
	press("Valitse reitti")
	check("odotusnäkymä", G.state.plan != null)
	if find_button("Siirry ikkunan alkuun") != null:
		press("Siirry ikkunan alkuun")
	check("ikkuna auki", find_button("Lähtöpoltto päälle") != null)
	press("Lähtöpoltto päälle")
	check("lähtöpoltto päällä", panel_text().contains("Lähtöpoltto on päällä") and find_button("Lähtöpoltto pois") != null)
	press("1 h/s")
	var guard := 0
	while G.state.flight == null and guard < 3000:
		advance(100)
		guard += 1
	check("lento alkoi", G.state.flight != null and panel_text().contains("Matkalla Marsiin"))
	check("mittarit", (ui._live.met as Label).text.begins_with("T+ ") and (ui._live.speed as Label).text.ends_with("km/s"))
	advance(2000)
	press("▸ Kurssikorjaus")
	check("kurssikorjauspaneeli ja esikatselu", panel_text().contains("Polton jälkeen rata") and not ui.map.preview.is_empty())
	press("10 m/s")
	var fuel: float = G.state.fuel
	press("Polta 10 m/s")
	check("kurssikorjaus kulutti polttoainetta", absf(float(G.state.fuel) - (fuel - 0.01)) < 1e-9)
	var fix: Button = null
	for b in buttons():
		if b.text.begins_with("Korjaa kurssi kohteeseen"):
			fix = b
	check("automaattinen korjaus tarjolla", fix != null)
	if fix != null:
		fix.pressed.emit()
		refresh()
	press("▾ Kurssikorjaus")
	check("esikatselu poistui", ui.map.preview.is_empty())
	fly_with_buttons()
	check("perillä", panel_text().contains("Alus on Marsin luona") and find_button("Jarruta kiertoradalle") != null)
	press("Jarruta kiertoradalle")
	check("Marsin kiertoradalla", panel_text().contains("Marsin kiertoradalla") and find_button("Tutki planeetta") != null)
	press("Tutki planeetta")
	check("kartoitus käynnissä", (ui._live.survey_label as Label) != null)
	press("1 vrk/s")
	advance(1500)
	check("Mars tutkittu", panel_text().contains("Tutkimuksen löydöt") and G.state.explored.has("Mars") and G.state.fuel == 14.0)
	press("▸ Lokikirja")
	check("lokikirja", panel_text().contains("Tutkitut planeetat") and panel_text().contains("2/8: Maa, Mars") and panel_text().contains("Maa → Mars"))
	press("▾ Lokikirja")
	# Paluu Maahan
	pick_target("Maa")
	check("paluureitit", panel_text().contains("Lento Maahan"))
	press("Valitse reitti")
	if find_button("Siirry ikkunan alkuun") != null:
		press("Siirry ikkunan alkuun")
	press("Lähtöpoltto päälle")
	press("1 h/s")
	guard = 0
	while G.state.flight == null and guard < 3000:
		advance(100)
		guard += 1
	fly_with_buttons()
	if find_button("Jarruta kiertoradalle") != null:
		press("Jarruta kiertoradalle")
	check("takaisin Maan kiertoradalla", G.state.location == "Maa" and G.state.flights.size() == 2)
	# Aloita alusta vahvistuksella
	press("Aloita alusta")
	check("vahvistus kysytään", ui._confirm.visible)
	ui._confirm.confirmed.emit()
	ui._confirm.hide()
	refresh()
	check("uusi peli", G.state.pad and panel_text().contains("Laukaisualustalla"))


func _layout() -> void:
	# Kokoa muutetaan käsin, joten ankkurit irrotetaan ikkunasta testin ajaksi.
	ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1600, 900)
	ui._layout()
	refresh()
	check("leveä: paneeli oikealla", ui._wide and ui._panel_scroll.visible and ui._panel_scroll.custom_minimum_size.x == VoyageUI.PANEL_W)
	ui.toggle_panel()
	check("paneelin piilotus", not ui._panel_scroll.visible and Settings.panel_hidden)
	ui.toggle_panel()
	check("paneeli takaisin", ui._panel_scroll.visible and not Settings.panel_hidden)
	ui.size = Vector2(390, 844)
	ui._layout()
	refresh()
	check("kapea: paneeli näkymän alla", not ui._wide and ui._narrow_scroll.visible and ui._panel_pad.get_parent() == ui._narrow_box)
	ui.size = Vector2(1600, 900)
	ui._layout()
	var r := ui.map.fit_radius()
	ui.map.zoom(0.5)
	check("zoomaus", absf(ui.map.radius - r * 0.5) < 1e-9)
	ui.map.set_follow(true)
	check("seuranta", ui.map.follow and ui.map.radius == 0.05)
	ui.map.set_follow(false)
	check("koko rata", not ui.map.follow and ui.map.radius < 0.0)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var info := PlanetInfo.all()
	var ok := true
	for name in Planets.NAMES:
		var c: Dictionary = info.get(name, {})
		for key: String in ["diameter", "mass", "gravity", "day", "year", "temperature", "atmosphere", "moons"]:
			ok = ok and String(c.get(key, "")) != ""
		ok = ok and c.get("facts", []).size() >= 2
	for m: String in Flight.MOONS:
		ok = ok and info.get(m, {}).get("facts", []).size() >= 2
	check("jokaisella planeetalla ja kuulla on tietokortti", ok)
