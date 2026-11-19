class_name VoyageUI
extends Control
## Pelin käyttöliittymä (web/js/voyage.js: paneelit ja asettelu). Näkymä (kartta tai ohjaamo) täyttää ikkunan, ja
## ohjaimet ovat oikean reunan 420 px:n paneelissa, jonka voi piilottaa. Kapeassa ikkunassa (alle 1000 px) paneeli
## on näkymän alla. Yläpalkissa nimi, ⓘ-ikkuna, päivä ja kello, paneelin piilotus ja koko näyttö.
## Paneeli rakennetaan uudelleen, kun pelin tila muuttuu (Game.changed); mittarit päivittyvät joka ruutu (_update).

const PANEL_W := 420.0
const WIDE_MIN := 1000.0
const DAY := Fmt.DAY_MS
const BURN_DIRS := [["prograde", "Eteen"], ["retrograde", "Taakse"], ["inward", "Sisään"], ["outward", "Ulos"]]
const BURN_SIZES := [[0.01, "10 m/s"], [0.05, "50 m/s"], [0.1, "100 m/s"], [0.5, "500 m/s"], [1.0, "1 km/s"]]
const ABOUT := "Peli, jossa lähdetään laukaisualustalta Maan pinnalta kiertoradalle ja sieltä muille planeetoille ja niiden kuille. Kantoraketti nostaa aluksen 200 km:n radalle noin 8,5 minuutissa. Kiertoradalla lähtöpoltto kytketään päälle, ja moottori syttyy, kun alus on radalla kohdassa, josta poltto linkoaa sen kohteeseen. Perillä jarrutetaan matalalle radalle. Radat, laukaisuikkunat ja polttoaineen kulutus (Δv) lasketaan oikeilla taivaanmekaniikan kaavoilla, ja pelin kello kulkee oikeassa ajassa, ellei aikaa kiihdytä."
const SOURCES := "Kuvalähteet: Solar System Scope (planeetat, Maan pilvet ja yövalot, Kuu ja Saturnuksen renkaat; CC BY 4.0, solarsystemscope.com/textures), NASA/Goddard SVS Deep Star Maps 2020 (Linnunrata), NASA/JPL/USGS (Phobos, Io), NASA/JPL-Caltech/SSI/LPI (Enceladus, Triton), Björn Jónsson NASAn kuvista (Ganymedes) ja Seek9750 Wikimedia Commonsissa (Europa). Kirjasin: DejaVu Sans (Bitstream Vera -lisenssi)."

## Valikkopainike tai Esc: pääscene avaa aloitusvalikon.
signal menu_requested
var _radio_btn: Button
var _brand: Label
var _radio_popup: PopupPanel
var map: FlightMap
var cockpit_view: CockpitView = null # 3D-ohjaamo
var fault_panel: FaultPanel
var game_over: GameOver

var _root: VBoxContainer
var _top: PanelContainer
var _date: Label
var _time: Label
var _panel_btn: Button
var _full_btn: Button
var _view_area: Control
var _overlay_view: Control
var _overlay_modes: Control
var _overlay_zoom: Control
var _wide_box: HBoxContainer
var _narrow_scroll: ScrollContainer
var _narrow_box: VBoxContainer
var _panel_scroll: ScrollContainer
var _panel_pad: MarginContainer
var _body: VBoxContainer
var _about: AcceptDialog
var _about_box: VBoxContainer
var _quality_seg: PanelContainer
var _confirm: ConfirmationDialog
var _wide := true
var _live := {} # päivitettävät tekstit ja palkit: nimi → Control
var _phase_key := ""
var _dirty := true
var _log_open := false
var _burn_open := false
var _burn_dir := "prograde"
var _burn_dv := 0.05
var _burn_preview: Dictionary = {}


func _ready() -> void:
	theme = UiKit.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = UiKit.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_root = UiKit.vbox(0)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_build_top()
	_build_view()
	_build_panel()
	_build_dialogs()
	_wide_box = UiKit.hbox(0)
	_wide_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrow_scroll = ScrollContainer.new()
	_narrow_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_narrow_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrow_box = UiKit.vbox(0)
	_narrow_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrow_scroll.add_child(_narrow_box)
	_root.add_child(_wide_box)
	_root.add_child(_narrow_scroll)
	_wide_box.add_child(_view_area)
	_wide_box.add_child(_panel_scroll)
	resized.connect(_layout)
	Game.changed.connect(func() -> void: _dirty = true)
	Game.notice_changed.connect(func(_t: String) -> void: _dirty = true)
	Game.search_progress.connect(func(p: float) -> void:
		var bar: Variant = _live.get("search_bar")
		if bar is ProgressBar:
			bar.value = p)
	_layout()
	_rebuild()
	# Aluksen vika (#42) ja tuhoutuminen kaiken päällä.
	fault_panel = FaultPanel.new()
	add_child(fault_panel)
	game_over = GameOver.new()
	add_child(game_over)


func _process(_delta: float) -> void:
	if Game.state.is_empty():
		return
	var key := _phase()
	if _dirty or key != _phase_key:
		_rebuild()
	_update()


func _unhandled_key_input(event: InputEvent) -> void:
	var e := event as InputEventKey
	if e == null or not e.pressed or e.echo:
		return
	if e.keycode == KEY_ESCAPE and is_visible_in_tree():
		menu_requested.emit()
	elif e.keycode == KEY_F11:
		toggle_fullscreen()
	elif e.keycode == KEY_P:
		toggle_panel()
	elif e.keycode >= KEY_1 and e.keycode <= KEY_8 and not Game.state.pad and Game.state.survey == null:
		Game.set_warp(e.keycode - KEY_1)
	elif e.keycode == KEY_PLUS or e.keycode == KEY_KP_ADD or e.keycode == KEY_EQUAL:
		map.zoom(1.0 / 1.6)
	elif e.keycode == KEY_MINUS or e.keycode == KEY_KP_SUBTRACT:
		map.zoom(1.6)
	else:
		return
	get_viewport().set_input_as_handled()


# Tila, jonka vaihtuessa paneeli rakennetaan uudelleen, vaikka Game.changed ei laukea (kello ylittää rajan).
func _phase() -> String:
	var s: Dictionary = Game.state
	var t := Game.sim_now()
	var up: bool = s.ascent != null and t >= float(s.ascent.liftoff)
	var ready: bool = s.plan != null and t >= Game.hold_at()
	var arrived: bool = s.flight != null and t >= float(s.flight.arrive)
	return "%s %s %s %s" % [up, ready, arrived, _wide]


# --- Rakenne ---

func _build_top() -> void:
	_top = PanelContainer.new()
	_top.theme_type_variation = "TopBar"
	var h := UiKit.hbox(12)
	_top.add_child(h)
	var menu_btn := UiKit.button("≡", func() -> void: menu_requested.emit())
	menu_btn.tooltip_text = "Valikko (Esc)"
	menu_btn.custom_minimum_size = Vector2(32, 28)
	h.add_child(menu_btn)
	_brand = UiKit.label("Sisunautti", "BrandLabel", false)
	h.add_child(_brand)
	var info := UiKit.button("i", show_about)
	info.tooltip_text = "Tietoa pelistä"
	info.custom_minimum_size = Vector2(28, 28)
	h.add_child(info)
	var clock := UiKit.vbox(0)
	clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock.alignment = BoxContainer.ALIGNMENT_CENTER
	_date = UiKit.label("", "TitleLabel", false)
	_date.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_time = UiKit.label("", "MutedLabel", false)
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clock.add_child(_date)
	clock.add_child(_time)
	h.add_child(clock)
	_radio_btn = UiKit.button("♪ Radio", show_radio)
	_radio_btn.tooltip_text = "Ohjaamon radio: musiikkia ja johtokeskuksen radioliikennettä"
	_radio_btn.custom_minimum_size = Vector2(0, 32)
	h.add_child(_radio_btn)
	_panel_btn = UiKit.button("▤", toggle_panel)
	_panel_btn.tooltip_text = "Piilota sivupaneeli (P)"
	_panel_btn.custom_minimum_size = Vector2(36, 32)
	h.add_child(_panel_btn)
	_full_btn = UiKit.button("⛶", toggle_fullscreen)
	_full_btn.tooltip_text = "Koko näyttö (F11)"
	_full_btn.custom_minimum_size = Vector2(36, 32)
	h.add_child(_full_btn)
	_root.add_child(_top)


func _build_view() -> void:
	_view_area = Control.new()
	_view_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_view_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_view_area.clip_contents = true
	map = FlightMap.new()
	map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view_area.add_child(map)
	cockpit_view = CockpitView.new()
	cockpit_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cockpit_view.ready.connect(_apply_view)
	_view_area.add_child(cockpit_view)
	# Näkymän vaihto (vasen yläkulma), kartan tilat (oikea yläkulma) ja zoomaus (oikea alakulma).
	_overlay_view = _overlay(Control.PRESET_TOP_LEFT)
	_overlay_modes = _overlay(Control.PRESET_TOP_RIGHT)
	_overlay_zoom = _overlay(Control.PRESET_BOTTOM_RIGHT)
	_refresh_overlays()


func _overlay(preset: int) -> MarginContainer:
	var m := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		m.add_theme_constant_override("margin_" + side, 10)
	m.set_anchors_and_offsets_preset(preset)
	m.grow_horizontal = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT] else Control.GROW_DIRECTION_END
	m.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset == Control.PRESET_BOTTOM_RIGHT else Control.GROW_DIRECTION_END
	_view_area.add_child(m)
	return m


func _refresh_overlays() -> void:
	for o: Control in [_overlay_view, _overlay_modes, _overlay_zoom]:
		for c in o.get_children():
			c.queue_free()
	var cockpit_ok := cockpit_view != null
	var view := Settings.view if cockpit_ok else "map"
	var sw := UiKit.seg([["cockpit", "Ohjaamo"], ["map", "Kartta"]], view, func(v: String) -> void:
		Settings.set_view(v)
		_apply_view()
		_refresh_overlays())
	if not cockpit_ok:
		var b: Button = sw.get_child(0).get_child(0)
		b.disabled = true
		b.tooltip_text = "3D-ohjaamo ei ole vielä käytössä"
	_overlay_view.add_child(sw)
	var on_map := view == "map"
	_overlay_modes.visible = on_map
	_overlay_zoom.visible = on_map
	_overlay_modes.add_child(UiKit.seg([[false, "Koko rata"], [true, "Alus"]], map.follow, func(v: bool) -> void:
		map.set_follow(v)
		_refresh_overlays()))
	var z := UiKit.hbox(4)
	var zin := UiKit.button("+", func() -> void: map.zoom(1.0 / 1.6))
	zin.tooltip_text = "Lähennä (+)"
	zin.custom_minimum_size = Vector2(36, 32)
	var zout := UiKit.button("−", func() -> void: map.zoom(1.6))
	zout.tooltip_text = "Loitonna (−)"
	zout.custom_minimum_size = Vector2(36, 32)
	z.add_child(zin)
	z.add_child(zout)
	_overlay_zoom.add_child(z)
	_apply_view()


func _apply_view() -> void:
	var cockpit := cockpit_view != null and Settings.view == "cockpit"
	map.visible = not cockpit
	if cockpit_view != null and cockpit_view.viewport != null:
		cockpit_view.visible = cockpit
		# Piilossa olevaa ohjaamoa ei piirretä.
		cockpit_view.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if cockpit else SubViewport.UPDATE_DISABLED


func _build_panel() -> void:
	_panel_scroll = ScrollContainer.new()
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_scroll.custom_minimum_size.x = PANEL_W
	_panel_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bg := StyleBoxFlat.new()
	bg.bg_color = UiKit.BG
	bg.border_color = UiKit.LINE
	bg.border_width_left = 1
	_panel_scroll.add_theme_stylebox_override("panel", bg)
	_panel_pad = MarginContainer.new()
	_panel_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_panel_pad.add_theme_constant_override("margin_" + side, 16)
	_body = UiKit.vbox(12)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_pad.add_child(_body)
	_panel_scroll.add_child(_panel_pad)


func _build_dialogs() -> void:
	_about = AcceptDialog.new()
	_about.title = "Sisunautti %s" % version()
	_about.ok_button_text = "Sulje"
	var v := UiKit.vbox(12)
	_about_box = v
	v.add_child(UiKit.label(ABOUT))
	v.add_child(UiKit.label(SOURCES, "MutedLabel"))
	v.add_child(UiKit.label("Grafiikan laatu", "TitleLabel"))
	var levels := []
	for i in Settings.max_quality() + 1:
		levels.append([i, Settings.QUALITY_NAMES[i]])
	_quality_seg = UiKit.seg(levels, Settings.quality, func(i: int) -> void: Settings.set_quality(i))
	v.add_child(_quality_seg)
	v.add_child(UiKit.label("Korkea ja Ultra: pehmeät varjot, varjojen peitto (SSAO) ja Ultralla heijastukset (SSR) sekä 8k-pintakartat. Selaimessa enintään Keski.", "MutedLabel"))
	v.add_child(UiKit.label("Aluksen häiriöt", "MutedLabel"))
	var faults := []
	for i in Settings.FAULT_NAMES.size():
		faults.append([i, Settings.FAULT_NAMES[i]])
	v.add_child(UiKit.seg(faults, Settings.faults, func(i: int) -> void: Settings.set_faults(i)))
	v.add_child(UiKit.label("Lennolla ja kiertoradalla aluksessa voi tulla vikoja, jotka on korjattava ajassa: johtojen kytkentä, ohjelmavirhe tai paineet. Muuten alus tuhoutuu.", "MutedLabel"))

	v.add_child(UiKit.label("Versio %s · %s" % [version(), "selain (Compatibility)" if Settings.is_compatibility() else "työpöytä (Forward+)"], "MutedLabel"))
	_about.add_child(v)
	add_child(_about)
	_confirm = ConfirmationDialog.new()
	_confirm.title = "Aloita alusta"
	_confirm.dialog_text = "Aloitetaanko alusta? Uusi lento lähtee laukaisualustalta Maan pinnalta täydellä polttoaineella."
	_confirm.dialog_autowrap = true
	_confirm.ok_button_text = "Aloita alusta"
	_confirm.cancel_button_text = "Peru"
	_confirm.confirmed.connect(func() -> void:
		_burn_open = false
		_burn_preview = {}
		map.preview = {}
		Game.restart())
	add_child(_confirm)


## Asettelu ikkunan leveyden mukaan: leveässä paneeli oikealla, kapeassa näkymän alla.
## Vierittää paneelin loppuun (kuvakaappaukset ja uudet vaihtoehdot).
func scroll_panel_to_end() -> void:
	var sc := _panel_scroll if _wide else _narrow_scroll
	sc.scroll_vertical = int(sc.get_v_scroll_bar().max_value)


func _layout() -> void:
	var wide := size.x >= WIDE_MIN
	# Kapeassa ikkunassa radiopainikkeessa vain kuvake, jotta yläpalkki mahtuu.
	_radio_btn.text = "♪ Radio" if size.x >= 520.0 else "♪"
	_radio_btn.custom_minimum_size.x = 0.0 if size.x >= 520.0 else 36.0
	_brand.visible = size.x >= 440.0
	if wide != _wide or _view_area.get_parent() == null:
		_wide = wide
		for n: Control in [_view_area, _panel_scroll, _panel_pad]:
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
		if wide:
			_wide_box.add_child(_view_area)
			_wide_box.add_child(_panel_scroll)
			_panel_scroll.add_child(_panel_pad)
		else:
			_narrow_box.add_child(_view_area)
			_narrow_box.add_child(_panel_pad)
	_wide_box.visible = wide
	_narrow_scroll.visible = not wide
	_panel_scroll.visible = wide and not Settings.panel_hidden
	_view_area.custom_minimum_size.y = 0.0 if wide else clampf(size.y * 0.46, 260.0, 520.0)
	_panel_btn.visible = wide
	_panel_btn.tooltip_text = ("Näytä" if Settings.panel_hidden else "Piilota") + " sivupaneeli (P)"


func toggle_panel() -> void:
	Settings.set_panel_hidden(not Settings.panel_hidden)
	_layout()


func toggle_fullscreen() -> void:
	var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)


# --- Paneelin sisältö ---

func _rebuild() -> void:
	_dirty = false
	_phase_key = _phase()
	_live.clear()
	map.preview = {} # kurssikorjauksen esikatselu vain, kun korjauspaneeli on auki
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	var s: Dictionary = Game.state
	_body.add_child(_status())
	if s.pad:
		_pad_view()
	elif s.flight != null:
		_flying()
	elif s.plan != null:
		_waiting()
	else:
		_orbiting()
	_update()


func _add(n: Control) -> Control:
	_body.add_child(n)
	return n


func _live_label(id: String, text: String = "", variation: String = "") -> Label:
	var l := UiKit.label(text, variation)
	_live[id] = l
	return l


func _actions(buttons: Array) -> HFlowContainer:
	var f := HFlowContainer.new()
	f.add_theme_constant_override("h_separation", 8)
	f.add_theme_constant_override("v_separation", 8)
	for b: Control in buttons:
		f.add_child(b)
	return f


func _status() -> Control:
	var s: Dictionary = Game.state
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	var where_t := ""
	var where_s := ""
	var t := Game.sim_now()
	if s.pad:
		var up: bool = s.ascent != null and t >= float(s.ascent.liftoff)
		where_t = "Nousussa kiertoradalle" if up else "Laukaisualustalla"
		where_s = "kantoraketin kyydissä" if up else "Maan pinnalla"
	elif s.flight != null:
		where_t = "Matkalla %s" % Fmt.ill(s.flight.to)
		where_s = "lähtö %s" % Fmt.from_text(s.flight.from)
	elif s.location != null:
		where_t = "%s kiertoradalla" % Fmt.gen(s.location)
		where_s = Fmt.orbit_text(s.location)
	else:
		where_t = "Auringon kiertoradalla"
		where_s = "ohilennon jälkeen"
	var a := UiKit.stat("Sijainti", where_t, where_s)
	a[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	g.add_child(a[0])
	var ship: Dictionary = Flight.SHIPS[s.ship]
	var f := UiKit.stat("Polttoaine (Δv) · %s" % ship.name, "%s / %s km/s" % [Fmt.num(s.fuel, 2), Fmt.num(Game.fuel_max())])
	f[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var bar := UiKit.progress(clampf(float(s.fuel) / Game.fuel_max(), 0.0, 1.0))
	f[0].get_child(0).add_child(bar)
	g.add_child(f[0])
	return g


func _warp_buttons(count: int = Game.WARPS.size()) -> Control:
	var items := []
	for i in count:
		items.append([i, Game.WARPS[i][1]])
	var sg := UiKit.seg(items, Game.warp_index(), func(i: int) -> void: Game.set_warp(i), true, 4 if count > 4 else 0)
	sg.tooltip_text = "Aikakiihdytys (näppäimet 1–8)"
	return sg


func _stats_grid(items: Array) -> GridContainer:
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 8)
	g.add_theme_constant_override("v_separation", 8)
	for it: Array in items:
		var st := UiKit.stat(it[0], "–", " ")
		st[0].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_live[it[1]] = st[1]
		if it.size() > 2:
			_live[it[2]] = st[2]
		else:
			st[2].visible = false
		g.add_child(st[0])
	return g


# Laukaisualusta ja nousu kiertoradalle.
func _pad_view() -> void:
	var s: Dictionary = Game.state
	if s.ascent == null:
		_add(UiKit.label("Alus on laukaisualustalla Maan pinnalla. Kantoraketti nostaa sen 200 km:n kiertoradalle noin 8,5 minuutissa. Aluksen omaa polttoainetta nousu ei kuluta."))
		_add(_shipyard())
		_add(_actions([UiKit.button("Aloita lähtölaskenta", Game.start_countdown, "GoButton")]))
		_add(_logbook())
		return
	var up := Game.sim_now() >= float(s.ascent.liftoff)
	_add(_live_label("count", "", "BigLabel"))
	_add(_stats_grid([["Vaihe", "phase"], ["Korkeus", "alt"], ["Nopeus maan suhteen", "aspeed", "aspeed_sub"], ["Kiihtyvyys", "g"]]))
	if up:
		_add(_warp_buttons(2))
		_add(UiKit.label("Vaihe 1 sammuu ja irtoaa 2 min 30 s kohdalla, ja vaihe 2 vie aluksen kiertoradalle. Aikaa voi kiihdyttää kymmenkertaiseksi.", "MutedLabel"))
	else:
		_add(_actions([UiKit.button("Keskeytä lähtölaskenta", Game.abort_countdown)]))


func _option_card(o: Dictionary) -> Control:
	var kind: Array = Game.KINDS[o.kind]
	var span: float = float(o.arrive) - float(o.depart)
	var title: String = "%s: %s" % [kind[0], o.via] if o.kind == "assist" else kind[0]
	var sub: String = kind[1]
	if o.kind == "assist":
		var fb: Dictionary = o.flyby
		sub = "Ohilento %s ohi %s%s" % [Fmt.gen(o.via), Fmt.date(fb.t), ", poltto %s" % Fmt.dv(fb.dv) if float(fb.dv) > 0.005 else ", ei polttoa"]
	elif o.kind == "local":
		sub = "Hohmannin siirto %s ympärillä" % Fmt.gen(o.parent)
	var c := UiKit.card()
	var v: VBoxContainer = c[1]
	var head := UiKit.hbox()
	var tl := UiKit.label(title, "TitleLabel", false)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(UiKit.label("jää %s km/s" % Fmt.num(float(Game.state.fuel) - float(o.dvTotal), 1) if o.fuelOk else "polttoaine ei riitä",
		"GoodLabel" if o.fuelOk else "WarnLabel", false))
	v.add_child(head)
	v.add_child(UiKit.label(sub, "MutedLabel"))
	var wait: float = float(o.depart) - Game.sim_now()
	var rows := [
		["Lähtö", "%s%s" % [Fmt.date(o.depart), " (%s päästä)" % Fmt.days(wait / DAY) if wait > DAY else ""]],
		["Lentoaika", Fmt.short_duration(span) if span < 2.0 * DAY else Fmt.days(span / DAY)],
		["Perillä", Fmt.date(o.arrive)],
		["Δv", "lähtö %s%s + jarrutus %s = %s" % [Fmt.dv(o.dvDep), " + linkous %s" % Fmt.dv(o.dvFlyby) if float(o.get("dvFlyby", 0.0)) > 0.005 else "", Fmt.dv(o.dvArr), Fmt.dv(o.dvTotal)]],
	]
	if float(o.get("spiralOut", 0.0)) > 0.0 or float(o.get("spiralIn", 0.0)) > 0.0:
		rows.append(["Spiraalit", "nousu alkaa %s (%s), lasku %s" % [Fmt.date(float(o.depart) - float(o.spiralOut)), Fmt.days(float(o.spiralOut) / DAY), Fmt.days(float(o.spiralIn) / DAY)]])
	v.add_child(UiKit.rows(rows))
	var pick := UiKit.button("Valitse reitti", func() -> void: Game.choose(o), "GoButton" if o.kind == "cheapest" or o.kind == "local" else "")
	pick.disabled = not o.fuelOk
	v.add_child(_actions([pick]))
	if not o.fuelOk:
		c[0].modulate = Color(1, 1, 1, 0.65)
	return c[0]


# Tietokortti. Kiinnostavat faktat paljastuvat, kun kohde on tutkittu.
func _info_card(name: String) -> Control:
	var info := PlanetInfo.of(name)
	var explored: bool = Game.state.explored.has(name)
	var c := UiKit.card()
	var v: VBoxContainer = c[1]
	var head := UiKit.hbox()
	var tl := UiKit.label(name, "TitleLabel", false)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(UiKit.label("tutkittu" if explored else "tutkimatta", "GoodLabel" if explored else "MutedLabel", false))
	v.add_child(head)
	var rows: Array
	if info.has("parent"):
		rows = [["Kiertää", info.parent], ["Rata", info.orbit], ["Halkaisija", info.diameter], ["Massa", info.mass],
			["Painovoima", info.gravity], ["Lämpötila", info.temperature], ["Kaasukehä", info.atmosphere]]
	else:
		rows = [["Halkaisija", info.diameter], ["Massa", info.mass], ["Painovoima", info.gravity], ["Vuorokausi", info.day],
			["Vuosi", info.year], ["Lämpötila", info.temperature], ["Kaasukehä", info.atmosphere], ["Kuut", info.moons]]
	v.add_child(UiKit.rows(rows))
	if explored:
		v.add_child(UiKit.label("Tutkimuksen löydöt", "TitleLabel"))
		for f: String in info.facts:
			v.add_child(UiKit.label("• " + f))
	return c[0]


func _survey_panel() -> Control:
	var s: Dictionary = Game.state
	var name: String = s.location
	var explored: bool = s.explored.has(name)
	var refuel := Flight.can_refuel(s.ship, name)
	var v := UiKit.vbox(8)
	var ship_name: String = Flight.SHIPS[s.ship].name
	var after := "ja sen jälkeen polttoaine täydennetään" if refuel else "mutta %sa ei voi tankata täällä (vetyä saa vain Maasta ja kaasujättiläisiltä)" % ship_name.to_lower()
	if s.survey != null:
		v.add_child(_live_label("survey_label", "", "MutedLabel"))
		var bar := UiKit.progress(0.0)
		_live["survey_bar"] = bar
		v.add_child(bar)
		v.add_child(_warp_buttons())
	elif not explored:
		v.add_child(UiKit.label("Tutki %s kiertoradalta. Kartoitus kestää vuorokauden, %s." % [Fmt.par(name), after]))
		v.add_child(_actions([UiKit.button("Tutki kuu" if Flight.is_moon(name) else "Tutki planeetta", Game.start_survey, "GoButton")]))
	elif refuel and float(s.fuel) < Game.fuel_max() - 0.005:
		v.add_child(UiKit.label("%s on jo tutkittu. Tankkaus kestää vuorokauden." % name, "MutedLabel"))
		v.add_child(_actions([UiKit.button("Tankkaa", Game.start_survey)]))
	return v


func _shipyard() -> Control:
	var s: Dictionary = Game.state
	var c := UiKit.card()
	var v: VBoxContainer = c[1]
	v.add_child(UiKit.label("Alus", "TitleLabel"))
	var items := []
	for id: String in Flight.SHIPS:
		items.append([id, Flight.SHIPS[id].name])
	v.add_child(UiKit.seg(items, s.ship, func(id: String) -> void: Game.change_ship(id), true))
	var ship: Dictionary = Flight.SHIPS[s.ship]
	v.add_child(UiKit.label("%s Δv-budjetti %s km/s." % [ship.text, Fmt.num(ship.fuel)], "MutedLabel"))
	return c[0]


func _collapsible(title: String, open: bool, on_toggle: Callable) -> Array:
	var c := UiKit.card()
	var v: VBoxContainer = c[1]
	var head := Button.new()
	head.text = ("▾ " if open else "▸ ") + title
	head.theme_type_variation = "SegButton"
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.add_theme_color_override("font_color", UiKit.FG)
	head.pressed.connect(func() -> void: on_toggle.call(not open))
	v.add_child(head)
	return [c[0], v]


func _logbook() -> Control:
	var s: Dictionary = Game.state
	var c := _collapsible("Lokikirja", _log_open, func(o: bool) -> void:
		_log_open = o
		_dirty = true)
	if not _log_open:
		return c[0]
	var v: VBoxContainer = c[1]
	var fl: Array = s.flights
	var total := 0.0
	var km := 0.0
	var top := 0.0
	for f: Dictionary in fl:
		total += float(f.arrive) - float(f.depart)
		km += float(f.km)
		top = maxf(top, float(f.maxSpeed))
	var planets: Array = s.explored.filter(func(n: String) -> bool: return not Flight.is_moon(n))
	var moons: Array = s.explored.filter(func(n: String) -> bool: return Flight.is_moon(n))
	v.add_child(UiKit.rows([
		["Tutkitut planeetat", "%d/8: %s" % [planets.size(), ", ".join(planets)]],
		["Tutkitut kuut", "%d/%d%s" % [moons.size(), Flight.MOONS.size(), ": " + ", ".join(moons) if not moons.is_empty() else ""]],
		["Lentoja", str(fl.size())],
		["Lentoaika yhteensä", Fmt.days(total / DAY) if not fl.is_empty() else "–"],
		["Kuljettu matka", Fmt.km(km) if not fl.is_empty() else "–"],
		["Huippunopeus", "%s km/s (%s km/h)" % [Fmt.num(top, 2), Fmt.num(top * 3600.0)] if not fl.is_empty() else "–"],
	]))
	if not fl.is_empty():
		v.add_child(UiKit.label("Lennot", "TitleLabel"))
		for i in range(fl.size() - 1, -1, -1):
			var f: Dictionary = fl[i]
			v.add_child(UiKit.label("%s → %s%s" % [f.fromName, f.to, "" if f.captured else " (ohilento)"]))
			v.add_child(UiKit.label("%s–%s · %s · %s" % [Fmt.date(f.depart).substr(3), Fmt.date(f.arrive).substr(3),
				Fmt.days((float(f.arrive) - float(f.depart)) / DAY), Fmt.km(f.km)], "MutedLabel"))
	var log: Array = s.log
	if not log.is_empty():
		v.add_child(UiKit.label("Tapahtumat", "TitleLabel"))
		for i in range(log.size() - 1, maxi(-1, log.size() - 31), -1):
			var e: Dictionary = log[i]
			v.add_child(UiKit.label(Fmt.date(e.t), "MutedLabel"))
			v.add_child(UiKit.label(e.text))
	return c[0]


func _restart_button(text: String = "Aloita alusta") -> Button:
	return UiKit.button(text, show_restart)


# Dialogin leveys ikkunan mukaan; tekstien vähimmäisleveys asetetaan, jotta rivitys ja korkeus lasketaan oikein.
func _popup(d: AcceptDialog, content: Control, max_w: int) -> void:
	var w := mini(max_w, int(size.x) - 32)
	content.custom_minimum_size.x = w - 40
	d.popup_centered(Vector2i(w, 0))
	# Rivitettyjen tekstien korkeus tiedetään vasta, kun leveys on asetettu: kutistetaan sisällön mukaan.
	await get_tree().process_frame
	d.size = Vector2i(w, 0)
	d.reset_size()
	d.move_to_center()


## Radiopaneeli yläpalkin painikkeen alle: kanavat, soiva kappale, seuraava kappale, sammutus ja voimakkuus.
func show_radio() -> void:
	var radio := get_tree().get_first_node_in_group("radio") as Radio
	if radio == null:
		return
	if _radio_popup == null:
		_radio_popup = PopupPanel.new()
		_radio_popup.add_theme_stylebox_override("panel", UiKit.box(Color(UiKit.CARD, 0.97), Color(UiKit.ACCENT, 0.35), 12, 16))
		add_child(_radio_popup)
		radio.changed.connect(func() -> void:
			if _radio_popup.visible:
				_fill_radio(radio))
	_fill_radio(radio)
	var w := mini(340, int(size.x) - 16)
	var p := _radio_btn.get_global_rect()
	var x := clampi(int(p.end.x) - w, 8, int(size.x) - w - 8)
	_radio_popup.popup(Rect2i(Vector2i(x, int(p.end.y) + 6), Vector2i(w, 0)))


func _fill_radio(radio: Radio) -> void:
	for c in _radio_popup.get_children():
		c.queue_free()
	var v := UiKit.vbox(10)
	_radio_popup.add_child(v)
	v.add_child(UiKit.label("♪ Radio", "TitleLabel"))
	var np := radio.now_playing()
	if np.is_empty():
		v.add_child(UiKit.label("Radio on pois päältä. Valitse kanava.", "MutedLabel"))
	else:
		v.add_child(UiKit.label("Soi: " + String(np[0])))
		v.add_child(UiKit.label(String(np[1]), "MutedLabel"))
	for i in Radio.CHANNELS.size():
		var b := UiKit.button(String(Radio.CHANNELS[i][0]), radio.tune.bind(i), "GoButton" if i == radio.channel else "")
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(b)
	var row := UiKit.hbox(8)
	var nxt := UiKit.button("Seuraava kappale", radio.next_track)
	nxt.disabled = radio.channel < 0
	row.add_child(nxt)
	var off := UiKit.button("Sammuta", radio.tune.bind(-1))
	off.disabled = radio.channel < 0
	row.add_child(off)
	v.add_child(row)
	v.add_child(UiKit.label("Musiikin voimakkuus", "MutedLabel"))
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = Settings.music_volume
	slider.value_changed.connect(func(x: float) -> void: Settings.set_music_volume(x))
	v.add_child(slider)
	_radio_popup.reset_size.call_deferred()


## Pelin versio (project.godot), näytetään Tietoa-ikkunassa.
static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version"))


func show_about() -> void:
	_popup(_about, _about_box, 560)


func show_restart() -> void:
	_popup(_confirm, _confirm.get_label(), 460)


func _orbiting() -> void:
	var s: Dictionary = Game.state
	var loc: Variant = s.location
	if loc != null:
		_add(_info_card(loc))
		_add(_survey_panel())
	else:
		_add(UiKit.label("Polttoaine ei riittänyt jarrutukseen, joten alus ohitti kohteen ja kiertää nyt Aurinkoa. Suunnittele uusi reitti, jos polttoaine riittää, tai aloita alusta."))
	if s.survey == null:
		_add(_warp_buttons())
	if Game.notice != "":
		_add(UiKit.label(Game.notice, "WarnLabel"))
	if s.survey != null:
		_add(_logbook())
		return
	if loc == "Maa":
		_add(_shipyard())
	_add(UiKit.label("Valitse kohde", "HeadLabel"))
	var target_btn := func(name: String, on_press: Callable) -> Button:
		var b := UiKit.button(name + ("" if s.explored.has(name) else " •"), on_press)
		b.toggle_mode = true
		b.button_pressed = name == Game.target
		if not s.explored.has(name):
			b.tooltip_text = "tutkimatta"
		return b
	var targets := HFlowContainer.new()
	targets.add_theme_constant_override("h_separation", 6)
	targets.add_theme_constant_override("v_separation", 6)
	if Flight.is_moon(loc):
		# Kuusta palataan emoplaneetan kiertoradalle, ja sieltä voi jatkaa muualle.
		var parent: String = Flight.MOONS[loc].parent
		targets.add_child(target_btn.call(parent, func() -> void: Game.local_option(parent)))
		_add(targets)
		_add(UiKit.label("Kuusta lennetään ensin takaisin %s kiertoradalle." % Fmt.gen(parent), "MutedLabel"))
	else:
		for name in Planets.NAMES:
			if name != loc:
				var n := name
				targets.add_child(target_btn.call(n, func() -> void: Game.begin_search(n)))
		_add(targets)
		var moons := Flight.moons_of(loc) if loc != null else PackedStringArray()
		if not moons.is_empty():
			_add(UiKit.label("%s kuut" % Fmt.gen(loc), "TitleLabel"))
			var row := HFlowContainer.new()
			row.add_theme_constant_override("h_separation", 6)
			for m in moons:
				var mm := m
				row.add_child(target_btn.call(mm, func() -> void: Game.local_option(mm)))
			_add(row)
	if Game.target == "":
		_add(UiKit.label("Peli laskee siirtoradan valmiiksi: se etsii seuraavan kahden vuoden laukaisuikkunat ja näyttää halvimman sekä nopeammat vaihtoehdot. Tutkimattomat kohteet on merkitty pisteellä. Polttoaine täydentyy, kun kohde on tutkittu.", "MutedLabel"))
	elif not Game.options_ready:
		_add(UiKit.label("Haetaan laukaisuikkunoita ja linkousreittejä: %s %s…" % [Fmt.from_text(Game.here()), Fmt.ill(Game.target)], "MutedLabel"))
		var bar := UiKit.progress(Game.progress)
		_live["search_bar"] = bar
		_add(bar)
	elif Game.options.is_empty():
		_add(UiKit.label("Siirtorataa ei löytynyt. Kokeile toista kohdetta.", "MutedLabel"))
	else:
		_add(UiKit.label("Lento %s" % Fmt.ill(Game.target), "HeadLabel"))
		for o: Dictionary in Game.options:
			_add(_option_card(o))
		if Game.options.all(func(o: Dictionary) -> bool: return not o.fuelOk):
			var msg := "Polttoaine ei riitä yhteenkään vaihtoehtoon."
			if loc != null and not s.explored.has(loc):
				msg = "Polttoaine ei riitä yhteenkään vaihtoehtoon. Tutki planeetta, niin polttoaine täydennetään."
			elif loc != null:
				msg = "Polttoaine ei riitä yhteenkään vaihtoehtoon. Tankkaa tai valitse lähempi kohde."
			_add(UiKit.label(msg, "MutedLabel"))
	_add(_logbook())
	if not s.log.is_empty():
		_add(_actions([_restart_button()]))


func _waiting() -> void:
	var s: Dictionary = Game.state
	var p: Dictionary = s.plan
	var ion := float(p.get("spiralOut", 0.0)) > 0.0
	var ready := Game.sim_now() >= Game.hold_at()
	_add(UiKit.label("Lento %s" % Fmt.ill(p.to), "HeadLabel"))
	var rows := [["Lähtö", Fmt.date(p.depart)], ["Lentoaika", Fmt.days((float(p.arrive) - float(p.depart)) / DAY)], ["Perillä", Fmt.date(p.arrive)],
		["Δv", "%s%s + %s = %s" % [Fmt.dv(p.dvDep), " + %s" % Fmt.dv(p.dvFlyby) if float(p.get("dvFlyby", 0.0)) > 0.005 else "", Fmt.dv(p.dvArr), Fmt.dv(p.dvTotal)]]]
	var fb: Variant = p.get("flyby")
	if fb is Dictionary:
		rows.insert(2, ["Linkous", "%s %s" % [fb.body, Fmt.date(fb.t)]])
	if ion:
		rows.append(["Spiraalinousu", "%s alkaen, %s" % [Fmt.date(float(p.depart) - float(p.spiralOut)), Fmt.days(float(p.spiralOut) / DAY)]])
	_add(UiKit.rows(rows))
	if ion and p.get("spiralStarted", false):
		_add(_live_label("count", "", "BigLabel"))
		_add(UiKit.label("Ionimoottori kiihdyttää alusta spiraalina ulospäin. Siirtorata alkaa, kun spiraali on valmis.", "MutedLabel"))
		var bar := UiKit.progress(0.0)
		_live["spiral_bar"] = bar
		_add(bar)
		_add(_warp_buttons())
		return
	_add(_live_label("count", "", "BigLabel"))
	var cancel := UiKit.button("Peru lento", Game.cancel_plan)
	var local: bool = p.get("local", false)
	if p.get("armed", false):
		var text := Game.notice
		if text == "":
			text = ("Lähtöpoltto on päällä. Alus kiertää %s nokka menosuuntaan, ja moottori syttyy itsestään, kun alus on radalla kohdassa, josta poltto linkoaa sen kohti %s." % [Fmt.par(p.from), Fmt.par(p.to)]) if Flight.is_planet(p.from) and not local else "Lähtöpoltto on päällä. Moottori syttyy itsestään, kun lähtölaskenta päättyy."
		_add(UiKit.label(text, "MutedLabel"))
		_add(_warp_buttons())
		_add(_actions([UiKit.button("Lähtöpoltto pois", Game.disarm), cancel]))
	elif not ready:
		_add(UiKit.label("Odota laukaisuikkunaa tai kiihdytä aikaa. Kello pysähtyy ikkunan avautuessa, joten se ei mene ohi.", "MutedLabel"))
		_add(_warp_buttons())
		_add(_actions([UiKit.button("Siirry spiraalin alkuun" if ion else "Siirry ikkunan alkuun", Game.jump_to_window), cancel]))
	elif ion:
		_add(UiKit.label("Spiraalinousu kuluttaa %s polttoainetta ja kestää %s." % [Fmt.dv(p.dvDep), Fmt.days(float(p.spiralOut) / DAY)], "MutedLabel"))
		_add(_actions([UiKit.button("Aloita spiraalinousu", Game.start_spiral, "GoButton"), cancel]))
	else:
		var wait := " Polttokohtaan on enintään %s." % Fmt.short_duration(Flight.orbit_period(p.from) * 1000.0) if Flight.is_planet(p.from) and not local else ""
		var text := Game.notice if Game.notice != "" else "Laukaisuikkuna on auki. Kytke lähtöpoltto päälle: alus jatkaa kiertorataa ja polttaa moottorin, kun se on oikeassa kohdassa.%s Poltto kuluttaa %s polttoainetta." % [wait, Fmt.dv(p.dvDep)]
		_add(UiKit.label(text, "MutedLabel"))
		_add(_actions([UiKit.button("Lähtöpoltto päälle", Game.arm, "GoButton"), cancel]))


func _forecast(f: Dictionary) -> String:
	if f.get("miss", false):
		return "ohittaa %s %s etäisyydeltä %s (vaikutuspiiri %s)" % [Fmt.par(f.to), Fmt.km(f.missKm), Fmt.date(f.arrive), Fmt.km(Flight.body(f.to).soiKm)]
	return "saapuu %s luo %s, jarrutus %s" % [Fmt.gen(f.to), Fmt.date(f.arrive), Fmt.dv(f.dvArr)]


# Kurssikorjaukset: poltto valittuun suuntaan, ennuste ennen polttoa ja automaattinen korjaus kohteeseen.
func _burn_panel() -> Control:
	var f: Dictionary = Game.state.flight
	var c := _collapsible("Kurssikorjaus", _burn_open, func(o: bool) -> void:
		_burn_open = o
		_burn_preview = {}
		map.preview = {}
		_dirty = true)
	if not _burn_open:
		return c[0]
	var v: VBoxContainer = c[1]
	var t := Game.sim_now()
	if _burn_preview.is_empty():
		_burn_preview = Flight.apply_burn(f, t, _burn_dir, _burn_dv)
	map.preview = _burn_preview
	v.add_child(UiKit.label("Nykyinen rata %s." % _forecast(f), "MutedLabel"))
	v.add_child(UiKit.seg(BURN_DIRS, _burn_dir, func(d: String) -> void:
		_burn_dir = d
		_burn_preview = {}
		_dirty = true, true))
	v.add_child(UiKit.seg(BURN_SIZES, _burn_dv, func(d: float) -> void:
		_burn_dv = d
		_burn_preview = {}
		_dirty = true, true))
	v.add_child(UiKit.label("Polton jälkeen rata %s." % _forecast(_burn_preview)))
	var size_label := ""
	for it: Array in BURN_SIZES:
		if it[0] == _burn_dv:
			size_label = it[1]
	var burn := UiKit.button("Polta %s" % size_label, func() -> void:
		if Game.burn(_burn_dir, _burn_dv, size_label):
			_burn_preview = {}
			map.preview = {}, "GoButton")
	burn.disabled = float(Game.state.fuel) < _burn_dv
	var buttons: Array = [burn]
	var fix := Game.auto_correction()
	if not fix.is_empty():
		var auto := UiKit.button("Korjaa kurssi kohteeseen (%s)" % Fmt.dv(fix.dv), func() -> void:
			if Game.auto_correct():
				_burn_preview = {}
				map.preview = {})
		auto.disabled = float(Game.state.fuel) < float(fix.dv)
		buttons.append(auto)
	v.add_child(_actions(buttons))
	v.add_child(UiKit.label("Poltto näkyy kartalla vihreänä katkoviivana ennen kuin sen tekee. Polttoaine kuluu polton verran.", "MutedLabel"))
	return c[0]


# Ilmajarrutus jättiläisplaneetalla: kuvaus ja painike, tai tyhjä, jos se ei ole mahdollinen.
func _aero_option(f: Dictionary) -> Array:
	if not Game.can_aerobrake():
		return []
	var b := Flight.body(f.to)
	var cost := Flight.aerobrake_dv(f.to)
	var alt := Fmt.num(float(b.low.periKm) - float(b.radiusKm))
	var low_orbit := {"mu": b.mu, "periKm": b.low.periKm, "apoKm": b.low.apoKm}
	var high_orbit := {"mu": b.mu, "periKm": b.capture.periKm, "apoKm": b.capture.apoKm}
	var leave_low := Flight.burn_dv(f.to, f.vinfArr, low_orbit)
	var leave_high := Flight.burn_dv(f.to, f.vinfArr, high_orbit)
	var ship: Dictionary = Flight.SHIPS[Game.state.ship]
	var stuck := " %s (%s km/s) ei pääse sieltä enää pois." % [ship.name, Fmt.num(Game.fuel_max())] if leave_low > Game.fuel_max() else ""
	return [UiKit.label("Ilmajarrutus: alus sukeltaa %s kaasukehän yläosaan, ja ilmanvastus jarruttaa sen %s km:n ympyräradalle. Polttoainetta kuluu vain radan nostoon (%s). Lähtö matalalta radalta on kallis: noin %s, kun venyneeltä radalta se on noin %s.%s" % [Fmt.gen(f.to), alt, Fmt.dv(cost), Fmt.dv(leave_low), Fmt.dv(leave_high), stuck]),
		_actions([UiKit.button("Ilmajarruta matalalle radalle", func() -> void: Game.capture(true), "GoButton")])]


func _flying() -> void:
	var s: Dictionary = Game.state
	var f: Dictionary = s.flight
	var arrived := Game.sim_now() >= float(f.arrive)
	var local: bool = f.get("local", false)
	_add(_live_label("met", "", "BigLabel"))
	_add(_stats_grid([["Nopeus %s suhteen" % Fmt.gen(f.parent) if local else "Nopeus Auringon suhteen", "speed", "speed_sub"],
		["Etäisyys %s" % Fmt.par(f.to), "dist", "eta"], ["Etäisyys Auringosta", "sun"], ["Valon kulkuaika Maahan", "light"]]))
	var fuel: float = s.fuel
	if arrived and f.get("miss", false):
		_add(UiKit.label("Alus ohitti %s %s etäisyydeltä, vaikutuspiirin ulkopuolelta. Se jatkaa Auringon ympäri." % [Fmt.par(f.to), Fmt.km(f.missKm)]))
		_add(_actions([UiKit.button("Jatka ohilentoa", func() -> void: Game.capture(), "GoButton")]))
	elif arrived and fuel >= float(f.dvArr) - 1e-9:
		var aero := _aero_option(f)
		for n: Control in aero:
			_add(n)
		var spiral := float(f.get("spiralIn", 0.0)) > 0.0
		_add(UiKit.label(("Alus on %s luona. Spiraalilasku (%s, %s) vie sen kiertoradalle %s." % [Fmt.gen(f.to), Fmt.dv(f.dvArr), Fmt.days(float(f.spiralIn) / DAY), Fmt.orbit_text(f.to)]) if spiral
			else "Alus on %s luona. Jarrutuspoltto (%s) vie sen kiertoradalle %s." % [Fmt.gen(f.to), Fmt.dv(f.dvArr), Fmt.orbit_text(f.to)]))
		var text := "Aloita spiraalilasku" if spiral else ("Jarruta moottorilla venyneelle radalle" if not aero.is_empty() else "Jarruta kiertoradalle")
		_add(_actions([UiKit.button(text, func() -> void: Game.capture(), "" if not aero.is_empty() else "GoButton")]))
	elif arrived and local:
		_add(UiKit.label("Polttoaine (%s) ei riitä jarrutukseen (%s)." % [Fmt.dv(fuel), Fmt.dv(f.dvArr)]))
		_add(_actions([_restart_button()]))
	elif arrived:
		var aero := _aero_option(f)
		for n: Control in aero:
			_add(n)
		_add(UiKit.label("Alus on %s luona, mutta polttoaine (%s) ei riitä moottorijarrutukseen (%s). %s ohittaa planeetan ja jatkaa Auringon ympäri." % [Fmt.gen(f.to), Fmt.dv(fuel), Fmt.dv(f.dvArr), "Ilman ilmajarrutusta alus" if not aero.is_empty() else "Alus"]))
		_add(_actions([UiKit.button("Jatka ohilentoa", func() -> void: Game.capture(), "" if not aero.is_empty() else "GoButton")]))
	else:
		_add(_warp_buttons())
		var text := Game.notice
		if text == "":
			var fb: Variant = f.get("flyby")
			var flyby := "Linkous %s ohi %s %s korkeudelta. " % [Fmt.gen(fb.body), Fmt.date(fb.t), Fmt.km(float(fb.rpKm) - float(Flight.body(fb.body).radiusKm))] if fb is Dictionary and not fb.get("done", false) else ""
			if local:
				text = "Perillä %s %s." % [Fmt.date(f.arrive), Fmt.clock(f.arrive)]
			elif f.get("miss", false):
				text = "Nykyinen rata %s. Tee kurssikorjaus, jotta alus osuu vaikutuspiiriin." % _forecast(f)
			else:
				text = "%s%s vaikutuspiiriin %s. Kiihdytys pienenee automaattisesti ennen tapahtumia." % [flyby, Fmt.gen(f.to), Fmt.date(f.soi)]
		_add(UiKit.label(text, "WarnLabel" if Game.notice != "" else "MutedLabel"))
		# Ionialus ei voi tehdä hetkellisiä polttoja, eikä paikallisella siirrolla tarvita korjauksia.
		if not local and float(f.get("spiralIn", 0.0)) <= 0.0:
			_add(_burn_panel())
	_add(_actions([_restart_button("Keskeytä lento")]))


# --- Mittarit ---

static func pad_clock(tau: float) -> String:
	if is_inf(tau) and tau < 0.0:
		return "valmiina"
	var sec := int(ceilf(-tau)) if tau < 0.0 else int(floorf(tau))
	return "T%s %02d.%02d" % ["−" if tau < 0.0 else "+", sec / 60, sec % 60]


## Lennon mittarit (voyage.js: readouts).
func readouts(t: float) -> Dictionary:
	var s: Dictionary = Game.state
	var f: Variant = s.flight
	var tr: Dictionary = f if f != null else s.plan
	var ship: Dictionary = Flight.ship_state(f, t) if f != null else Flight.departure_state(tr.from, t)
	var local: bool = f != null and f.get("local", false)
	var speed := Flight.norm(ship.rel.v) if local else Flight.norm(ship.v)
	var near: Dictionary
	if local:
		near = {"name": f.parent, "speed": Flight.norm(ship.rel.v)}
	elif f != null or not Flight.is_planet(tr.from):
		near = Flight.nearest_planet(ship.r, ship.v, t)
	else:
		near = {"name": tr.from, "speed": 0.0}
	var arrive: float = tr.arrive
	# Etäisyydet näkymän paikasta kohteen pintaan (#41), kuten ohjaamossa.
	var view_r: PackedFloat64Array = CockpitState._view_r(f, ship, t)
	return {
		"met": "T+ %s" % Flight.fmt_duration(t - float(f.depart)) if f != null else "T− %s" % Flight.fmt_duration(float(tr.depart) - t),
		"speed": speed, "near": near,
		"dist": Fmt.km(Flight.surface_distance(view_r, tr.to, t)),
		"eta": "perillä %s, T− %s" % [Fmt.date(arrive), Flight.fmt_duration(arrive - t)] if t < arrive else "perillä",
		"sun": Fmt.km(Flight.norm(view_r)),
		"light": Fmt.light_time(Flight.norm(Flight.sub(view_r, Flight.planet_state("Maa", t).r))),
	}


func _set_text(id: String, text: String) -> void:
	var n: Variant = _live.get(id)
	if n is Label:
		n.text = text


func _update() -> void:
	var s: Dictionary = Game.state
	var t := Game.sim_now()
	_date.text = Fmt.date(t)
	_time.text = "%s · %s" % [Fmt.clock(t), Game.WARPS[Game.warp_index()][1]]
	if s.pad and s.ascent != null:
		var L := Flight.launch_state(s.ascent.liftoff, t)
		_set_text("count", pad_clock(L.tau))
		_set_text("phase", L.phase)
		_set_text("alt", "%s km" % (Fmt.num(L.alt, 1) if L.alt < 10.0 else Fmt.num(L.alt)))
		_set_text("aspeed", "%s km/s" % Fmt.num(L.speed, 2))
		_set_text("aspeed_sub", "%s km/h" % Fmt.num(L.speed * 3600.0))
		_set_text("g", "%s g" % Fmt.num(L.g, 1))
	if s.plan != null:
		var p: Dictionary = s.plan
		var left := Game.hold_at() - t
		if p.get("spiralStarted", false):
			var fr := minf(1.0, 1.0 - (float(p.depart) - t) / float(p.spiralOut))
			var bar: Variant = _live.get("spiral_bar")
			if bar is ProgressBar:
				bar.value = fr
			_set_text("count", "Spiraali %s %% · T− %s" % [Fmt.num(fr * 100.0), Flight.fmt_duration(float(p.depart) - t)])
		else:
			_set_text("count", "%sT− %s" % ["Poltto " if p.get("armed", false) else "", Fmt.short_duration(left)] if left > 0.0 else "T− 0")
	if s.survey != null:
		var sv: Dictionary = s.survey
		var dur: float = float(sv.dur) if sv.get("dur") != null else Game.SURVEY_MS
		var end: float = float(sv.start) + dur
		var fr := clampf((t - float(sv.start)) / dur, 0.0, 1.0)
		var bar: Variant = _live.get("survey_bar")
		if bar is ProgressBar:
			bar.value = fr
		var what: String = "Spiraalilasku kiertoradalle" if sv.kind == "spiral" else ("Tankkaus" if s.explored.has(sv.body) else "Kartoitus: %s" % sv.body)
		_set_text("survey_label", "%s %s %% · valmis %s %s" % [what, Fmt.num(fr * 100.0), Fmt.date(end), Fmt.clock(end)])
	if s.flight == null:
		return
	var r := readouts(t)
	_set_text("met", r.met)
	_set_text("speed", "%s km/s" % Fmt.num(r.speed, 2))
	_set_text("speed_sub", "%s km/h · %s suhteen %s km/s" % [Fmt.num(r.speed * 3600.0), Fmt.gen(r.near.name), Fmt.num(r.near.speed, 2)])
	_set_text("dist", r.dist)
	_set_text("eta", r.eta)
	_set_text("sun", r.sun)
	_set_text("light", r.light)
