class_name SoundSynth
## Pelin äänet syntetisoituna käynnistyksessä (ei äänitiedostoja): laukaisun jyrinä, moottorin poltto, ilmajarrutuksen
## plasma ja ohjaamon humina silmukoina sekä käyttöliittymän napsautus, ilmoitusten kellosoinnut ja lähtölaskennan
## piippaus. Näytteet 22 050 Hz, 16-bittinen mono. Silmukat ristihäivytetään saumattomiksi.

const RATE := 22050


## Valkoinen kohina −1…1 toistettavasti (siemen).
static func _noise(n: int, seed: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		out[i] = rng.randf() * 2.0 - 1.0
	return out


## Yksinapainen alipäästö (rajataajuus Hz).
static func _lowpass(x: PackedFloat32Array, hz: float) -> PackedFloat32Array:
	var a := 1.0 - exp(-TAU * hz / RATE)
	var y := 0.0
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		y += a * (x[i] - y)
		out[i] = y
	return out


## Ylipäästö: signaali miinus alipäästetty.
static func _highpass(x: PackedFloat32Array, hz: float) -> PackedFloat32Array:
	var lp := _lowpass(x, hz)
	var out := PackedFloat32Array()
	out.resize(x.size())
	for i in x.size():
		out[i] = x[i] - lp[i]
	return out


static func _normalize(x: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 1e-9
	for v in x:
		m = maxf(m, absf(v))
	var k := peak / m
	for i in x.size():
		x[i] *= k
	return x


## Saumaton silmukka: loppu ristihäivytetään alkuun (pituus lyhenee fade_s sekuntia).
static func seamless(x: PackedFloat32Array, fade_s: float) -> PackedFloat32Array:
	var f := int(fade_s * RATE)
	var n := x.size() - f
	var out := x.slice(0, n)
	for i in f:
		var t := float(i) / f
		out[i] = x[i] * t + x[n + i] * (1.0 - t)
	return out


## Näytteet AudioStreamWAV:ksi (16-bittinen PCM), silmukkana tai kertasoittona.
static func to_wav(x: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(x.size() * 2)
	for i in x.size():
		bytes.encode_s16(i * 2, int(clampf(x[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = x.size()
	return w


## Hidas satunnainen vaihtelu (0–1) taajuudella hz.
static func _wobble(n: int, hz: float, seed: int) -> PackedFloat32Array:
	var w := _normalize(_lowpass(_lowpass(_noise(n, seed), hz), hz), 1.0)
	for i in n:
		w[i] = 0.5 + 0.5 * w[i]
	return w


## Laukaisun jyrinä: ruskea kohina, matala ja täyteläinen, hitaasti aaltoileva.
static func rumble() -> PackedFloat32Array:
	var n := int(3.5 * RATE)
	var white := _noise(n, 11)
	var brown := PackedFloat32Array()
	brown.resize(n)
	var b := 0.0
	for i in n:
		b = b * 0.996 + white[i] * 0.05
		brown[i] = b
	var x := _lowpass(_highpass(brown, 18.0), 220.0)
	var mod := _wobble(n, 2.0, 12)
	var crack := _lowpass(_noise(n, 13), 900.0)
	for i in n:
		x[i] = x[i] * (0.65 + 0.35 * mod[i]) + crack[i] * 0.06 * mod[i]
	return seamless(_normalize(x, 0.95), 0.4)


## Moottorin poltto: kohinan pauhu, matala perusvärähtely ja liekin räiske.
static func burn() -> PackedFloat32Array:
	var n := int(3.0 * RATE)
	var roar := _lowpass(_highpass(_noise(n, 21), 60.0), 650.0)
	var hiss := _lowpass(_highpass(_noise(n, 22), 1500.0), 5000.0)
	var flick := _wobble(n, 9.0, 23)
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		var t := float(i) / RATE
		x[i] = roar[i] * (0.7 + 0.3 * flick[i]) + hiss[i] * 0.12 + sin(TAU * 46.0 * t) * 0.18 * (0.8 + 0.2 * flick[i])
	return seamless(_normalize(x, 0.9), 0.3)


## Ilmajarrutuksen plasma: suhiseva, nopeasti lepattava kohina ja rätinä.
static func plasma() -> PackedFloat32Array:
	var n := int(3.0 * RATE)
	var band := _lowpass(_highpass(_noise(n, 31), 700.0), 4200.0)
	var low := _lowpass(_highpass(_noise(n, 32), 80.0), 400.0)
	var flutter := _wobble(n, 14.0, 33)
	var rng := RandomNumberGenerator.new()
	rng.seed = 34
	var x := PackedFloat32Array()
	x.resize(n)
	var pop := 0.0
	for i in n:
		if rng.randf() < 0.0012:
			pop = rng.randf_range(0.4, 1.0)
		pop *= 0.985
		x[i] = band[i] * (0.4 + 0.6 * flutter[i]) + low[i] * 0.5 + (rng.randf() * 2.0 - 1.0) * pop * 0.5
	return seamless(_normalize(x, 0.85), 0.3)


## Ohjaamon taustahumina: sähköverkon kaltainen sävy yläsävelineen ja tuulettimen kohina.
static func hum() -> PackedFloat32Array:
	var n := int(4.0 * RATE)
	var fan := _lowpass(_highpass(_noise(n, 41), 120.0), 900.0)
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		var t := float(i) / RATE
		var am := 0.85 + 0.15 * sin(TAU * 0.25 * t)
		x[i] = (sin(TAU * 55.0 * t) * 0.5 + sin(TAU * 110.0 * t) * 0.22 + sin(TAU * 165.0 * t) * 0.1 + sin(TAU * 440.0 * t) * 0.015) * am \
			+ fan[i] * 0.35
	return seamless(_normalize(x, 0.8), 0.25)


## Käyttöliittymän napsautus: lyhyt, pehmeä naksahdus.
static func click() -> PackedFloat32Array:
	var n := int(0.045 * RATE)
	var noise := _noise(n, 51)
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		var t := float(i) / RATE
		x[i] = sin(TAU * 1650.0 * t) * exp(-t / 0.006) * 0.6 + noise[i] * exp(-t / 0.0015) * 0.35
	return _normalize(x, 0.7)


## Kellosointi: sävelet (Hz) peräkkäin 0,13 s välein, kellomaiset yläsävelet ja pitkä häivytys.
static func chime(notes: Array) -> PackedFloat32Array:
	var step := 0.13
	var n := int((step * notes.size() + 1.3) * RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	for k in notes.size():
		var f := float(notes[k])
		var start := int(k * step * RATE)
		for i in range(start, n):
			var t := float(i - start) / RATE
			var env := minf(1.0, t / 0.004) * exp(-t / 0.45)
			x[i] += (sin(TAU * f * t) + 0.35 * sin(TAU * f * 2.0 * t) * exp(-t / 0.2) + 0.15 * sin(TAU * f * 2.76 * t) * exp(-t / 0.12)) * env
	return _normalize(x, 0.6)


## Lähtölaskennan piippaus (lyhyt siniääni).
static func beep(hz: float, length: float) -> PackedFloat32Array:
	var n := int(length * RATE)
	var x := PackedFloat32Array()
	x.resize(n)
	for i in n:
		var t := float(i) / RATE
		x[i] = sin(TAU * hz * t) * minf(1.0, t / 0.005) * minf(1.0, (length - t) / 0.02) * 0.5
	return x
