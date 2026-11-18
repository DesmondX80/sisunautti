# Sisunautti

Avaruuslentopeli selaimessa. Lähdetään laukaisualustalta Maan pinnalta kiertoradalle ja sieltä planeetoille ja niiden
kuille. Radat, laukaisuikkunat ja polttoaineen kulutus (Δv) lasketaan oikeilla taivaanmekaniikan kaavoilla, ja
lentoa seurataan 3D-ohjaamosta.

- Peli: https://desmondx80.github.io/sisunautti/

Peli syntyi OmaAvaruus-sovelluksen ([DesmondX80/omaavaruus](https://github.com/DesmondX80/omaavaruus)) Avaruuslento-osiona
ja eriytettiin omaksi pelikseen. Tallennetut pelit jatkuvat: molemmat sivut ovat samassa alkuperässä
(`desmondx80.github.io`), ja tallennusavaimet (`avaruuslento*`) ovat ennallaan.

> **Siirto Godotiin käynnissä.** Peli siirretään Godot 4.7 -pelimoottorille (issuet #7–#12), ja Godot-versio
> korvaa selainversion: sama peli julkaistaan työpöydälle (Windows, Linux) ja selaimeen samaan osoitteeseen.
> Godot-projekti on repon juuressa, ja nykyinen selainversio on hakemistossa `web/`, kunnes Godot-versio on sen tasolla.

## Kehitys: Godot-versio

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
- Kuvakaappaukset käyttöliittymän tiloista (vaatii ikkunan): `godot -- --uishotstest=/polku/kuviin --size=390x844`.
- Ratamekaniikka on hakemistossa `scripts/orbit/` (`planets.gd`, `flight.gd`, `window_search.gd`). Laskut tehdään
  64-bittisillä `float`-luvuilla (`PackedFloat64Array`), ja laukaisuikkunoiden haku jaetaan ruutujen kesken.
  `orbitcomparetest` vertaa tuloksia selainversioon (`tests/data/orbit_reference.json`, luodaan komennolla
  `node tools/make_orbit_reference.mjs` sen jälkeen, kun `web/`-hakemistossa on ajettu `npm ci`).

### Vienti

Vientipohjat (export templates) asennetaan editorista: *Editor → Manage Export Templates*.

```bash
godot --headless --export-release "Windows Desktop" export/windows/Sisunautti.exe
godot --headless --export-release "Linux" export/linux/Sisunautti.x86_64
godot --headless --export-release "Web" export/web/index.html   # web_nothreads-pohja, ei vaadi COOP/COEP-otsakkeita
```

`export/` ei ole versionhallinnassa.

## Kehitys: selainversio (`web/`)

```bash
cd web
npm install
npm run dev      # http://localhost:8000
npm test
```

Selainversio on pelkkiä staattisia tiedostoja (ES-moduulit ilman käännösvaihetta), eikä se tarvitse palvelinta.

## Pelin kulku

peli, jossa lähdetään raketilla Maan pinnalta kiertoradalle ja sieltä muille planeetoille. Peli hakee seuraavan kahden vuoden laukaisuikkunat Lambertin ratkaisuilla ja näyttää halvimman ja nopeammat siirtoradat Δv-kustannuksineen. Laukaisun jälkeen lentonäkymässä on lentoaika (T+), kalenteripäivä, nopeus Auringon ja lähimmän planeetan suhteen, etäisyys kohteeseen, valon kulkuaika Maahan sekä kartta, jolle on piirretty raketti, kuljettu reitti ja tuleva rata. Aikaa voi kiihdyttää 1×:stä vuoteen sekunnissa, ja kiihdytys pienenee itsestään ennen vaikutuspiirin rajaa ja saapumista. Pelin kello kulkee oikeassa ajassa myös pelin ollessa kiinni, ja tila tallentuu selaimeen.

- - **Laukaisu Maan pinnalta**: uusi peli alkaa laukaisualustalta. Lähtölaskenta (T− 10 s) päättyy sytytykseen, ja kantoraketti nostaa aluksen 200 km:n kiertoradalle 8 min 30 s:ssa: vaihe 1, suurin aerodynaaminen kuorma (Max Q), vaiheen erotus 2 min 30 s kohdalla ja vaihe 2. Näkymässä ovat korkeus, nopeus, kiihtyvyys ja vaihe. Ohjaamo tärisee vaiheen mukaan (kovimmin laukaisussa ja Max Q:ssa, nykäys vaiheen erotuksessa), nokka kääntyy pystystä vaakaan, ja päivällä sininen taivas tummuu ilmakehän ohetessa. Nousua ei integroida voimista: korkeus ja nopeus seuraavat sileitä käyriä, jotka päättyvät täsmälleen ympyräradan tilaan. Nousu ei kuluta aluksen omaa polttoainetta.
- - **Lähtöpoltto kiertoradalta**: kun laukaisuikkuna on auki, lentäjä kytkee lähtöpolton päälle. Alus kääntyy nokka menosuuntaan ja jatkaa kiertorataa, ja moottori syttyy itsestään kohdassa, josta poistumishyperbelin asymptootti osoittaa lähtösuuntaan (enintään yhden kierroksen päässä; siirtorata ratkaistaan uudelleen sille hetkelle). Venyneellä radalla poltto tehdään seuraavassa perikeskuksessa.
- - **Matalat saapumisradat**: perillä jarrutetaan Merkuriuksella, Venuksella ja Marsilla 500 km:n ympyräradalle (Maassa 200 km). Jättiläisplaneetoilla radan perikeskus on 3 000–5 000 km pilvien yläpuolella, mutta rata on venynyt, koska matalalle ympyräradalle jarruttaminen veisi 7–17 km/s. Alus jää radalle siihen kohtaan, johon se saapui.
- - **Ilmajarrutus jättiläisplaneetoilla**: saapuessa voi moottorijarrutuksen sijaan ilmajarruttaa. Alus sukeltaa kaasukehän yläosaan (noin 200 km pilvien yläpuolelle), ja ilmanvastus jarruttaa sen matalalle ympyräradalle (Jupiter 5 000 km, muut 3 000 km). Polttoainetta kuluu vain radan nostoon (0,3–0,7 km/s), ja ohjaamo tärisee plasman hehkuessa ikkunoissa. Lähtö matalalta radalta maksaa täyden hinnan: Jupiterilta noin 17 km/s, Saturnukselta 11, Uranukselta ja Neptunukselta 7. Kemiallinen raketti ei pääse Jupiterin matalalta radalta pois, ja peli varoittaa siitä ennen valintaa. Ionialus ei voi ilmajarruttaa.
- - **Tutkiminen ja lokikirja**: perillä jarrutetaan kiertoradalle (jos polttoaine ei riitä, alus ohittaa planeetan ja jää Auringon kiertoradalle). Planeetan tietokortissa ovat koko, massa, painovoima, päivän ja vuoden pituus, lämpötila, kaasukehä ja kuut. Vuorokauden kartoituksen jälkeen planeetta on tutkittu, sen faktat paljastuvat ja polttoaine täydennetään. Lokikirjassa ovat lennot, tutkitut planeetat (x/8), kokonaislentoaika, kuljettu matka ja huippunopeus.
- - **Kurssikorjaukset**: lennon aikana moottoria voi polttaa eteen, taakse, sisään tai ulos (10 m/s–1 km/s). Ennuste kertoo ennen polttoa, osuuko alus kohteen vaikutuspiiriin vai ohittaako se kohteen, ja uusi rata näkyy kartalla. Automaattinen korjaus laskee reitin takaisin kohteeseen.
- - **Linkous, kuut ja alukset**: reittihaku ehdottaa myös yhden painovoimalinkouksen reittejä (esim. Maa → Venus → Merkurius), kun ne ovat suoraa lentoa halvempia tai nopeampia. Kohteina ovat myös Kuu, Phobos, Io, Europa, Ganymedes, Titan, Enceladus ja Triton, joihin lennetään emoplaneetan kiertoradalta, ja niillä on omat tietokorttinsa. Maan kiertoradalla voi vaihtaa alusta: kemiallinen raketti (14 km/s), ydinlämpöraketti (22 km/s, vetyä vain Maasta ja kaasujättiläisiltä) tai ionialus (45 km/s, mutta lähtö ja jarrutus ovat kuukausien spiraaleja).
- - **3D-ohjaamo**: lentoa voi seurata aluksen ikkunasta (WebGL, [three.js](https://threejs.org/) 0.170.0, MIT-lisenssi, tallennettu hakemistoon `web/js/vendor/`; ladataan vasta, kun ohjaamo avataan). Tähdet ovat oikeissa suunnissa (kirkkaat tähdet OmaAvaruuden taivaankartan luettelosta, himmeä tausta tihenee Linnunradan tasoa kohti), ja Aurinko ja planeetat ovat oikeassa suunnassa ja näennäisessä koossa. Ohjaamossa on kaareva kuomun kehys vinotukineen ja ristikkotukineen kulunutta metallia, keskikonsoli kolmella päänäytöllä (lentoaika, nopeus, etäisyys ja polttoaine), sivuilla koneistosylinterit ja kaapeliniput, käsinojissa ohjainsauva ja tehovipu sekä yläkulmissa kaksi kattonäyttöä: navigointinäyttö piirtää planeetat, aluksen ja suunnan kohteeseen oikeista sijainneista, ja järjestelmänäyttö näyttää polttoaineen ja aikakiihdytyksen. Auringonvalo tulee ohjaamoon ikkunoista oikeasta suunnasta, ja kehys ja tuet heittävät varjonsa (varjokartta); lähellä oleva planeetta tai kuu valaisee ohjaamoa omalla värillään, ja valo himmenee kauempana Auringosta. Planeetan tai kuun varjossa auringonvalo sammuu sen mukaan, kuinka suuren osan Auringon kiekosta kappale peittää. Sisätila rakennetaan koodissa (`web/js/cabin.js`) perusmuodoista ja piirretyistä tekstuureista, joten mallitiedostoja ei ole. Katsetta käännetään raahaamalla tai asentoantureilla. Planeettojen ja kuiden pinnat ovat luotainkuvista koottuja karttoja (`web/textures/`, ks. [Tekstuurien lähteet](#tekstuurien-lähteet)), jotka haetaan vasta, kun kohde näkyy kiekkona, ja lähellä kohdetta tilalle vaihtuu tarkempi 4k- tai 8k-kartta. Siihen asti ja ilman verkkoa näkyy selaimessa piirretty tyylitelty pinta (Maan mantereet Natural Earth 110m, public domain). Titan on piirretty, koska sen pinta on utukerroksen peitossa. Jos WebGL ei toimi, näytetään kartta.
- - **Leveä näyttö**: vähintään 1000 pikselin levyisessä ikkunassa ohjaamo tai kartta täyttää koko ikkunan ja ohjaimet ovat oikean reunan paneelissa. Yläpalkin painike vie pelin selaimen koko näytön tilaan. Paneelin voi piilottaa yläpalkin painikkeesta, jolloin se liukuu oikealle ja näkymä levenee koko ikkunaan; valinta tallentuu selaimeen.

## Rakenne

```
project.godot, export_presets.cfg   # Godot-projekti (Forward+, web: Compatibility)
scripts/, scenes/, ui/, assets/     # Godot: logiikka, scenet, käyttöliittymä, resurssit
scripts/game.gd, scripts/format.gd   # Godot: pelin tila, kello ja tallennus; suomenkielinen muotoilu
scripts/ui/, ui/                    # Godot: käyttöliittymä, lentokartta ja teema
assets/data/, assets/fonts/         # Godot: tietokortit (planet_info.json) ja DejaVu Sans -kirjasin
scripts/orbit/                      # Godot: ratamekaniikka (Kepler, Lambert, ikkunahaku, linkoukset, kuut)
tests/, tools/                      # Godot: ikkunattomat testit, vertailuarvot ja run_tests.sh
web/               # selainversio:
  index.html, styles.css
  manifest.webmanifest, icons/   # PWA-manifesti ja kuvakkeet (icon.svg on lähde, PNG:t siitä piirrettyjä)
  sw.js              # service worker: verkko ensin, ilman verkkoa välimuisti
  textures/          # planeettojen ja kuiden pintakartat (WebP, lähteet alla)
  js/
    main.js          # käynnistys ja Tietoa-ikkuna
    voyage.js        # pelin tila, kello, käyttöliittymä ja lentokartta
    flight.js        # ratamekaniikka: Kepler, Lambert, laukaisuikkunat, linkoukset, nousu ja kiertoradat
    cockpit.js       # 3D-ohjaamo (three.js) ja taivaan kappaleet
    cabin.js         # ohjaamon sisätila perusmuodoista
    textures.js      # selaimessa piirretyt varapinnat (land.js: Maan mantereet)
    planets.js       # planeettojen rata-alkiot ja sijainnit
    solarsystem.js   # aurinkokunnan kartan pohja
    planetinfo.js    # planeettojen ja kuiden tietokortit
    stars.js         # kirkkaat tähdet
    core.js          # apufunktiot ja tallennus
    vendor/          # three.js 0.170.0 (MIT)
  test/              # vitest: ratamekaniikka ja tiedostolistojen tarkistus
```

## Tekstuurien lähteet

Ohjaamon pintakartat ovat hakemistossa `web/textures/` (tasavälinen lieriöprojektio, WebP, yhteensä noin 41 Mt). Jokaisesta kohteesta on peruskartta (enintään 2048 × 1024). Lisäksi on tarkat kartat, jotka haetaan vasta, kun kohde täyttää suuren osan ikkunasta: 8k (8192 × 4096) ja 4k Merkuriuksesta, Maasta, Marsista, Kuusta, Iosta, Europasta, Ganymedeestä ja Enceladuksesta sekä 4k Venuksesta, Jupiterista, Saturnuksesta, Phoboksesta ja Tritonista (näistä ei ole tarkempaa lähdettä tai lähteen tarkkuus ei riitä 8k:hon). 8k-karttaa käytetään vain tietokoneella; kosketusnäyttölaitteet ja heikommat näytönohjaimet saavat 4k-kartan.

| Kohde | Lähde | Lisenssi |
| --- | --- | --- |
| Merkurius, Venus (pilvikerros), Maa, Mars, Jupiter, Saturnus ja renkaat, Uranus, Neptunus, Kuu | [Solar System Scope](https://www.solarsystemscope.com/textures/), NASAn aineistoon perustuvat kartat. Maan karttaan on yhdistetty saman lähteen pilvikartta. | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Phobos | Viking-luotainten mosaiikki, NASA/JPL/USGS ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Phobos_Viking_Mosaic_DLRcontrol_7200.jpg)); sävytetty ruskeanharmaaksi | public domain |
| Io | Galileo- ja Voyager-luotainten värimosaiikki (Io GalileoSSI-Voyager Global Mosaic ClrMerge 1km), [USGS Astrogeology](https://astrogeology.usgs.gov/search/map/io_galileo_ssi_voyager_color_merged_global_mosaic_1km) | public domain |
| Europa | Seek9750: Moon Europa color map ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Moon_Europa_color_map.jpg)), NASAn kuvista | CC0 |
| Ganymedes | Björn Jónsson: Map of Ganymede, NASAn kuvista ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Map_of_Ganymede_by_Bj%C3%B6rn_J%C3%B3nsson.jpg)). Tarkoissa kartoissa värit ovat tästä kartasta ja hienot yksityiskohdat USGS:n Voyager- ja Galileo-mosaiikin kirkkaudesta ([USGS Astrogeology](https://astrogeology.usgs.gov/search/map/ganymede_voyager_galileo_ssi_global_color_mosaic_1435m)) | vapaa käyttö, tekijä mainittava; USGS public domain |
| Enceladus | Cassini-luotaimen värikartta PIA18435, NASA/JPL-Caltech/SSI/LPI ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Enceladus_Color_Map.jpg)) | public domain |
| Kirjasin (Godot-versio) | [DejaVu Sans](https://dejavu-fonts.github.io/) (`assets/fonts/`) | Bitstream Vera -lisenssi, ks. `assets/fonts/LICENSE-DejaVu.txt` |
| Triton | Voyager 2:n värikartta PIA18668, NASA/JPL-Caltech/LPI ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Triton_Map.jpg)). Voyager kuvasi vain osan pinnasta: kuvaamaton pohjoinen alue on täytetty ympäristön sumennetulla värillä, ja tehostettuja värejä on haalistettu. | public domain |

## Julkaisu

Push `main`-haaraan julkaisee selainversion automaattisesti: `pages.yml` kopioi hakemiston `web/` sivuston tiedostot
GitHub Pagesiin ja asettaa commitin tunnisteen service workerin versioksi (`sw.js`). `ci.yml` ajaa selainversion testit ja
Godot-version ikkunattomat testit (Godot 4.7.2 välimuistista).
