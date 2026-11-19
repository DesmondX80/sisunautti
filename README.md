# Sisunautti

Avaruuslentopeli selaimessa ja työpöydällä (Windows, Linux), tehty Godot 4.7:llä. Lähdetään laukaisualustalta Maan pinnalta kiertoradalle ja sieltä planeetoille ja niiden
kuille. Radat, laukaisuikkunat ja polttoaineen kulutus (Δv) lasketaan oikeilla taivaanmekaniikan kaavoilla, ja
lentoa seurataan 3D-ohjaamosta.

- Peli selaimessa: https://desmondx80.github.io/sisunautti/
- Työpöytäversiot: [julkaisut](https://github.com/DesmondX80/sisunautti/releases) (Sisunautti-windows.zip, Sisunautti-linux.zip)

Peli syntyi OmaAvaruus-sovelluksen ([DesmondX80/omaavaruus](https://github.com/DesmondX80/omaavaruus)) Avaruuslento-osiona
ja eriytettiin omaksi pelikseen. Tallennetut pelit jatkuvat: molemmat sivut ovat samassa alkuperässä
(`desmondx80.github.io`), ja tallennusavaimet (`avaruuslento*`) ovat ennallaan.

Peli tehtiin alun perin JavaScriptillä ja three.js:llä, ja versiossa 1.0.0 se siirrettiin Godotiin. Godot-versio
korvasi selainversion samassa osoitteessa: ensimmäisellä käynnistyksellä selaimessa se tuo vanhan pelin
localStoragesta (avaimet `avaruuslento`, `avaruuslento.view` ja `avaruuslento.panel`), kirjaa tuonnin lokikirjaan
ja poistaa vanhan service workerin ja sen välimuistit.

## Kehitys

Tarvitaan [Godot 4.7.2](https://godotengine.org/download/) (vakioversio, ei .NET).

```bash
cd ~/projektit
git clone git@github.com:DesmondX80/sisunautti.git sisunautti
cd sisunautti
godot --headless --import   # tuo resurssit kerran uudessa työkopiossa
godot -e                    # avaa editorissa (tai Godotin projektilistasta project.godot)
godot                       # käynnistä peli
tools/run_tests.sh          # ikkunattomat testit, esim. tools/run_tests.sh settingstest
```

- Renderöijä: työpöydällä **Forward+**, selaimessa **GL Compatibility** (`rendering/renderer/rendering_method.web`).
- Laatutasot Matala, Keski, Korkea ja Ultra (`Settings`-autoload, `user://settings.cfg`). Työpöydän oletus on Korkea,
  selaimen Keski.
- Testi on tiedosto `tests/<nimi>_test.gd`, ja se ajetaan lipulla `--<nimi>test`, esim. `godot --headless -- --boottest`.
- Pelin tila, kello ja tapahtumat ovat autoloadissa `Game` (`scripts/game.gd`), ja tila tallentuu tiedostoon
  `user://save.json` 5 s välein ja suljettaessa samassa JSON-muodossa kuin selainversion tallennus. Käyttöliittymä ja
  ohjaamo kuuntelevat sen signaaleja (laukaisu, kiertorata, lähtöpoltto, ohilento, vaikutuspiiri, saapuminen, kartoitus).
- Käyttöliittymä (`scripts/ui/`): näkymä (lentokartta, myöhemmin 3D-ohjaamo) täyttää ikkunan, ja ohjaimet ovat oikean
  reunan 420 px:n paneelissa, jonka voi piilottaa. Alle 1000 px:n levyisessä ikkunassa paneeli on näkymän alla.
  Teema on selainversion väreissä (`ui/theme.tres`, luodaan komennolla `godot --headless -s tools/make_theme.gd`).
  Näppäimet: 1–8 aikakiihdytys, + ja − zoomaus, P sivupaneeli, F11 koko näyttö. Kartan zoomaus myös hiiren rullalla ja
  nipistämällä.
- 3D-ohjaamo (`scripts/cockpit/`, varjostimet `shaders/`): etuseinä on ohjaamon kuva (`assets/cockpit/ohjaamo.png`)
  täsmälleen kuvan kuvakulmassa (vaakakulma noin 95°). Koska kamera vain kääntyy paikallaan, tasainen kuva näkyy oikein
  joka suuntaan katsottaessa. Kuva piirretään 2D-kerroksena 3D-näkymän päälle (`shaders/cockpit_overlay.gdshader`):
  jokaiselle pikselille lasketaan katsesuunta ja siitä kohta kuvassa, joten kuvan värit säilyvät ilman sävykartoitusta.
  Kuvan ikkuna-alue on läpinäkyvä (alfakanava, ääriviiva `Cabin.WINDOW`), joten avaruus näkyy sen läpi, ja kuvan
  näyttöjen päälle piirretään pelin näytöt projektiivisella kuvauksella (kulmat kuvasta, `Cabin.MONITORS`). Kuvan
  ympärillä on ohjaamon 360°-panoraama (`assets/cockpit/panoraama-6k.webp` 5824 × 2880 työpöydällä,
  `panoraama.webp` 4096 × 2048 selaimessa), joka lasketaan samasta katsesuunnasta; etukuva häivytetään reunoiltaan
  panoraamaan. Panoraaman horisonttia on laskettu 11°, jotta sen kojelauta jää etukuvan kojelaudan taakse, ja sen omat
  ohjainsauvat on retusoitu pois (LaMa-inpainting), joten alas katsottaessa näkyvät vain lentäjän kädet sauvoissa. Näytöt (tutka, aluskaavio, tähtäin,
  järjestelmät, kohdekamera ja pikkunäyttö) ovat `SubViewport`-tekstuureja kuvan näyttöjen muodossa (leveys 1024),
  jotka piirretään uudelleen enintään 20 kertaa sekunnissa; kohdekamera ja järjestelmänäytön hologrammi näyttävät
  kohteen pinnan pyörivänä pallona (`shaders/globe.gdshader`). Näyttöä napsauttamalla katse kääntyy siihen ja
  kuvakulma kapenee niin, että näyttö täyttää kuvan; uusi napsautus, Esc tai Loitonna palauttaa näkymän. Rullalla
  ja nipistämällä zoomataan vapaasti. Moottorin ja plasman hehku sävyttää ohjaamon kuvaa, ja ikkunan lasissa on
  likaa ja naarmuja, jotka Aurinko sytyttää häikäisyksi. Avaruudessa ovat kirkkaat tähdet HDR-pisteinä ja Linnunrata taustana, Auringon
  HDR-kiekko hehkuineen ja linssiheijastus (ohjaamon rakenteet peittävät sen syvyyspuskurin perusteella), planeettojen
  ja kuiden pintakartat (2k, lähellä 4k tai 8k), ilmakehän sironta varjostimella, Maan erillinen pilvikerros,
  kaupunkien valot ja merien heijastus sekä Saturnuksen läpikuultavat renkaat varjoineen. Kappaleet piirretään
  kameran suhteen: 64-bittiset sijainnit muutetaan suunnaksi ja logaritmisesti puristetuksi etäisyydeksi, ja niiden
  syvyysarvo kirjoitetaan aina ohjaamon taakse. Valaistus: auringonvalo ikkunoista pehmeine varjoineen, lähimmän
  kappaleen heijastama valo sen värisenä, himmeneminen kaukana Auringosta ja pimennys, kun kappale peittää Auringon.
  AgX-tonemapping, hehku ja automaattinen valotus. Laukaisussa päivätaivas, liekki ja pakokaasupilvi (GPU-partikkelit)
  ja tärinä; poltoissa moottorin hehku; ilmajarrutuksessa virtaava plasma, oranssi valo ja kipinät.
- Laatutasot (Tietoa-ikkunassa): Matala, Keski, Korkea ja Ultra muuttavat varjojen tarkkuutta, SSAO:ta (Korkea),
  SSR:ää (Ultra), reunanpehmennystä, partikkelimääriä, pintakarttojen tarkkuutta (Matala 2k, Keski 4k, Korkea ja
  Ultra 8k) ja ilmakehän näytteitä. Oletus valitaan näytönohjaimen mukaan. Selaimessa (Compatibility) enintään
  Keski, ilman SSAO:ta, SSR:ää ja automaattista valotusta, ja 8k-karttoja ei viedä selainversioon.
- Kuvakaappaukset käyttöliittymän tiloista (vaatii ikkunan): `godot -- --uishotstest=/polku/kuviin --size=390x844`.
  Ohjaamosta: `godot -- --cockpitshotstest=/polku/kuviin [--quality=0–3]` (selaimen renderöijällä lisäksi
  `--rendering-method gl_compatibility`); raporttiin kirjataan myös ruutunopeus.
- Ratamekaniikka on hakemistossa `scripts/orbit/` (`planets.gd`, `flight.gd`, `window_search.gd`). Laskut tehdään
  64-bittisillä `float`-luvuilla (`PackedFloat64Array`), ja laukaisuikkunoiden haku jaetaan ruutujen kesken.
  `orbitcomparetest` vertaa tuloksia selainversioon (`tests/data/orbit_reference.json`, luodaan komennolla
  vanhasta JS-versiosta komennolla `node tools/make_orbit_reference.mjs`; ohje skriptin alussa).

### Vienti

Vientipohjat (export templates) asennetaan editorista: *Editor → Manage Export Templates*.

```bash
godot --headless --export-release "Windows Desktop" export/windows/Sisunautti.exe
godot --headless --export-release "Linux" export/linux/Sisunautti.x86_64
godot --headless --export-release "Web" export/web/index.html   # web_nothreads-pohja, ei vaadi COOP/COEP-otsakkeita
```

`export/` ei ole versionhallinnassa.

## Pelin kulku

peli, jossa lähdetään raketilla Maan pinnalta kiertoradalle ja sieltä muille planeetoille. Peli hakee seuraavan kahden vuoden laukaisuikkunat Lambertin ratkaisuilla ja näyttää halvimman ja nopeammat siirtoradat Δv-kustannuksineen. Laukaisun jälkeen lentonäkymässä on lentoaika (T+), kalenteripäivä, nopeus Auringon ja lähimmän planeetan suhteen, etäisyys kohteeseen, valon kulkuaika Maahan sekä kartta, jolle on piirretty raketti, kuljettu reitti ja tuleva rata. Aikaa voi kiihdyttää 1×:stä vuoteen sekunnissa, ja kiihdytys pienenee itsestään ennen vaikutuspiirin rajaa ja saapumista. Pelin kello kulkee oikeassa ajassa myös pelin ollessa kiinni, ja tila tallentuu (selaimessa selaimen tallennustilaan, työpöydällä käyttäjän kansioon).

- - **Laukaisu Maan pinnalta**: uusi peli alkaa laukaisualustalta. Lähtölaskenta (T− 10 s) päättyy sytytykseen, ja kantoraketti nostaa aluksen 200 km:n kiertoradalle 8 min 30 s:ssa: vaihe 1, suurin aerodynaaminen kuorma (Max Q), vaiheen erotus 2 min 30 s kohdalla ja vaihe 2. Näkymässä ovat korkeus, nopeus, kiihtyvyys ja vaihe. Ohjaamo tärisee vaiheen mukaan (kovimmin laukaisussa ja Max Q:ssa, nykäys vaiheen erotuksessa), nokka kääntyy pystystä vaakaan, ja päivällä sininen taivas tummuu ilmakehän ohetessa. Nousua ei integroida voimista: korkeus ja nopeus seuraavat sileitä käyriä, jotka päättyvät täsmälleen ympyräradan tilaan. Nousu ei kuluta aluksen omaa polttoainetta.
- - **Lähtöpoltto kiertoradalta**: kun laukaisuikkuna on auki, lentäjä kytkee lähtöpolton päälle. Alus kääntyy nokka menosuuntaan ja jatkaa kiertorataa, ja moottori syttyy itsestään kohdassa, josta poistumishyperbelin asymptootti osoittaa lähtösuuntaan (enintään yhden kierroksen päässä; siirtorata ratkaistaan uudelleen sille hetkelle). Venyneellä radalla poltto tehdään seuraavassa perikeskuksessa.
- - **Matalat saapumisradat**: perillä jarrutetaan Merkuriuksella, Venuksella ja Marsilla 500 km:n ympyräradalle (Maassa 200 km). Jättiläisplaneetoilla radan perikeskus on 3 000–5 000 km pilvien yläpuolella, mutta rata on venynyt, koska matalalle ympyräradalle jarruttaminen veisi 7–17 km/s. Alus jää radalle siihen kohtaan, johon se saapui.
- - **Ilmajarrutus jättiläisplaneetoilla**: saapuessa voi moottorijarrutuksen sijaan ilmajarruttaa. Alus sukeltaa kaasukehän yläosaan (noin 200 km pilvien yläpuolelle), ja ilmanvastus jarruttaa sen matalalle ympyräradalle (Jupiter 5 000 km, muut 3 000 km). Polttoainetta kuluu vain radan nostoon (0,3–0,7 km/s), ja ohjaamo tärisee plasman hehkuessa ikkunoissa. Lähtö matalalta radalta maksaa täyden hinnan: Jupiterilta noin 17 km/s, Saturnukselta 11, Uranukselta ja Neptunukselta 7. Kemiallinen raketti ei pääse Jupiterin matalalta radalta pois, ja peli varoittaa siitä ennen valintaa. Ionialus ei voi ilmajarruttaa.
- - **Tutkiminen ja lokikirja**: perillä jarrutetaan kiertoradalle (jos polttoaine ei riitä, alus ohittaa planeetan ja jää Auringon kiertoradalle). Planeetan tietokortissa ovat koko, massa, painovoima, päivän ja vuoden pituus, lämpötila, kaasukehä ja kuut. Vuorokauden kartoituksen jälkeen planeetta on tutkittu, sen faktat paljastuvat ja polttoaine täydennetään. Lokikirjassa ovat lennot, tutkitut planeetat (x/8), kokonaislentoaika, kuljettu matka ja huippunopeus.
- - **Kurssikorjaukset**: lennon aikana moottoria voi polttaa eteen, taakse, sisään tai ulos (10 m/s–1 km/s). Ennuste kertoo ennen polttoa, osuuko alus kohteen vaikutuspiiriin vai ohittaako se kohteen, ja uusi rata näkyy kartalla. Automaattinen korjaus laskee reitin takaisin kohteeseen.
- - **Linkous, kuut ja alukset**: reittihaku ehdottaa myös yhden painovoimalinkouksen reittejä (esim. Maa → Venus → Merkurius), kun ne ovat suoraa lentoa halvempia tai nopeampia. Kohteina ovat myös Kuu, Phobos, Io, Europa, Ganymedes, Titan, Enceladus ja Triton, joihin lennetään emoplaneetan kiertoradalta, ja niillä on omat tietokorttinsa. Maan kiertoradalla voi vaihtaa alusta: kemiallinen raketti (14 km/s), ydinlämpöraketti (22 km/s, vetyä vain Maasta ja kaasujättiläisiltä) tai ionialus (45 km/s, mutta lähtö ja jarrutus ovat kuukausien spiraaleja).
- - **3D-ohjaamo**: lentoa seurataan aluksen ikkunasta. Ohjaamo on mallinnettu PBR-materiaalein (kulunut metalli, kumi, kangas, lasi), näytöt hehkuvat ja merkkivalot seuraavat pelin tilaa. Tähdet, Aurinko, planeetat ja kuut ovat oikeissa suunnissa ja oikean kokoisina; planeetoilla on ilmakehän sironta, Maalla pilvikerros, yövalot ja meriheijastus, Saturnuksella renkaat varjoineen. Auringonvalo tulee ikkunoista pehmeine varjoineen, ja pimennyksessä se sammuu sen mukaan, kuinka paljon kappale peittää Auringosta. Ohjaamo on käyttäjän antama kuva, jonka ikkunasta näkyy oikea avaruus ja jonka näytöillä näkyvät pelin tiedot. Kojelaudan viidellä näytöllä ovat tutka, aluskaavio, tähtäin nopeuksineen, järjestelmät ja kohdekameran kuva kohteesta. Katsetta käännetään raahaamalla, ja näyttöä napsauttamalla siihen zoomataan, jotta lukemat näkyvät tarkasti (myös rulla ja nipistys). Tarkemmin kohdassa [Kehitys](#kehitys) ja kuvien lähteet kohdassa [Tekstuurien lähteet](#tekstuurien-lähteet).
- - **Leveä näyttö**: vähintään 1000 pikselin levyisessä ikkunassa ohjaamo tai kartta täyttää ikkunan ja ohjaimet ovat oikean reunan paneelissa, jonka voi piilottaa (P). Kapeammassa ikkunassa paneeli on näkymän alla. Yläpalkin painike vie pelin koko näytön tilaan (F11).

## Rakenne

```
project.godot, export_presets.cfg   # Godot-projekti (Forward+, web: Compatibility)
scripts/, scenes/, ui/, assets/     # Godot: logiikka, scenet, käyttöliittymä, resurssit
scripts/game.gd, scripts/format.gd   # Godot: pelin tila, kello ja tallennus; suomenkielinen muotoilu
scripts/ui/, ui/                    # Godot: käyttöliittymä, lentokartta ja teema
scripts/cockpit/, shaders/          # Godot: 3D-ohjaamo, avaruus ja varjostimet
assets/textures/                    # Godot: pintakartat ja Linnunrata (WebP, viedään sellaisinaan)
assets/data/, assets/fonts/         # Godot: tietokortit (planet_info.json) ja DejaVu Sans -kirjasin
scripts/orbit/                      # Godot: ratamekaniikka (Kepler, Lambert, ikkunahaku, linkoukset, kuut)
tests/, tools/                      # Godot: ikkunattomat testit, vertailuarvot ja run_tests.sh
```

## Tekstuurien lähteet

Ohjaamon kuva `assets/cockpit/ohjaamo.png` (1382 × 777) on pelin tekijän antama kuva; sen ikkuna-alue on tehty läpinäkyväksi. Ohjaamon panoraama on pelin tekijän tekemä (Gemini, 1456 × 720), ja se on suurennettu nelinkertaiseksi Real-ESRGANilla (malli realesrgan-x4plus, reunat kierrettyinä, jotta sauma pysyy jatkuvana).

Ohjaamon pintakartat ovat hakemistossa `assets/textures/` (tasavälinen lieriöprojektio, WebP, yhteensä noin 41 Mt). Jokaisesta kohteesta on peruskartta (enintään 2048 × 1024). Lisäksi on tarkat kartat, jotka haetaan vasta, kun kohde täyttää suuren osan ikkunasta: 8k (8192 × 4096) ja 4k Merkuriuksesta, Maasta, Marsista, Kuusta, Iosta, Europasta, Ganymedeestä ja Enceladuksesta sekä 4k Venuksesta, Jupiterista, Saturnuksesta, Phoboksesta ja Tritonista (näistä ei ole tarkempaa lähdettä tai lähteen tarkkuus ei riitä 8k:hon). 8k-karttaa käytetään vain tietokoneella; kosketusnäyttölaitteet ja heikommat näytönohjaimet saavat 4k-kartan.

| Kohde | Lähde | Lisenssi |
| --- | --- | --- |
| Merkurius, Venus (pilvikerros), Maa, Mars, Jupiter, Saturnus ja renkaat, Uranus, Neptunus, Kuu | [Solar System Scope](https://www.solarsystemscope.com/textures/), NASAn aineistoon perustuvat kartat. Maan karttaan on yhdistetty saman lähteen pilvikartta. | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Phobos | Viking-luotainten mosaiikki, NASA/JPL/USGS ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Phobos_Viking_Mosaic_DLRcontrol_7200.jpg)); sävytetty ruskeanharmaaksi | public domain |
| Io | Galileo- ja Voyager-luotainten värimosaiikki (Io GalileoSSI-Voyager Global Mosaic ClrMerge 1km), [USGS Astrogeology](https://astrogeology.usgs.gov/search/map/io_galileo_ssi_voyager_color_merged_global_mosaic_1km) | public domain |
| Europa | Seek9750: Moon Europa color map ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Moon_Europa_color_map.jpg)), NASAn kuvista | CC0 |
| Ganymedes | Björn Jónsson: Map of Ganymede, NASAn kuvista ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Map_of_Ganymede_by_Bj%C3%B6rn_J%C3%B3nsson.jpg)). Tarkoissa kartoissa värit ovat tästä kartasta ja hienot yksityiskohdat USGS:n Voyager- ja Galileo-mosaiikin kirkkaudesta ([USGS Astrogeology](https://astrogeology.usgs.gov/search/map/ganymede_voyager_galileo_ssi_global_color_mosaic_1435m)) | vapaa käyttö, tekijä mainittava; USGS public domain |
| Enceladus | Cassini-luotaimen värikartta PIA18435, NASA/JPL-Caltech/SSI/LPI ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Enceladus_Color_Map.jpg)) | public domain |
| Maan päiväkartta ilman pilviä, pilvikerros ja yövalot (Godot-versio, `assets/textures/maa-*`) | [Solar System Scope](https://www.solarsystemscope.com/textures/) Wikimedia Commonsin kautta: 8k earth daymap, clouds, nightmap ja 2k specular map; pienennetty ja muunnettu WebP:ksi (`tools/make_textures.gd`) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Linnunrata (Godot-versio, `assets/textures/linnunrata-4k.webp`) | NASA/Goddard Space Flight Center Scientific Visualization Studio: [Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/), Milkyway 2020 (Wikimedia Commonsin 3840 px versio), muunnettu WebP:ksi | public domain (NASA) |
| Kirjasin (Godot-versio) | [DejaVu Sans](https://dejavu-fonts.github.io/) (`assets/fonts/`) | Bitstream Vera -lisenssi, ks. `assets/fonts/LICENSE-DejaVu.txt` |
| Triton | Voyager 2:n värikartta PIA18668, NASA/JPL-Caltech/LPI ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Triton_Map.jpg)). Voyager kuvasi vain osan pinnasta: kuvaamaton pohjoinen alue on täytetty ympäristön sumennetulla värillä, ja tehostettuja värejä on haalistettu. | public domain |

## Julkaisu

GitHub-julkaisu (`gh release create vX.Y.Z`) käynnistää `release.yml`:n, joka vie Windows- ja Linux-versiot ja
liittää ne julkaisuun (Sisunautti-windows.zip, Sisunautti-linux.zip) sekä käynnistää `main`-haarasta `pages.yml`:n,
joka vie selainversion (Compatibility, `web_nothreads`-pohja) GitHub Pagesiin. Pagesiin kopioidaan myös `tools/web/sw.js`,
joka korvaa vanhan selainversion service workerin ja poistaa sen. `ci.yml` ajaa ikkunattomat testit jokaisesta
pushista.
