extends TestCase
## Äänien testi ilman ikkunaa: synteesi (pituudet, huiput, saumattomat silmukat), silmukoiden tasot pelin tilasta
## ja äänisolmu pääscenessä.
##   godot --headless -- --soundtest


func _ready() -> void:
	var R := SoundSynth.RATE
	var loops := {"rumble": SoundSynth.rumble(), "burn": SoundSynth.burn(), "plasma": SoundSynth.plasma(),
		"hum": SoundSynth.hum()}
	for name: String in loops:
		var x: PackedFloat32Array = loops[name]
		var peak := 0.0
		for v in x:
			peak = maxf(peak, absf(v))
		check("silmukka %s: pituus ja huippu" % name, x.size() > 2 * R and peak > 0.5 and peak <= 1.0)
		# Sauma: hyppy lopusta alkuun on samaa luokkaa kuin vierekkäisten näytteiden tavallinen ero.
		var mean_step := 0.0
		for i in range(1, x.size()):
			mean_step += absf(x[i] - x[i - 1])
		mean_step /= x.size() - 1
		check("silmukka %s saumaton" % name, absf(x[x.size() - 1] - x[0]) < 5.0 * mean_step + 0.01)
	var q := SoundSynth.quindar()
	check("Quindar-piippaus kaksiosainen ja hiljenee", q.size() > int(0.55 * R) and absf(q[q.size() - 1]) < 0.05 \
		and absf(q[int(0.29 * R)]) < 0.001)
	var w := SoundSynth.to_wav(SoundSynth.click(), false)
	check("napsautus WAV:ksi", w.data.size() == SoundSynth.click().size() * 2 and w.loop_mode == AudioStreamWAV.LOOP_DISABLED)
	var lw := SoundSynth.to_wav(loops.burn, true)
	check("silmukka WAV:ssa", lw.loop_mode == AudioStreamWAV.LOOP_FORWARD and lw.loop_end == loops.burn.size())
	# Humina tasainen: 0,25 s:n jaksojen tehot vaihtelevat alle 1,3 dB (kohinan luonnollinen vaihtelu).
	var hum: PackedFloat32Array = loops.hum
	var lo := INF
	var hi := 0.0
	var win := R / 4
	for k in hum.size() / win:
		var e := 0.0
		for i in range(k * win, (k + 1) * win):
			e += hum[i] * hum[i]
		lo = minf(lo, e)
		hi = maxf(hi, e)
	check("taustahumina tasainen", hi / lo < 1.35)
	var launch := GameSound.levels({"shake": 1.0, "thrust": 1.0, "tau": 5.0}, true)
	check("laukaisussa jyrinä", launch.rumble == 1.0 and launch.burn > 0.3)
	var burn := GameSound.levels({"shake": 0.7, "thrust": 1.0, "aero": 0.0}, false)
	check("poltossa moottori", burn.burn == 1.0 and burn.rumble < 0.5 and burn.plasma == 0.0)
	check("ilmajarrutuksessa plasma", GameSound.levels({"aero": 0.9}, false).plasma == 0.9)
	check("humina laukaisun jälkeen", GameSound.levels({}, false).hum > 0.0)
	check("ei huminaa alustalla eikä nousussa", GameSound.levels({"tau": 100.0}, true).hum == 0.0)
	# Laukaisun repliikit: lähtölaskenta, liftoff, torni ja vaiheen erotus 2:30; aikaa kiihdytettäessä ohitetut pois.
	check("lähtölaskenta kymmenestä", GameSound.launch_line(-10.5, -9.95) == "count10")
	check("viimeinen luku", GameSound.launch_line(-1.05, -0.98) == "count1")
	check("liftoff", GameSound.launch_line(-0.05, 0.02) == "liftoff")
	check("tower cleared", GameSound.launch_line(8.95, 9.02) == "tower")
	check("kantoraketin erotus 2:30", GameSound.launch_line(149.95, 150.03) == "staging")
	check("ei repliikkiä välissä", GameSound.launch_line(20.0, 20.07) == "")
	check("ohitettu repliikki ei soi", GameSound.launch_line(100.0, 160.0) == "")
	# Radio: viisi kanavaa, joiden tiedostot löytyvät; viritys, seuraava kappale ja sammutus.
	var files := true
	for ch: Array in Radio.CHANNELS:
		for t: Array in ch[1]:
			files = files and ResourceLoader.exists(Radio.DIR + String(t[0]))
	check("radiossa viisi kanavaa ja tiedostot", Radio.CHANNELS.size() == 5 and files)
	var radio: Radio = get_parent().radio
	var saved_channel: int = Settings.radio_channel
	radio.tune(2)
	check("radio viritetty", radio.channel == 2 and radio.track == 0 and String(radio.now_playing()[1]).contains("NASA"))
	radio.next_track()
	check("seuraava kappale", radio.track == 1)
	radio.next_track()
	check("kanava alkaa alusta", radio.track == 0)
	radio.tune(-1)
	check("radio pois", radio.channel == -1 and radio.now_playing().is_empty() and Settings.radio_channel == -1)
	Settings.set_radio_channel(saved_channel)
	check("radiokohina", SoundSynth.radio_static().size() > SoundSynth.RATE / 3)
	var sound: GameSound = get_parent().sound
	check("äänisolmu pääscenessä", sound != null and not sound.quiet)
	var voices := true
	for name: String in GameSound.VOICES:
		var v: AudioStream = load(GameSound.VOICE_DIR + name + ".ogg")
		var most := 1.0 if name.begins_with("count") else 4.5
		voices = voices and v != null and v.get_length() > 0.3 and v.get_length() < most
	check("lennonjohdon repliikit (luvut alle sekunnin)", voices)
	check("kuulutus soi", sound.announce("arrive"))
	check("toinen kuulutus jonoon, ei päälle", sound.announce("capture") and sound.queued() == 1)
	finish()
