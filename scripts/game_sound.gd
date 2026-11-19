class_name GameSound
extends Node
## Pelin äänet: silmukat (laukaisun jyrinä, moottorin poltto, ilmajarrutuksen plasma, ohjaamon taustaääni), joiden
## voimakkuus seuraa ohjaamon tilaa (CockpitState), sekä kertaäänet: painikkeiden napsautus, lähtölaskennan
## piippaukset ja ilmoitukset (kiertorata, lähtöpoltto, vaikutuspiiri, saapuminen, kartoitus). Äänet syntetisoidaan
## käynnistyksessä (SoundSynth), paitsi ohjaamon taustaääni, joka on äänite (AMBIENT). Voimakkuus ja mykistys ovat
## Settingsissä (pääväylä). quiet: valikko auki.

const LOOPS := ["rumble", "burn", "plasma", "hum"]
## Ohjaamon taustaääni: freesound_community, Spaceship Ambient (Pixabay), saumattomaksi silmukaksi leikattuna.
const AMBIENT := "res://assets/sound/ohjaamo_tausta.ogg"

var quiet := false
var _loops := {} # nimi → AudioStreamPlayer
var _levels := {} # nimi → nykyinen taso 0–1 (pehmennetty)
var _click: AudioStreamWAV
var _chimes := {} # nimi → AudioStreamWAV
var _beep: AudioStreamWAV
var _go: AudioStreamWAV
var _state_at := -1000
var _target := {}
var _last_count := 99


func _ready() -> void:
	var make := {"rumble": SoundSynth.rumble, "burn": SoundSynth.burn, "plasma": SoundSynth.plasma}
	for name: String in LOOPS:
		var p := AudioStreamPlayer.new()
		p.stream = ambient() if name == "hum" else SoundSynth.to_wav(make[name].call(), true)
		p.volume_db = -80.0
		add_child(p)
		_loops[name] = p
		_levels[name] = 0.0
		_target[name] = 0.0
	_click = SoundSynth.to_wav(SoundSynth.click(), false)
	_beep = SoundSynth.to_wav(SoundSynth.beep(880.0, 0.12), false)
	_go = SoundSynth.to_wav(SoundSynth.beep(1320.0, 0.35), false)
	for c: Array in [["orbit", [523.25, 659.25, 783.99, 1046.5]], ["depart", [392.0, 523.25, 659.25]],
			["soi", [880.0, 659.25]], ["arrive", [659.25, 783.99, 987.77, 1318.5]], ["survey", [783.99, 1046.5]], ["notice", [987.77]]]:
		_chimes[c[0]] = SoundSynth.to_wav(SoundSynth.chime(c[1]), false)
	Game.orbit_reached.connect(func(_b: String) -> void: play_chime("orbit"))
	Game.departure_burn.connect(func(_f: Dictionary) -> void: play_chime("depart"))
	Game.soi_entered.connect(func(_b: String) -> void: play_chime("soi"))
	Game.arrived.connect(func(_b: String) -> void: play_chime("notice"))
	Game.capture_done.connect(func(_b: String, ok: bool, _a: bool) -> void: play_chime("arrive" if ok else "soi"))
	Game.survey_finished.connect(func(_b: String, _f: bool) -> void: play_chime("survey"))
	get_tree().node_added.connect(_on_node_added)
	_hook_buttons.call_deferred(get_tree().root)


## Ohjaamon taustaääni silmukkana.
static func ambient() -> AudioStreamOggVorbis:
	var s: AudioStreamOggVorbis = (load(AMBIENT) as AudioStreamOggVorbis).duplicate()
	s.loop = true
	return s


## Silmukoiden tavoitetasot (0–1) ohjaamon tilasta: laukaisussa jyrinä tärinän ja työnnön mukaan, poltoissa
## moottori, ilmajarrutuksessa plasma ja aina hiljainen ohjaamon taustaääni.
static func levels(s: Dictionary, pad: bool) -> Dictionary:
	var shake := clampf(float(s.get("shake", 0.0)), 0.0, 1.0)
	var thrust := clampf(float(s.get("thrust", 0.0)), 0.0, 1.0)
	var aero := clampf(float(s.get("aero", 0.0)), 0.0, 1.0)
	var launching := pad and float(s.get("tau", -INF)) >= -3.0
	return {"rumble": clampf(shake * 0.8 + thrust * 0.5, 0.0, 1.0) if launching else shake * 0.4,
		"burn": thrust * (0.55 if launching else 1.0), "plasma": aero, "hum": 0.35}


func _process(delta: float) -> void:
	if Game.state.is_empty():
		return
	var now := Time.get_ticks_msec()
	if now - _state_at > 66:
		_state_at = now
		var s := CockpitState.make()
		_target = levels(s, Game.state.pad)
		if quiet:
			for k: String in _target:
				_target[k] = 0.0
		_countdown(s)
	for name: String in LOOPS:
		var lv: float = lerpf(float(_levels[name]), float(_target.get(name, 0.0)), minf(1.0, delta * 4.0))
		_levels[name] = lv
		var p: AudioStreamPlayer = _loops[name]
		if lv > 0.003:
			p.volume_db = linear_to_db(lv)
			if not p.playing:
				p.play()
		elif p.playing:
			p.stop()


# Lähtölaskennan viimeiset 5 sekuntia piippaavat, ja sytytyksessä korkeampi ääni.
func _countdown(s: Dictionary) -> void:
	var tau := float(s.get("tau", -INF))
	if not Game.state.pad or not is_finite(tau) or tau < -10.5 or tau > 0.5 or quiet:
		_last_count = 99
		return
	var count := ceili(-tau)
	if count != _last_count and count <= 5:
		_play(_go if count <= 0 else _beep, -6.0)
	_last_count = count


func play_chime(name: String) -> void:
	if not quiet and _chimes.has(name):
		_play(_chimes[name], -4.0)


func _play(stream: AudioStream, db: float) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = db
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()


func click() -> void:
	_play(_click, -10.0)


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(click):
		(n as BaseButton).pressed.connect(click)


func _hook_buttons(n: Node) -> void:
	_on_node_added(n)
	for c in n.get_children():
		_hook_buttons(c)


## Silmukan nykyinen taso (testit).
func level(name: String) -> float:
	return float(_levels.get(name, 0.0))
