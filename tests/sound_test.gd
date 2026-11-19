extends TestCase
## Äänien testi ilman ikkunaa: synteesi (pituudet, huiput, saumattomat silmukat), silmukoiden tasot pelin tilasta
## ja äänisolmu pääscenessä.
##   godot --headless -- --soundtest


func _ready() -> void:
	var R := SoundSynth.RATE
	var loops := {"rumble": SoundSynth.rumble(), "burn": SoundSynth.burn(), "plasma": SoundSynth.plasma(), "hum": SoundSynth.hum()}
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
	var c := SoundSynth.chime([523.25, 659.25])
	check("kellosointi häipyy", c.size() > R and absf(c[c.size() - 1]) < 0.05)
	var w := SoundSynth.to_wav(SoundSynth.click(), false)
	check("napsautus WAV:ksi", w.data.size() == SoundSynth.click().size() * 2 and w.loop_mode == AudioStreamWAV.LOOP_DISABLED)
	var lw := SoundSynth.to_wav(loops.hum, true)
	check("silmukka WAV:ssa", lw.loop_mode == AudioStreamWAV.LOOP_FORWARD and lw.loop_end == loops.hum.size())
	var launch := GameSound.levels({"shake": 1.0, "thrust": 1.0, "tau": 5.0}, true)
	check("laukaisussa jyrinä", launch.rumble == 1.0 and launch.burn > 0.3)
	var burn := GameSound.levels({"shake": 0.7, "thrust": 1.0, "aero": 0.0}, false)
	check("poltossa moottori", burn.burn == 1.0 and burn.rumble < 0.5 and burn.plasma == 0.0)
	check("ilmajarrutuksessa plasma", GameSound.levels({"aero": 0.9}, false).plasma == 0.9)
	check("humina aina", GameSound.levels({}, false).hum > 0.0)
	var sound: GameSound = get_parent().sound
	check("äänisolmu pääscenessä", sound != null and not sound.quiet)
	finish()
