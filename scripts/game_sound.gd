class_name GameSound
extends Node
## Pelin äänet: silmukat (laukaisun jyrinä, moottorin poltto, ilmajarrutuksen plasma, ohjaamon taustahumina), joiden
## voimakkuus seuraa ohjaamon tilaa (CockpitState), painikkeiden napsautus ja lennonjohdon puhe. Puhe on yhtä ja
## samaa ääntä (tools/make_voice.py): lähtölaskenta kymmenestä, "liftoff", tornin ohitus, Max Q, vaiheen erotus
## 2:30 ja toisen vaiheen sytytys sekä lennon vaiheiden kuulutukset Quindar-piippauksin (kiertorata, lähtöpoltto,
## vaikutuspiiri, saapuminen, jarrutus kiertoradalle). Repliikit soivat jonossa, eivät päällekkäin. Kartoituksen
## valmistuminen kuittaa pelkällä Quindar-piippauksella. Muut äänet syntetisoidaan käynnistyksessä (SoundSynth).
## Voimakkuus ja mykistys ovat Settingsissä (pääväylä). quiet: valikko auki.

const LOOPS := ["rumble", "burn", "plasma", "hum"]
## Lennonjohdon repliikit: assets/sound/voice/<nimi>.ogg.
const VOICE_DIR := "res://assets/sound/voice/"
const VOICES := ["count1", "count2", "count3", "count4", "count5", "count6", "count7", "count8", "count9", "count10",
	"liftoff", "tower", "maxq", "staging", "stage2", "orbit", "depart", "soi", "arrive", "capture", "flyby"]
## Vaiheet, joista kuuluu kuulutus; muut ilmoitukset kuittaa pelkkä piippaus.
const CALLOUTS := ["orbit", "depart", "soi", "arrive", "capture", "flyby"]
## Laukaisun repliikit: [hetki laukaisusta (s), repliikki]. Lähtölaskennan luvut sekunnin välein.
const LAUNCH_LINES := [[-10.0, "count10"], [-9.0, "count9"], [-8.0, "count8"], [-7.0, "count7"], [-6.0, "count6"],
	[-5.0, "count5"], [-4.0, "count4"], [-3.0, "count3"], [-2.0, "count2"], [-1.0, "count1"], [0.0, "liftoff"],
	[9.0, "tower"], [66.0, "maxq"], [150.0, "staging"], [158.0, "stage2"]]
## Jonossa odottanut repliikki jätetään soittamatta, kun se on vanhentunut (ms).
const QUEUE_MAX_MS := 6000

var quiet := false
var _loops := {} # nimi → AudioStreamPlayer
var _levels := {} # nimi → nykyinen taso 0–1 (pehmennetty)
var _click: AudioStreamWAV
var _quindar: AudioStreamWAV
var _voices := {} # nimi → AudioStream
var _voice: AudioStreamPlayer
var _queue: Array = [] # [nimi, jonoon (ms)]
var _state_at := -1000
var _target := {}
var _last_tau := -INF
## Vian hälytys (#42) silmukkana vian ajan ja kertaäänet.
var _alarm: AudioStreamPlayer
var _buzz: AudioStreamWAV
var _fixed: AudioStreamWAV
var _boom: AudioStreamWAV


func _ready() -> void:
	var make := {"rumble": SoundSynth.rumble, "burn": SoundSynth.burn, "plasma": SoundSynth.plasma,
		"hum": SoundSynth.hum}
	for name: String in LOOPS:
		var p := AudioStreamPlayer.new()
		p.stream = SoundSynth.to_wav(make[name].call(), true)
		p.volume_db = -80.0
		add_child(p)
		_loops[name] = p
		_levels[name] = 0.0
		_target[name] = 0.0
	_click = SoundSynth.to_wav(SoundSynth.click(), false)
	for name: String in VOICES:
		_voices[name] = load(VOICE_DIR + name + ".ogg")
	_voice = AudioStreamPlayer.new()
	_voice.volume_db = -2.0
	_voice.finished.connect(_next_voice)
	add_child(_voice)
	_quindar = SoundSynth.to_wav(SoundSynth.quindar(), false)
	Game.orbit_reached.connect(func(_b: String) -> void: announce("orbit"))
	Game.departure_burn.connect(func(_f: Dictionary) -> void: announce("depart"))
	Game.soi_entered.connect(func(_b: String) -> void: announce("soi"))
	Game.arrived.connect(func(_b: String) -> void: announce("arrive"))
	Game.capture_done.connect(func(_b: String, ok: bool, _a: bool) -> void: announce("capture" if ok else "flyby"))
	Game.survey_finished.connect(func(_b: String, _f: bool) -> void: announce("survey"))
	_alarm = AudioStreamPlayer.new()
	_alarm.stream = SoundSynth.to_wav(SoundSynth.alarm(), true)
	_alarm.volume_db = -12.0
	add_child(_alarm)
	_buzz = SoundSynth.to_wav(SoundSynth.buzz(), false)
	_fixed = SoundSynth.to_wav(SoundSynth.fixed(), false)
	_boom = SoundSynth.to_wav(SoundSynth.explosion(), false)
	Game.fault_mistake.connect(func(_k: String) -> void: _play(_buzz, -6.0))
	Game.fault_fixed.connect(func(_k: String) -> void: _play(_fixed, -6.0))
	Game.ship_destroyed.connect(func(_k: String) -> void: _play(_boom, 0.0))
	get_tree().node_added.connect(_on_node_added)
	_hook_buttons.call_deferred(get_tree().root)


## Silmukoiden tavoitetasot (0–1) ohjaamon tilasta: laukaisussa jyrinä tärinän ja työnnön mukaan, poltoissa
## moottori, ilmajarrutuksessa plasma ja vaimea taustahumina vasta laukaisun jälkeen (ei alustalla eikä nousussa).
static func levels(s: Dictionary, pad: bool) -> Dictionary:
	var shake := clampf(float(s.get("shake", 0.0)), 0.0, 1.0)
	var thrust := clampf(float(s.get("thrust", 0.0)), 0.0, 1.0)
	var aero := clampf(float(s.get("aero", 0.0)), 0.0, 1.0)
	var launching := pad and float(s.get("tau", -INF)) >= -3.0
	return {"rumble": clampf(shake * 0.8 + thrust * 0.5, 0.0, 1.0) if launching else shake * 0.4,
		"burn": thrust * (0.55 if launching else 1.0), "plasma": aero, "hum": 0.0 if pad else 0.22}


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
		_launch_voice(s)
		# Hälytys soi vian ajan (ei valikossa).
		var alarm := Game.state.get("fault") != null and not quiet
		if alarm != _alarm.playing:
			if alarm:
				_alarm.play()
			else:
				_alarm.stop()
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


## Laukaisun repliikki, jonka hetki ohitettiin välillä (prev, tau]. Vanhentunut (yli sekunti sitten, esim. aikaa
## kiihdytettäessä) jää pois. Palauttaa repliikin nimen tai "".
static func launch_line(prev: float, tau: float) -> String:
	for l: Array in LAUNCH_LINES:
		var at: float = l[0]
		if at > prev and at <= tau and tau - at < 1.0:
			return l[1]
	return ""


func _launch_voice(s: Dictionary) -> void:
	var tau := float(s.get("tau", -INF))
	if not Game.state.pad or not is_finite(tau):
		_last_tau = -INF
		return
	var line := launch_line(_last_tau, tau) if is_finite(_last_tau) else ""
	_last_tau = tau
	if line != "" and not quiet:
		# Lähtölaskennan luku korvaa jonossa odottavan, jotta laskenta pysyy tahdissa.
		_queue.clear()
		_voice.stop()
		speak(line)


## Lennon vaiheen ilmoitus: kuulutus tai pelkkä piippaus. Kuulutukset menevät puhejonoon (esim. saapuminen ja jarrutus
## kiertoradalle samalla hetkellä soivat peräkkäin). Palauttaa, soiko tai jonottaako jotain.
func announce(name: String) -> bool:
	if quiet:
		return false
	if name in CALLOUTS:
		speak(name)
	else:
		_play(_quindar, -8.0)
	return true


## Lennonjohdon repliikki puhejonoon.
func speak(name: String) -> void:
	_queue.append([name, Time.get_ticks_msec()])
	if not _voice.playing:
		_next_voice()


func _next_voice() -> void:
	var now := Time.get_ticks_msec()
	while not _queue.is_empty():
		var item: Array = _queue.pop_front()
		if now - int(item[1]) <= QUEUE_MAX_MS and not quiet:
			_voice.stream = _voices[item[0]]
			_voice.play()
			return


## Jonossa odottavat repliikit (testit).
func queued() -> int:
	return _queue.size()


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
