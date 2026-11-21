# Sisunautti – ohjeet Claudelle

Avaruuslentopeli: Maan pinnalta kiertoradalle ja planeetoille oikeilla taivaanmekaniikan
kaavoilla, Godot 4.7. Julkaistaan työpöydälle (Windows, Linux, macOS). Selainversion (GitHub Pages, Compatibility) vienti on
toistaiseksi pois käytöstä, koska peli ei nyt toimi selaimessa (selain ja mobiili myöhemmin, #56).
Vanha JS-selainversio poistettiin versiossa 1.0.0; sen tallennukset tuodaan selaimessa localStoragesta.

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
  `user://save.json`), muotoilu `format.gd` (`Fmt`), aluksen viat `faults.gd`, pääscenen `main.gd`; `scripts/orbit/` ratamekaniikka
  (`planets.gd`, `flight.gd`, ikkunahaku ruutu kerrallaan `window_search.gd`)
- `scenes/` – scenet, pääscene `scenes/main.tscn`
- `scripts/ui/` – käyttöliittymä koodissa (`voyage_ui.gd`, `flight_map.gd`, `ui_kit.gd`); `ui/theme.tres` luodaan
  `tools/make_theme.gd`:llä aina, kun `UiKit.make_theme()` muuttuu
- `scripts/cockpit/` – 3D-ohjaamo (`cockpit_view.gd`, `space.gd`, `cabin.gd`, `screens.gd`, `cockpit_state.gd`,
  `body_textures.gd`); varjostimet `shaders/`. Avaruuden varjostimet kirjoittavat syvyyden ohjaamon taakse
  (`shaders/space_depth.gdshaderinc`), ja etäisyydet puristetaan (`Space.compress`), jotta kaukotaso on 120 km.
- `assets/textures/` – pintakartat WebP:nä Godotin keep-tuonnilla (puretaan ajossa, 8k vain työpöydälle)
- `assets/data/planet_info.json` – tietokortit
- `assets/` – tekstuurit, mallit ja muut resurssit
- `tests/` – ikkunattomat testit `<nimi>_test.gd` (pohja `test_case.gd`)
- `tools/` – apuskriptit, `run_tests.sh`
- `tools/web/sw.js` – Pagesiin kopioitava worker, joka poistaa vanhan selainversion service workerin

## Testit

- Jokaiselle logiikkaskriptille testi. Testi `tests/<nimi>_test.gd` (nimessä ei alaviivoja) perii `TestCase`-luokan ja
  ajetaan lipulla `--<nimi>test`: `godot --headless -- --<nimi>test`.
- Ikkunaa vaativat testit (`uishotstest`, `cockpitshotstest`) eivät ole `run_tests.sh`:ssa: kuvakaappaukset otetaan käyttöliittymän
  muutoksista 1600×900- ja 390×844-ikkunassa ja katsotaan ennen valmista.
- Kaikki testit: `tools/run_tests.sh` (tai `tools/run_tests.sh settingstest` yksittäin).
- Pelin tila (`Game.state`) on samassa JSON-muodossa kuin selainversion tallennus (avain `avaruuslento`, camelCase-avaimet).
  Esimerkki selainversiosta: `tests/data/web_save.json` (`tools/make_web_save.mjs`). Testit asettavat kellon
  käsin (`Game.fake_real_ms`) ja käyttävät tallennusta `user://test_save.json`.
- `orbitcomparetest` vertaa ratamekaniikkaa vanhan JS-version tuloksiin (`tests/data/orbit_reference.json`).
  Jos ratamekaniikkaa muutetaan tarkoituksella, vertailuarvot päivitetään (ks. `tools/make_orbit_reference.mjs`).
- Uudessa työkopiossa aja ensin `godot --headless --import`.
- CI (`.github/workflows/ci.yml`) ajaa Godot-testit (Godot 4.7.2 välimuistista). Julkaisu käynnistää `release.yml`:n
  (Windows-, Linux- ja macOS-liitteet). `pages.yml` (selainversio) ajetaan vain käsin, ja se on toistaiseksi pois käytöstä.

## Työtapa

1. Issue GitHubista → assign itselle.
2. Toteutus ja testit, README ajan tasalle.
3. Commit (`Closes #N`) → push `main`-haaraan → tarkista CI-ajo.
4. Suomenkielinen kommentti issueen: tehdyt asiat (rastit), varaumat ja testaamatta jääneet.
5. Versionnosto (`project.godot`, `export_presets.cfg`) → GitHub-julkaisu `vX.Y.Z`
   suomenkielisin julkaisutiedoin (`gh release create`).
