class_name BodyTextures
extends RefCounted
## Planeettojen ja kuiden pintakartat (assets/textures/, lähteet README:ssä). Kuvat ovat WebP-tiedostoja, jotka
## viedään sellaisinaan (Godotin "keep"-tuonti) ja puretaan vasta, kun kohde näkyy: peruskartta (enintään 2048 px)
## kun kiekko on muutaman pikselin kokoinen, ja tarkka 4k- tai 8k-kartta lähellä. Purku tehdään työpöydällä
## taustasäikeessä; selaimessa (ei säikeitä) heti. Titanin pinta on utukerroksen peitossa, joten se piirretään.
## Maan 16k-päiväkartta (Ultra, työpöytä) on JPEG, joka tuodaan näytönohjaimen pakattuna tekstuurina (S3TC, 89 Mt
## mipmapeineen; pakkaamattomana se veisi 700 Mt) ja ladataan ResourceLoaderilla. Harmaasävykartat (pilvet, meret,
## yövalot) puretaan yksikanavaisiksi.

const DIR := "res://assets/textures/"
## Tarkimman saatavilla olevan kartan leveys.
const HIRES := {"Merkurius": 8192, "Venus": 4096, "Maa": 16384, "Mars": 8192, "Jupiter": 4096, "Saturnus": 4096, "Kuu": 8192,
	"Phobos": 4096, "Io": 8192, "Europa": 8192, "Ganymedes": 8192, "Enceladus": 8192, "Triton": 4096}
## Maan päiväkartta on pilvetön (pilvet erillisenä kerroksena).
const FILE := {"Maa": "maa-paiva"}

var _cache := {} # polku → ImageTexture
var _pending := {} # polku → tehtävän tunniste
var _results := {} # polku → Image (säikeestä)
var _mutex := Mutex.new()
var threaded := not OS.has_feature("web")


static func file_for(name: String, width: int) -> String:
	var base: String = FILE.get(name, name.to_lower())
	if width >= 16384:
		return DIR + base + "-16k.jpg"
	return DIR + base + ("" if width <= 2048 else "-%dk" % (width / 1024)) + ".webp"


## Tuotu (pakattu) tekstuuri eikä sellaisenaan purettava WebP.
static func imported(path: String) -> bool:
	return path.ends_with(".jpg")


static func exists(path: String) -> bool:
	return ResourceLoader.exists(path) if imported(path) else FileAccess.file_exists(path)


## Leveimmän käytettävissä olevan kartan leveys laatutason ylärajalla.
static func best_width(name: String, max_width: int) -> int:
	var w: int = mini(int(HIRES.get(name, 2048)), max_width)
	while w > 2048 and not exists(file_for(name, w)):
		w /= 2
	return w


## Tekstuuri polusta: valmis, tai null (lataus aloitetaan ja valmistuu myöhemmin, poll()).
func get_texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	if not exists(path):
		return null
	if imported(path):
		return _get_imported(path)
	if not threaded:
		var img := _decode(path)
		_cache[path] = ImageTexture.create_from_image(img) if img != null else null
		return _cache[path]
	if not _pending.has(path):
		_pending[path] = WorkerThreadPool.add_task(_load_task.bind(path), false, "pintakartta")
	return null


func _get_imported(path: String) -> Texture2D:
	if not threaded:
		_cache[path] = load(path)
		return _cache[path]
	if not _pending.has(path):
		ResourceLoader.load_threaded_request(path, "Texture2D")
		_pending[path] = -1
	return null


## Siirtää valmiit säikeessä puretut kuvat tekstuureiksi (pääsäikeessä). Palauttaa true, jos jokin valmistui.
func poll() -> bool:
	var done := false
	_mutex.lock()
	var ready := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for path: String in ready:
		var img: Image = ready[path]
		_cache[path] = ImageTexture.create_from_image(img) if img != null else null
		if _pending.has(path):
			WorkerThreadPool.wait_for_task_completion(_pending[path])
			_pending.erase(path)
		done = true
	for path: String in _pending.keys():
		if int(_pending[path]) != -1:
			continue
		var st := ResourceLoader.load_threaded_get_status(path)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			_cache[path] = ResourceLoader.load_threaded_get(path)
			_pending.erase(path)
			done = true
		elif st == ResourceLoader.THREAD_LOAD_FAILED or st == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_cache[path] = null
			_pending.erase(path)
	return done


## Odottaa kesken olevat purut (ohjaamon poisto ja pelin lopetus).
func wait_all() -> void:
	for path: String in _pending:
		if int(_pending[path]) == -1:
			ResourceLoader.load_threaded_get(path)
		else:
			WorkerThreadPool.wait_for_task_completion(_pending[path])
	_pending.clear()


## Vapauttaa välimuistista kuvat, joita ei enää tarvita (tarkat kartat kaukana).
func release(path: String) -> void:
	_cache.erase(path)


func _load_task(path: String) -> void:
	var img := _decode(path)
	_mutex.lock()
	_results[path] = img
	_mutex.unlock()


static func _decode(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_webp_from_buffer(bytes) != OK:
		return null
	if path.contains("pilvet") or path.contains("meri") or path.contains("maa-yo"):
		img.convert(Image.FORMAT_L8)
	img.generate_mipmaps()
	return img


## Titanin oranssi utupinta (piirretty) ja muut varapinnat yksivärisinä.
static func drawn(name: String, color: Color) -> ImageTexture:
	var w := 256
	var h := 128
	var img := Image.create(w, h, true, Image.FORMAT_RGB8)
	var noise := FastNoiseLite.new()
	noise.seed = name.hash()
	noise.frequency = 0.02
	for y in h:
		var lat := float(y) / h
		for x in w:
			var n := noise.get_noise_2d(x * 2.0, y * 6.0) * 0.5 + 0.5
			var band := 0.92 + 0.08 * sin(lat * 18.0 + n * 3.0)
			img.set_pixel(x, y, color * band * (0.9 + n * 0.15))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
