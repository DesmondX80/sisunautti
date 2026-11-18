# Sisunautti – ohjeet Claudelle

Avaruuslentopeli: Maan pinnalta kiertoradalle ja planeetoille oikeilla taivaanmekaniikan
kaavoilla. Peli siirtyy Godot 4.7:ään (issuet #7–#12). Godot-projekti on repon juuressa;
vanha selainversio (JS + three.js) on hakemistossa `web/`, kunnes Godot-versio korvaa sen (#12).

## Kieli

- Vastaa käyttäjälle suomeksi.
- Koodi ja tunnisteet (muuttujat, funktiot, tiedostot, signaalit) englanniksi.
- Kommentit, käyttöliittymän tekstit, README, commit-viestit ja julkaisutiedot suomeksi.
- Lukujen muotoilu käyttöliittymässä: pilkku desimaalierottimena, välilyönti tuhaterottimena.

## Koodi

- GDScript staattisin tyypein (`var x: float`, `func f(a: int) -> String`).
- Ratamekaniikka 64-bittisillä `float`-luvuilla. `Vector3` on 32-bittinen: sitä **ei** käytetä
  kilometrikoordinaatteihin, vaan omia kolmen `float`-luvun rakenteita tai `PackedFloat64Array`a.
  Piirrettäessä sijainnit muutetaan kameran suhteen (suunta ja etäisyys).
- Aika millisekunteina (`int`) kuten selainversiossa, jotta tallennukset ovat yhteensopivia.
- Tallennusavaimia `avaruuslento`, `avaruuslento.view` ja `avaruuslento.panel` ei nimetä uudelleen
  ilman siirtoa: vanhat selaintallennukset tuodaan niistä.
- Renderöijä: työpöydällä Forward+ (näyttävä grafiikka), selaimessa GL Compatibility.
  Laatutasot (Matala, Keski, Korkea, Ultra) ovat `Settings`-autoloadissa.

## Rakenne

- `scripts/` – logiikka: autoloadit `settings.gd` ja `game.gd` (pelin tila, kello, tapahtumasignaalit, tallennus
  `user://save.json`), muotoilu `format.gd` (`Fmt`), pääscenen `main.gd`; `scripts/orbit/` ratamekaniikka
  (`planets.gd`, `flight.gd`, ikkunahaku ruutu kerrallaan `window_search.gd`)
- `scenes/` – scenet, pääscene `scenes/main.tscn`
- `ui/` – käyttöliittymän scenet ja teema
- `assets/` – tekstuurit, mallit ja muut resurssit
- `tests/` – ikkunattomat testit `<nimi>_test.gd` (pohja `test_case.gd`)
- `tools/` – apuskriptit, `run_tests.sh`
- `web/` – vanha selainversio (vitest-testit: `cd web && npm test`); `web/.gdignore` pitää sen Godotin ulkopuolella

## Testit

- Jokaiselle logiikkaskriptille testi. Testi `tests/<nimi>_test.gd` (nimessä ei alaviivoja) perii `TestCase`-luokan ja
  ajetaan lipulla `--<nimi>test`: `godot --headless -- --<nimi>test`.
- Kaikki testit: `tools/run_tests.sh` (tai `tools/run_tests.sh settingstest` yksittäin).
- Pelin tila (`Game.state`) on samassa JSON-muodossa kuin selainversion tallennus (avain `avaruuslento`, camelCase-avaimet).
  Esimerkki selainversiosta: `tests/data/web_save.json` (`tools/make_web_save.mjs`). Testit asettavat kellon
  käsin (`Game.fake_real_ms`) ja käyttävät tallennusta `user://test_save.json`.
- Ratamekaniikan muutokset tehdään samoin kuin selainversiossa, kunnes `web/` poistuu: vertailuarvot
  `tests/data/orbit_reference.json` luodaan JS-puolelta (`node tools/make_orbit_reference.mjs`, vaatii `cd web && npm ci`),
  ja `orbitcomparetest` vaatii samat tulokset (radat 1e-9, haut 1e-6).
- Uudessa työkopiossa aja ensin `godot --headless --import`.
- CI (`.github/workflows/ci.yml`) ajaa Godot-testit (Godot 4.7.2 välimuistista) ja selainversion testit.

## Työtapa

1. Issue GitHubista → assign itselle.
2. Toteutus ja testit, README ajan tasalle.
3. Commit (`Closes #N`) → push `main`-haaraan → tarkista CI- ja Pages-ajot.
4. Suomenkielinen kommentti issueen: tehdyt asiat (rastit), varaumat ja testaamatta jääneet.
5. Versionnosto (`project.godot`, `export_presets.cfg`) → GitHub-julkaisu `vX.Y.Z`
   suomenkielisin julkaisutiedoin (`gh release create`).
