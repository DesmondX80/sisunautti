#!/usr/bin/env bash
# Ajaa ikkunattomat testit peräkkäin ja tulostaa yhteenvedon.
# Käyttö: tools/run_tests.sh [GODOT] [TESTIN_NIMI...]
#   GODOT        Godot-ohjelma (oletus: $GODOT, sitten godot-4.7.2, sitten godot)
#   TESTIN_NIMI  ajaa vain nimetyt testit, esim. settingstest
# Testi on tiedosto tests/<nimi>_test.gd, ja se ajetaan lipulla --<nimi>test.
# Paluukoodi: 0 kaikki läpi, 1 jokin testi epäonnistui.
set -u
cd "$(dirname "$0")/.."

godot="${GODOT:-}"
if [[ $# -gt 0 && ( -x "$1" || "$1" == */* ) ]]; then godot="$1"; shift; fi
if [[ -z "$godot" ]]; then godot="$(command -v godot-4.7.2 || command -v godot)"; fi
[[ -n "$godot" ]] || { echo "Godotia ei löytynyt" >&2; exit 2; }
timeout_s="${TEST_TIMEOUT:-600}"
window_tests="uishotstest cockpitshotstest"

if [[ $# -gt 0 ]]; then
	names=("$@")
else
	names=()
	for f in tests/*_test.gd; do
		n="$(basename "$f" _test.gd)"
		# Ikkunaa vaativat testit (kuvakaappaukset) ajetaan erikseen.
		[[ " $window_tests " == *" ${n}test "* ]] && continue
		names+=("${n}test")
	done
fi

fails=0
summary=()
for name in "${names[@]}"; do
	start=$(date +%s)
	out="$(timeout "$timeout_s" "$godot" --headless -- "--$name" 2>&1)"
	code=$?
	secs=$(( $(date +%s) - start ))
	# Lopetuksen yhteydessä Godot ilmoittaa vapauttamatta jääneistä resursseista (teema, kirjasimet); ne eivät ole virheitä.
	errs="$(grep -E '^VIRHE|SCRIPT ERROR|Parse Error|ERROR:' <<<"$out" | grep -vE 'resources still in use at exit|were leaked at exit')"
	result="$(grep -E '^TULOS' <<<"$out" | tail -1)"
	if [[ $code -ne 0 || -n "$errs" || -z "$result" ]]; then
		fails=$((fails + 1))
		status="VIRHE"
		[[ $code -eq 124 ]] && status="AIKAKATKAISU"
		echo "----- $name ($status, koodi $code)"
		echo "$out" | tail -40
	fi
	summary+=("$(printf '%-24s %-13s %4ss  %s' "$name" "${status:-OK}" "$secs" "${result#TULOS }")")
	status=""
done

echo
printf '%s\n' "${summary[@]}"
echo
if [[ $fails -eq 0 ]]; then echo "Kaikki ${#names[@]} testiä läpi."; else echo "$fails/${#names[@]} testiä epäonnistui."; exit 1; fi
