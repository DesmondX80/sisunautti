class_name TestCase
extends Node
## Ikkunattomien testien pohja: check() kirjaa rivin OK tai VIRHE, finish() tulostaa
## yhteenvedon ja lopettaa pelin paluukoodilla 0 (kaikki läpi) tai 1.

var _passed := 0
var _failed := 0


func check(name: String, ok: bool) -> void:
	if ok:
		_passed += 1
		print("OK    ", name)
	else:
		_failed += 1
		print("VIRHE ", name)


## Suhteellinen vertailu: |a − b| ≤ tol · max(|a|, |b|, 1e-300).
func check_near(name: String, a: float, b: float, tol: float = 1e-9) -> void:
	var ok := absf(a - b) <= tol * maxf(maxf(absf(a), absf(b)), 1e-300)
	check(name if ok else "%s (%s ≠ %s)" % [name, a, b], ok)


func finish() -> void:
	print("TULOS %d OK, %d VIRHE" % [_passed, _failed])
	get_tree().quit(0 if _failed == 0 and _passed > 0 else 1)
