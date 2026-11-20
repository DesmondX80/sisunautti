class_name Radio
extends Node
## Ohjaamon radio (#31): viisi kanavaa, joilla soi vapaasti käytettävää musiikkia ja Apollo-lentojen radioliikennettä.
## Kanavan kappaleet soivat peräkkäin ja alkavat alusta. Kanavaa vaihdettaessa kuuluu lyhyt radiokohina. Valittu
## kanava ja musiikin voimakkuus tallentuvat asetuksiin (Settings.radio_channel, Settings.music_volume).
## Lähteet ja lisenssit: CREDITS ja README.

signal changed

const DIR := "res://assets/music/"
## Kanavat: nimi ja kappaleet [tiedosto, nimi, tekijä ja lisenssi].
const CHANNELS := [
	["Avaruustunnelma", [["ambient1.ogg", "Cosmic Navigation", "synth-thetic, CC0"],
		["ambient2.ogg", "Outer Space Loop", "wipics, CC0"]]],
	["Syntikka", [["synth1.ogg", "Space Synth Wave", "pro-sensory, CC0"],
		["synth2.ogg", "Space City", "mintodog, CC0"]]],
	["Johtokeskus", [["radio1.ogg", "Lennonjohto", "NASA, public domain"],
		["radio2.ogg", "Lennonjohto", "NASA, public domain"]]],
	["Rock", [["rock1.ogg", "Epic Rock Battle Theme", "hydrogene, CC0"],
		["rock2.ogg", "Space Adventure", "mintodog, CC0"]]],
	["Klassinen", [["classic1.ogg", "Johann Strauss II: An der schönen blauen Donau", "European Archive, CC0"],
		["classic2.ogg", "Gustav Holst: Planeetat – Jupiter", "Yhdysvaltain ilmavoimien soittokunta, public domain"]]],
]

var channel := -1 # −1: radio pois
var track := 0
var _player: AudioStreamPlayer
var _static: AudioStreamPlayer


func _ready() -> void:
	add_to_group("radio")
	_player = AudioStreamPlayer.new()
	_player.finished.connect(_next_track)
	add_child(_player)
	_static = AudioStreamPlayer.new()
	_static.stream = SoundSynth.to_wav(SoundSynth.radio_static(), false)
	_static.volume_db = -8.0
	add_child(_static)
	Settings.audio_changed.connect(_apply_volume)
	_apply_volume()
	if Settings.radio_channel >= 0 and Settings.radio_channel < CHANNELS.size():
		tune(Settings.radio_channel, false)


## Valitsee kanavan (−1 sammuttaa). Kohina kuuluu vaihdettaessa.
func tune(i: int, noise: bool = true) -> void:
	if noise and i != channel:
		_static.play()
	channel = clampi(i, -1, CHANNELS.size() - 1)
	track = 0
	_player.stop()
	if channel >= 0:
		_play_track()
	if Settings.radio_channel != channel:
		Settings.set_radio_channel(channel)
	changed.emit()


func next_track() -> void:
	if channel >= 0:
		_static.play()
		_next_track()


func _next_track() -> void:
	if channel < 0:
		return
	track = (track + 1) % (CHANNELS[channel][1] as Array).size()
	_play_track()
	changed.emit()


func _play_track() -> void:
	var t: Array = CHANNELS[channel][1][track]
	var stream: AudioStream = load(DIR + String(t[0]))
	_player.stream = stream
	_player.play()


func _apply_volume() -> void:
	_player.volume_db = linear_to_db(maxf(Settings.music_volume, 0.0001))
	_player.stream_paused = Settings.music_volume <= 0.0 and channel >= 0


## Soiva kappale: [nimi, tekijä ja lisenssi] tai [] kun radio on pois.
func now_playing() -> Array:
	if channel < 0:
		return []
	var t: Array = CHANNELS[channel][1][track]
	return [t[1], t[2]]


func is_playing() -> bool:
	return channel >= 0 and _player.playing
