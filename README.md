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

## Aloitusvalikko

Peli alkaa aloitusvalikosta (`scripts/ui/start_menu.gd`): Jatka peliä (kun peli on tallessa), Uusi peli (kysyy
vahvistuksen, jos tallennus korvataan), Asetukset (grafiikan laatu, aluksen häiriöt, äänenvoimakkuus ja mykistys, koko näyttö) ja Lopeta peli (vain työpöydällä).
Pelistä valikkoon pääsee yläpalkin ≡-painikkeella tai Esc-näppäimellä. Taustalla on James Webb -avaruusteleskoopin
kuva Kosmiset kalliot Carinan sumussa (NASA, ESA, CSA, STScI, [CC BY 4.0](https://esawebb.org/copyright/),
`assets/menu/taustakuva.webp`) hitaasti liukuen ja zoomaten, hiiren mukaan parallaksina ja tähdet tuikkien
(`shaders/menu_bg.gdshader`).

## Äänet

Äänet syntetisoidaan käynnistyksessä (`scripts/sound_synth.gd`, noin 0,2 s), paitsi ohjaamon taustaääni, joka on äänite
`assets/sound/ohjaamo_tausta.ogg` (freesound_community: [Spaceship Ambient](https://pixabay.com/sound-effects/spaceship-ambient-27988/),
Pixabayn sisältölisenssi; leikattu saumattomaksi 51 sekunnin silmukaksi). `scripts/game_sound.gd`
soittaa ne pelin tilan mukaan: laukaisun jyrinä tärinän ja työnnön mukaan, moottorin pauhu poltoissa, ilmajarrutuksen
plasman suhina ja rätinä, ohjaamon hiljainen taustaääni, painikkeiden napsautus, lähtölaskennan viiden viimeisen
sekunnin piippaukset. Lennon vaiheen vaihtuessa (kiertorata, lähtöpoltto, vaikutuspiiri, saapuminen, jarrutus
kiertoradalle) kuuluu NASAn radiokuulutus `assets/sound/vaihe_kuulutus.ogg`: Apollo-lentojen Quindar-piippaus
(2525 Hz), lennonjohdon "Stage separation confirmed" ja loppupiippaus (2475 Hz). Kuulutus on leikattu NASAn
IM-2-laukaisun lähetyksestä ([NASA Image and Video Library](https://images.nasa.gov/details/KSC-20250226-AU-ILW01-0004-SpaceX_CLPS_IM-2_Live_Launch_Coverage_Program-1_LOS-2), public domain).
Kartoituksen valmistuminen kuittaa pelkällä Quindar-piippauksella.
Voimakkuus ja mykistys ovat aloitusvalikon asetuksissa (`Settings.volume`, `Settings.muted`). Valikon ollessa auki
pelin äänet hiljenevät.

Ohjaamon radio (yläpalkin ♪ Radio, `scripts/radio.gd`) soittaa viittä kanavaa: Avaruustunnelma, Syntikka,
Johtokeskus (Apollo-lentojen radioliikennettä), Rock ja Klassinen. Kanavan kappaleet soivat peräkkäin, ja kanavaa
vaihdettaessa kuuluu radiokohina. Valittu kanava ja musiikin voimakkuus tallentuvat asetuksiin. Kaikki kappaleet ovat
vapaasti käytettäviä (CC0 tai public domain), ja ne on pakattu Ogg Vorbisiksi hakemistoon `assets/music/`:

| Kanava | Kappale | Lähde ja lisenssi |
| --- | --- | --- |
| Avaruustunnelma | Cosmic Navigation; Outer Space Loop | synth-thetic; wipics ([OpenGameArt](https://opengameart.org/content/cosmic-navigation), [OpenGameArt](https://opengameart.org/content/outer-space-loop)), CC0 |
| Syntikka | Space Synth Wave; Space City | pro-sensory; mintodog ([OpenGameArt](https://opengameart.org/content/space-synth-wave), [OpenGameArt](https://opengameart.org/content/space-city)), CC0 |
| Johtokeskus | Apollo 11:n laskeutuminen Kuuhun; Apollo 13 "Houston, we've had a problem" | NASA ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Pouso_da_Apollo_11_na_Lua.ogg), [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Apollo13-wehaveaproblem.ogg)), public domain |
| Rock | Epic Rock Battle Theme; Space Adventure | hydrogene; mintodog ([OpenGameArt](https://opengameart.org/content/jrpg-epic-rock-battle-theme-1), [OpenGameArt](https://opengameart.org/content/space-adventure)), CC0 |
| Klassinen | Johann Strauss II: An der schönen blauen Donau; Gustav Holst: Planeetat – Jupiter | European Archive, CC0 ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Strauss,_An_der_sch%C3%B6nen_blauen_Donau.ogg)); Yhdysvaltain ilmavoimien soittokunta, public domain ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Holst_The_Planets_Jupiter.ogg)) |

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
  Näppäimet: Esc valikko, M manuaaliohjaus (W/S/A/D/Q/E, Shift/Ctrl kaasu, X, B), 1–8 aikakiihdytys, + ja − zoomaus, P sivupaneeli, T kameranäyttö (kohde, taka, 360°), nuolinäppäimet 360°-kameran kääntö, F 360°-kamera koko näytölle, F11 koko näyttö. Kartan zoomaus myös hiiren rullalla ja
  nipistämällä.
- 3D-ohjaamo (`scripts/cockpit/`, varjostimet `shaders/`): etuseinä on ohjaamon kuva (`assets/cockpit/ohjaamo.png`)
  täsmälleen kuvan kuvakulmassa (vaakakulma noin 95°). Koska kamera vain kääntyy paikallaan, tasainen kuva näkyy oikein
  joka suuntaan katsottaessa. Kuva piirretään 2D-kerroksena 3D-näkymän päälle (`shaders/cockpit_overlay.gdshader`):
  jokaiselle pikselille lasketaan katsesuunta ja siitä kohta kuvassa, joten kuvan värit säilyvät ilman sävykartoitusta.
  Kuvan ikkuna-alue on läpinäkyvä (alfakanava, ääriviiva `Cabin.WINDOW`), joten avaruus näkyy sen läpi, ja kuvan
  näyttöjen päälle piirretään pelin näytöt projektiivisella kuvauksella (kulmat kuvasta, `Cabin.MONITORS`). Kuvan
  ympärillä on ohjaamon 360°-panoraama (`assets/cockpit/panoraama-6k.webp` 5824 × 2880 työpöydällä,
  `panoraama.webp` 4096 × 2048 selaimessa), joka lasketaan samasta katsesuunnasta; etukuva häivytetään reunoiltaan
  panoraamaan. Panoraaman pituuskulmia venytetään edessä niin, että sen 66° osuu etukuvan reunaan (47,5°): panoraaman oma kojelauta näyttöineen jää kokonaan etukuvan taakse ja sen sivukonsolit jatkavat etukuvan konsoleita (taakse kuva on ennallaan). Etukuvan sivuilla on ohjaamon sivukuva (`assets/cockpit/ohjaamo_sivu.png`, tehty skriptillä `tools/make_cockpit_side.py` käyttäjän kuvasta `tools/data/ohjaamo_oikea.jpg`) omana kuvatasonaan: ikkuna jatkuu viistoon pilariin, kojelauta sivukonsoliin ja sen takana on seinä ja ovi. Kuvan suunta ja polttoväli on sovitettu niin, että sen näyttö osuu etukuvan kohdekameranäyttöön (katse 47° oikealle, `Cabin.SIDE_*`), ja ikkunan pilari osuu etukuvan reunaan. Vasen sivu on sama kuva peilattuna ja katkaistuna ennen ovea. Sivukuvan reunat häivytetään panoraamaan, joka jatkuu oikealla sen ovesta ja vasemmalla pylväästä. Panoraaman sävy on sovitettu etukuvan viileään metalliin. Katse ei laske etukuvan alareunan alle (`CockpitView.min_pitch`), joten pilotin kädet lähtevät aina näkymän alareunasta. Panoraaman horisonttia on laskettu 11°, jotta sen kojelauta jää etukuvan kojelaudan taakse, ja sen omat
  ohjainsauvat on retusoitu pois (LaMa-inpainting), joten alas katsottaessa näkyvät vain lentäjän kädet sauvoissa. Näytöt (tutka, aluskaavio, tähtäin,
  järjestelmät, kohdekamera ja pikkunäyttö) ovat `SubViewport`-tekstuureja kuvan näyttöjen muodossa (leveys 1024),
  jotka piirretään uudelleen enintään 20 kertaa sekunnissa (pitkät tekstit sovitetaan näytölle pienentämällä fonttia,
  viimeisenä keinona ellipsillä, `CockpitScreen.fit_text`); järjestelmänäytön hologrammi näyttää
  kohteen pinnan pyörivänä pallona (`shaders/globe.gdshader`). Kohdekamera on kaukoputki aluksen paikalla samassa 3D-maailmassa: se osoittaa kohteeseen (ilman kohdetta Aurinkoon), joten kuvassa on täsmälleen sama puoli, vaihe, ilmakehä, pilvet ja renkaat kuin ikkunasta katsottuna, pohjoinen ylhäällä. Kohde täyttää näytön kehän (zoom jopa kymmeniätuhansia kertoja; kapea kuvakulma ja sivusiirto frustum-projektiolla, kaukaisten kappaleiden pisteet `Space.DOT_LAYER` eivät näy ja kohteelle ladataan valokuvakartta). Lähellä, kun kohde ei mahtuisi kuvaan (kiertoradalla ja laukaisualustalla), näytöllä on kohde suunnattuna pallona: keskellä kohta, jonka yllä alus on (merkki ALUS ja korkeus), Auringon valo oikealta suunnalta ja Maalla pilvet ja yövalot. Aurinkoon katsottaessa kuvassa on aurinkosuodin (oranssi asteikko ja granulaatio). Kohdekameranäytön voi vaihtaa takakameraksi (painike Takakamera tai T): toinen kamera samassa 3D-maailmassa kuvaa aluksen taakse ja 50° alas (kiertoradalla planeetta näkyy), ja kamera kääntyy niin, että lähdön jälkeen poistuva planeetta pysyy kuvassa; kuvassa on kamerasyötteen juovat, linssivirhe ja kohina (`shaders/rear_camera.gdshader`), ja se päivittyy näytön tahdissa. Kolmantena on 360°-kamera aluksen katolla (painike tai T uudelleen): sitä käännetään raahaamalla kameranäytöllä tai nuolinäppäimillä täysi kierros ja ±85° ylös ja alas, ja lähellä planeettaa tai kuuta se on vakautettu paikalliseen pystysuuntaan (horisontti pysyy vaakasuorassa myös pystyssä alustalla). Kuvassa on suuntimanauha (KEULA 0°, PERÄ 180°) ja kallistusasteikko kuvan mittakaavassa. Painikkeella Koko näyttö (F) 360°-kamera täyttää ohjaamonäkymän näytön tarkkuudella; silloin rulla tai nipistys zoomaa (1–8×) ja Esc palaa ohjaamoon. Ulkokamerat eivät näe ohjaamon lasia eivätkä plasmaa (`Cabin.INTERIOR_LAYER`). Näyttöä napsauttamalla katse kääntyy siihen ja
  kuvakulma kapenee niin, että näyttö täyttää kuvan; uusi napsautus, Esc tai Loitonna palauttaa näkymän. Rullalla
  ja nipistämällä zoomataan vapaasti. Kuva elää pelin mukana: vasen käsi työntää tehovipua eteen moottorin työnnön mukaan, oikean käden ohjainsauva värähtelee tärinässä ja kallistuu aluksen kääntyessä (pehmeä siirto varjostimessa), ja paneelien pienet valot (valokartta `assets/cockpit/ohjaamo_valot.png`, tehty skriptillä `tools/make_cockpit_lights.py`) vilkkuvat kukin omassa tahdissaan; kuusi niistä on merkkivaloja (moottori, aikakiihdytys, suunta, vaikutuspiiri, ilmakehä ja polttoaineen varoitus). Moottorin ja plasman hehku sävyttää ohjaamon kuvaa, ja ikkunan lasissa on
  likaa ja naarmuja, jotka Aurinko sytyttää häikäisyksi. Avaruudessa ovat kirkkaat tähdet HDR-pisteinä ja Linnunrata taustana, Auringon
  HDR-kiekko hehkuineen ja linssiheijastus (ohjaamon rakenteet peittävät sen syvyyspuskurin perusteella), planeettojen
  ja kuiden pintakartat (2k, lähellä 4k tai 8k, Maalla, Kuulla ja Marsilla Ultra-tasolla 16k), ilmakehän sironta varjostimella, Maan
  erillinen pilvikerros, kaupunkien valot ja merien heijastus sekä Saturnuksen läpikuultavat renkaat varjoineen.
  Ilmakehän sironta (`shaders/atmosphere.gdshader`) kerää näkösäteen matkalta sironneen valon ja vaimennuksen:
  tiheys laskee eksponentiaalisesti ja hiipuu kuoren ylärajalla nollaan, joten kiertoradalta horisontin yllä on ohut
  sininen kaari, joka häipyy pehmeästi mustaan, ja kaukainen pinta häipyy horisonttia kohti usvaan. Auringonvalo
  punertuu terminaattorilla. Kiertoradalta, kun kartan piste on kuvapistettä suurempi, pinnan rajat (rannikot,
  laaksot) rikotaan kohinalla, paikallista kontrastia terävöitetään ja maalle lisätään hienoa vaihtelua; pilvien
  reunat hajoavat ja niiden pintaan tulee Auringon valaisemia kumpuja, meren välke hajoaa aallokkoon ja yön
  kaupunkivalot jakautuvat pieniksi pisteiksi (`surface_detail`, Keski, Korkea ja Ultra). Maan 16k-päiväkartta on
  JPEG, joka tuodaan näytönohjaimen pakkaamana (S3TC, 89 Mt; pakkaamattomana 700 Mt), samoin Kuun ja Marsin 16k-kartat.
  Kuun pinnassa on kohokuvio LRO-luotaimen laserkorkeusmallista (`kuu-pinta*.webp`: pinnan normaali ja paikallinen
  korkeus): rinteet valaistaan oikein, ja varjot lasketaan kulkemalla korkeuskarttaa Aurinkoa kohti (Matala 6,
  Keski 10, Korkea 16 ja Ultra 24 askelta, puolivarjo kasvaa etäisyyden mukana), joten terminaattorin lähellä
  kraatterit täyttyvät pitkistä varjoista ja vuorenhuiput valaistuvat sen takana. Ilmaton pölypinta heijastaa
  Lommel–Seeliger-mallin mukaan (täysikuu on reunoja myöten kirkas), yöpuolella on Maan vaiheen mukainen sinertävä
  maanvalo, ja kiertoradalta näkyy korkeusmallin erottelukykyä pienempiä kraattereita (halkaisija 0,2–4 km:
  malja, valli ja tuoreiden kraatterien vaalea heittelykehä), jotka häivytetään ennen kuin ne kutistuvat
  kuvapistettä pienemmiksi. Marsissa on sama kohokuvio MGS-luotaimen MOLA-korkeusmallista (`mars-pinta*.webp`;
  rinteitä korostetaan, koska 1,3 km:n kartta pehmentää niitä), ja värikartta on Viking-luotainten mosaiikki, jonka
  sinertävät tummat alueet on väritetty kirkkauden mukaan Marsin ruskeiksi. Marsin ohut pölyinen ilmakehä sirottaa
  valoa enimmäkseen eteenpäin (Henyey–Greenstein-vaihefunktio): selän takaa paistava Aurinko ei sumenna pintaa,
  horisontin yllä on usvakaari ja vastavalossa ilmakehä hehkuu. Ilmakehän varjo riippuu korkeudesta: yöpuolen
  yllä ylempi ilma on vielä valaistu, kun pinnan lähellä oleva tiheä kerros on jo pimeä. Kappaleet piirretään
  kameran suhteen: 64-bittiset sijainnit muutetaan suunnaksi ja logaritmisesti puristetuksi etäisyydeksi, ja niiden
  syvyysarvo kirjoitetaan aina ohjaamon taakse. Valaistus: auringonvalo ikkunoista pehmeine varjoineen, lähimmän
  kappaleen heijastama valo sen värisenä, himmeneminen kaukana Auringosta ja pimennys, kun kappale peittää Auringon.
  AgX-tonemapping, hehku ja automaattinen valotus. Laukaisussa päivätaivas, liekki ja pakokaasupilvi (GPU-partikkelit)
  ja tärinä; poltoissa moottorin hehku; ilmajarrutuksessa virtaava plasma, oranssi valo ja kipinät.
- Laatutasot (Tietoa-ikkunassa): Matala, Keski, Korkea ja Ultra muuttavat varjojen tarkkuutta, SSAO:ta (Korkea),
  SSR:ää (Ultra), reunanpehmennystä, partikkelimääriä, pintakarttojen tarkkuutta (Matala 2k, Keski 4k, Korkea 8k,
  Ultra 8k sekä Maa, Kuu ja Mars 16k), Kuun ja Marsin varjojen tarkkuutta, pinnan lähikuvan yksityiskohtia (ei Matalassa) ja ilmakehän näytteitä. Oletus valitaan näytönohjaimen mukaan. Selaimessa (Compatibility) enintään
  Keski, ilman SSAO:ta, SSR:ää ja automaattista valotusta, ja 8k- ja 16k-karttoja ei viedä selainversioon.
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

- - **Laukaisu Maan pinnalta**: uusi peli alkaa laukaisualustalta. Lähtölaskenta (T− 10 s) päättyy sytytykseen, ja kantoraketti nostaa aluksen 200 km:n kiertoradalle 8 min 30 s:ssa: vaihe 1, suurin aerodynaaminen kuorma (Max Q), vaiheen erotus 2 min 30 s kohdalla ja vaihe 2. Näkymässä ovat korkeus, nopeus, kiihtyvyys ja vaihe. Ohjaamo tärisee vaiheen mukaan (kovimmin laukaisussa ja Max Q:ssa, nykäys vaiheen erotuksessa), nokka kääntyy pystystä vaakaan, ja päivällä sininen taivas tummuu ilmakehän ohetessa. Laukaisualustan vieressä on laukaisutorni (`scripts/cockpit/launch_tower.gd`): punaoranssi teräsristikko, ukkosenjohdinmasto, huoltotasot, miehistön kulkusilta, vilkkuvat estevalot ja yöllä valonheittimet. Sen yläosa näkyy ikkunasta, ja nousussa torni liukuu alas ja katoaa näkyvistä muutamassa sekunnissa. Nousua ei integroida voimista: korkeus ja nopeus seuraavat sileitä käyriä, jotka päättyvät täsmälleen ympyräradan tilaan. Nousu ei kuluta aluksen omaa polttoainetta.
- - **Aluksen asento ja näkymä ikkunasta**: kiertoradalla nokka on menosuuntaan ja katto poispäin kappaleesta kuin lentokoneella matkakorkeudessa, joten planeetta tai kuu kaartuu ikkunan alaosassa (`CockpitState.body_frame`). Lähtöpolton jälkeen alus kiihdyttää eteenpäin, ja kappale vajoaa hiljalleen alle ja taakse. Lennolla nokka osoittaa menosuuntaan täsmälleen kuten lentokartan nuoli (`Flight.heading_velocity`: kuiden luona emoplaneetan suhteen, muuten Auringon suhteen), ja menosuunta näkyy ikkunan keskellä (ohjaamokuvan "suoraan eteen" on kojelaudan takana); kohde näkyy ikkunassa, kun se on menosuunnassa, ja aina kohdekamerassa ja tutkassa. Lähellä kappaletta (kulmasäde 3–20°) asento siirtyy pehmeästi radan mukaiseksi: nokka nopeuden suuntaan kappaleen suhteen ja kappale alla. Ohjaamonäkymän rata on lähtö- ja kohdekappaleen vaikutuspiirissä oikea hyperbeli (`Flight.ship_view`; myös kurssikorjauksen jälkeen, jos rata osuu pysäköintiradan sisäpuolelle, jottei kohde lakkaa lähestymästä), ja kaikki etäisyyslukemat (paneeli, näytöt, tutka) lasketaan tästä paikasta kohteen pintaan (`Flight.surface_distance`): 0 km tarkoittaa pintaa, ja perillä lukema on pysäköintiradan korkeus: lähtö- ja jarrutuspoltto tehdään perikeskuksessa pysäköintiradan korkeudella (esim. Kuun kiertoradalle 100 km:n korkeudelle kuten Apollo-lennoilla), ja vaikutuspiirin rajalla rata yhtyy siirtorataan.
- - **Aluksen häiriöt**: lennolla ja kiertoradalla aluksessa voi tulla vika (asetus Pois, Harvoin noin 12 min ja Usein noin 5 min pelattua aikaa välein; ei laukaisualustalla). Vika korjataan minipelillä ennen kuin aika loppuu, tai alus tuhoutuu: **sähkövika** (johdot kytketään samanvärisiin liittimiin vetämällä tai napauttamalla, raidalliset erottuvat raidasta), **ohjelmavirhe** (navigointitietokoneen koodista etsitään virheellinen rivi oireen perusteella ja valitaan oikea korjaus) ja **jäähdytysvuoto** (venttiileillä tasataan kolme painetta vihreälle alueelle). Väärä yritys vie 8 s. Vian aikana aikaa ei voi kiihdyttää, ohjaamo sykkii punaista hälytysvaloa, näytöillä vilkkuu VIKA-palkki, hälytys soi ja alus värisee; korjausikkunan voi piilottaa yläreunan banneriin. Ajastin kulkee vain pelattaessa (ei valikossa, taustalla eikä suljettuna). Tuhoutuessa tulee välähdys, tärinä ja räjähdys, näytöt katkeavat, ja peli alkaa alusta (`scripts/faults.gd`, `Game.fault_*`, `scripts/ui/fault_panel.gd`, `scripts/ui/game_over.gd`).
- - **Manuaaliohjaus**: ohjaamon painike *Manuaaliohjaus* (tai M) antaa aluksen pilotin käsiin. Aluksen voi kääntää vapaasti 360° (W/S nokka ylös ja alas, A/D kääntö, Q/E kallistus). Ohjaus on pehmeä: sauva kääntyy heti, mutta ohjausraketit kiihdyttävät kääntymistä vähitellen (0,25 rad/s², enintään 0,6 rad/s), ja sauvan palatessa keskelle vakautus pysäyttää kääntymisen (`CockpitView.turn_rate`). Kääntäminen muuttaa vain asentoa: kurssi muuttuu kaasulla (Shift/Ctrl, X nollaa, myös HUD-painikkeet), joka polttaa nokan suuntaan, ja jarrutus (pidä B) polttaa menosuuntaa vastaan. Ilman kaasua alus jatkaa samalla radalla. Kertynyt nopeuden muutos poltetaan radalle puolen sekunnin välein (`Game.manual_thrust`), polttoaine kuluu, aikakiihdytys palaa 1×:ään ja polton Δv kirjataan lokikirjaan. Kemiallinen ja ydinlämpöalus kiihtyvät 2 g:llä, ionialus omalla pienellä työnnöllään. Poltto toimii siirtolennolla (`Flight.apply_burn_vector`), Auringon kiertoradalla ja kappaleen kiertoradalla. Kiertoradalla poltto tekee radasta vapaan radan (`Flight.is_free_orbit`: paikka ja nopeus kappaleen suhteen, propagoidaan Keplerin mukaan). Myötäsuuntainen poltto venyttää rataa, ja pakonopeudessa rata muuttuu pakoradaksi: vaikutuspiirin rajalla alus siirtyy kuun ympäriltä emoplaneetan kiertoradalle tai planeetan ympäriltä Auringon kiertoradalle. Poltto kohti kappaletta laskee perikeskusta, ja kun rata leikkaa pinnan, aikakiihdytys rajataan 100×:ään ja alus törmää pintaan ja tuhoutuu. HUD näyttää nokan kulman menosuunnasta ja kiertoradalla radan muodon (perikeskus ja apokeskus, pakoradalla v∞) sekä varoituksen, jos rata leikkaa pinnan. Kiertoradalla tehty poltto peruu suunnitellun lähdön, koska se laskettiin vanhalle radalle. Laukaisussa ohjaa kantoraketti.
- - **Lähtöpoltto kiertoradalta**: kun laukaisuikkuna on auki, lentäjä kytkee lähtöpolton päälle. Alus kääntyy nokka menosuuntaan ja jatkaa kiertorataa, ja moottori syttyy itsestään kohdassa, josta poistumishyperbelin asymptootti osoittaa lähtösuuntaan (enintään yhden kierroksen päässä; siirtorata ratkaistaan uudelleen sille hetkelle). Venyneellä radalla poltto tehdään seuraavassa perikeskuksessa. Kuuhun ja kuusta poltto tehdään samoin siinä pysäköintiradan kohdassa, josta siirtorata alkaa.
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
scripts/faults.gd                   # Godot: aluksen viat ja minipelien pulmat
scripts/ui/, ui/                    # Godot: käyttöliittymä, lentokartta ja teema
scripts/cockpit/, shaders/          # Godot: 3D-ohjaamo, avaruus ja varjostimet
assets/textures/                    # Godot: pintakartat ja Linnunrata (WebP, viedään sellaisinaan)
assets/data/, assets/fonts/         # Godot: tietokortit (planet_info.json) ja DejaVu Sans -kirjasin
scripts/orbit/                      # Godot: ratamekaniikka (Kepler, Lambert, ikkunahaku, linkoukset, kuut)
tests/, tools/                      # Godot: ikkunattomat testit, vertailuarvot ja run_tests.sh
```

## Tekstuurien lähteet

Aloitusvalikon taustakuva `assets/menu/taustakuva.webp` (3840 × 2224, pienennetty alkuperäisestä 14575 × 8441) on James Webb -avaruusteleskoopin kuva Kosmiset kalliot Carinan sumussa ([ESA/Webb weic2205a](https://esawebb.org/images/weic2205a/)): NASA, ESA, CSA, STScI, [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/).

Ohjaamon kuva `assets/cockpit/ohjaamo.png` (1382 × 777) on pelin tekijän antama kuva; sen ikkuna-alue on tehty läpinäkyväksi. Ohjaamon panoraama on pelin tekijän tekemä (Gemini, 1456 × 720), ja se on suurennettu nelinkertaiseksi Real-ESRGANilla (malli realesrgan-x4plus, reunat kierrettyinä, jotta sauma pysyy jatkuvana).

Ohjaamon pintakartat ovat hakemistossa `assets/textures/` (tasavälinen lieriöprojektio, WebP, yhteensä noin 70 Mt, sekä 16k-JPEG:t). Jokaisesta kohteesta on peruskartta (enintään 2048 × 1024). Lisäksi on tarkat kartat, jotka haetaan vasta, kun kohde täyttää suuren osan ikkunasta: 16k Maasta, Kuusta ja Marsista (JPEG, tuodaan pakattuna), 8k (8192 × 4096) ja 4k Merkuriuksesta, Maasta, Marsista, Kuusta, Iosta, Europasta, Ganymedeestä ja Enceladuksesta sekä 4k Venuksesta, Jupiterista, Saturnuksesta, Phoboksesta ja Tritonista (näistä ei ole tarkempaa lähdettä tai lähteen tarkkuus ei riitä 8k:hon). 8k-karttaa käytetään vain tietokoneella; kosketusnäyttölaitteet ja heikommat näytönohjaimet saavat 4k-kartan.

| Kohde | Lähde | Lisenssi |
| --- | --- | --- |
| Merkurius, Venus (pilvikerros), Maa, Jupiter, Saturnus ja renkaat, Uranus, Neptunus | [Solar System Scope](https://www.solarsystemscope.com/textures/), NASAn aineistoon perustuvat kartat. Maan karttaan on yhdistetty saman lähteen pilvikartta. | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Phobos | Viking-luotainten mosaiikki, NASA/JPL/USGS ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Phobos_Viking_Mosaic_DLRcontrol_7200.jpg)); sävytetty ruskeanharmaaksi | public domain |
| Io | Galileo- ja Voyager-luotainten värimosaiikki (Io GalileoSSI-Voyager Global Mosaic ClrMerge 1km), [USGS Astrogeology](https://astrogeology.usgs.gov/search/map/io_galileo_ssi_voyager_color_merged_global_mosaic_1km) | public domain |
| Europa | Seek9750: Moon Europa color map ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Moon_Europa_color_map.jpg)), NASAn kuvista | CC0 |
| Ganymedes | Björn Jónsson: Map of Ganymede, NASAn kuvista ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Map_of_Ganymede_by_Bj%C3%B6rn_J%C3%B3nsson.jpg)). Tarkoissa kartoissa värit ovat tästä kartasta ja hienot yksityiskohdat USGS:n Voyager- ja Galileo-mosaiikin kirkkaudesta ([USGS Astrogeology](https://astrogeology.usgs.gov/search/map/ganymede_voyager_galileo_ssi_global_color_mosaic_1435m)) | vapaa käyttö, tekijä mainittava; USGS public domain |
| Enceladus | Cassini-luotaimen värikartta PIA18435, NASA/JPL-Caltech/SSI/LPI ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Enceladus_Color_Map.jpg)) | public domain |
| Kuu (`assets/textures/kuu*`, värikartta) | NASA Scientific Visualization Studio: [CGI Moon Kit](https://svs.gsfc.nasa.gov/4720/), Lunar Reconnaissance Orbiterin laajakulmakameran (LROC WAC) värimosaiikki napoineen (16 384 × 8 192 px); 16k-JPEG ja 8k/4k/2k-WebP (`tools/make_moon_textures.py`) | public domain (NASA) |
| Kuun kohokuvio (`assets/textures/kuu-pinta*`) | NASA SVS: [CGI Moon Kit](https://svs.gsfc.nasa.gov/4720/), LRO:n laserkorkeusmittarin (LOLA) korkeusmalli 64 px/aste; pinnan normaalit ja paikallinen korkeus (`tools/make_moon_textures.py`) | public domain (NASA) |
| Mars (`assets/textures/mars*`, värikartta) | USGS Astrogeology: [Mars Viking Global Color Mosaic](https://astrogeology.usgs.gov/search/map/mars_viking_global_color_mosaic_925m) (925 m/px); kirkkauden mukainen värikorjaus, 16k-JPEG ja 8k/4k/2k-WebP (`tools/make_mars_textures.py`) | public domain (NASA/USGS) |
| Marsin kohokuvio (`assets/textures/mars-pinta*`) | USGS Astrogeology: [Mars MGS MOLA DEM](https://astrogeology.usgs.gov/search/map/mars_mgs_mola_dem_463m) (463 m/px); pinnan normaalit ja paikallinen korkeus (`tools/make_mars_textures.py`) | public domain (NASA/USGS) |
| Maan päiväkartta ilman pilviä (`assets/textures/maa-paiva*`) ja merimaski (`maa-meri.webp`, päiväkartan väreistä) | NASA Earth Observatory: [Blue Marble Next Generation](https://science.nasa.gov/earth/earth-observatory/blue-marble-next-generation/), marraskuu 2004, maaston varjostuksella (21 600 × 10 800 px); pienennetty 16k-JPEG:ksi ja 8k/4k/2k-WebP:ksi (`tools/make_earth_textures.py`) | public domain (NASA) |
| Maan yövalot (`assets/textures/maa-yo*`) | NASA Earth Observatory: [Black Marble 2016](https://science.nasa.gov/earth/earth-observatory/earth-at-night/maps/) (13 500 × 6 750 px); pelkät valot erotettu taustasta (`tools/make_earth_textures.py`) | public domain (NASA) |
| Maan pilvikerros (`assets/textures/maa-pilvet*`) | [Solar System Scope](https://www.solarsystemscope.com/textures/) Wikimedia Commonsin kautta: 8k earth clouds; harmaasävyinen WebP (8k `tools/make_earth_textures.py`, 4k ja 2k `tools/make_textures.gd`) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) |
| Linnunrata (Godot-versio, `assets/textures/linnunrata-4k.webp`) | NASA/Goddard Space Flight Center Scientific Visualization Studio: [Deep Star Maps 2020](https://svs.gsfc.nasa.gov/4851/), Milkyway 2020 (Wikimedia Commonsin 3840 px versio), muunnettu WebP:ksi | public domain (NASA) |
| Kirjasin (Godot-versio) | [DejaVu Sans](https://dejavu-fonts.github.io/) (`assets/fonts/`) | Bitstream Vera -lisenssi, ks. `assets/fonts/LICENSE-DejaVu.txt` |
| Triton | Voyager 2:n värikartta PIA18668, NASA/JPL-Caltech/LPI ([Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Triton_Map.jpg)). Voyager kuvasi vain osan pinnasta: kuvaamaton pohjoinen alue on täytetty ympäristön sumennetulla värillä, ja tehostettuja värejä on haalistettu. | public domain |

## Julkaisu

GitHub-julkaisu (`gh release create vX.Y.Z`) käynnistää `release.yml`:n, joka vie Windows- ja Linux-versiot ja
liittää ne julkaisuun (Sisunautti-windows.zip, Sisunautti-linux.zip) sekä käynnistää `main`-haarasta `pages.yml`:n,
joka vie selainversion (Compatibility, `web_nothreads`-pohja) GitHub Pagesiin. Pagesiin kopioidaan myös `tools/web/sw.js`,
joka korvaa vanhan selainversion service workerin ja poistaa sen. `ci.yml` ajaa ikkunattomat testit jokaisesta
pushista.
