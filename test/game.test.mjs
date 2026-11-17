import { execFileSync } from "node:child_process";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

import { describe, expect, it } from "vitest";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
// Julkaistava sivusto: nämä tiedostot ja hakemistot kopioidaan GitHub Pagesiin (.github/workflows/pages.yml).
const SITE = ["index.html", "styles.css", "manifest.webmanifest", "sw.js", "js", "icons", "textures"];
const walk = (path) =>
  statSync(join(root, path)).isDirectory() ? readdirSync(join(root, path)).flatMap((name) => walk(join(path, name))) : [path.replaceAll("\\", "/")];
const files = SITE.flatMap(walk);
const read = (file) => readFileSync(join(root, file), "utf8");

describe("sivusto", () => {
  it("service worker tallettaa kaikki pelin tiedostot", () => {
    const list = read("sw.js").match(/const SHELL = \[([\s\S]*?)\];/)[1];
    const shell = [...list.matchAll(/"([^"]+)"/g)].map((m) => (m[1] === "./" ? "index.html" : m[1]));
    // Valokuvatekstuurit talletetaan vasta käytettäessä, jotta asennus pysyy kevyenä.
    expect(shell.sort()).toEqual(files.filter((f) => f !== "sw.js" && !f.startsWith("textures/")).sort());
  });

  it("JavaScript-tiedostot ovat syntaksiltaan kelvollisia", () => {
    for (const file of files.filter((f) => f.endsWith(".js"))) {
      // Moduulina: tavallinen --check jäsentää .js-tiedoston ensin CommonJS:nä eikä huomaa kaikkia virheitä funktioiden sisällä.
      expect(() => execFileSync(process.execPath, ["--input-type=module", "--check"], { input: read(file), stdio: "pipe" }), file).not.toThrow();
    }
  });

  it("moduulien tuonnit osoittavat olemassa oleviin tiedostoihin", () => {
    for (const file of files.filter((f) => f.startsWith("js/"))) {
      for (const [, spec] of read(file).matchAll(/from '(\.\/[^']+)'/g)) {
        expect(files, `${file} tuo ${spec}`).toContain(join("js", spec).replaceAll("\\", "/"));
      }
    }
  });

  it("index.html ja manifesti viittaavat olemassa oleviin tiedostoihin", () => {
    const refs = [...read("index.html").matchAll(/(?:src|href)="([^"#:]+)"/g)].map((m) => m[1]);
    const icons = JSON.parse(read("manifest.webmanifest")).icons.map((icon) => icon.src);
    expect(refs).toContain("js/main.js");
    for (const ref of [...refs, ...icons]) expect(files, ref).toContain(ref);
  });
});

describe("aurinkokunnan kartta", async () => {
  const { helio, eccentricAnomaly, PLANETS } = await import("../js/planets.js");
  const Astronomy = await import("astronomy-engine");
  const BODIES = { Merkurius: "Mercury", Venus: "Venus", Maa: "EMB", Mars: "Mars", Jupiter: "Jupiter", Saturnus: "Saturn", Uranus: "Uranus", Neptunus: "Neptune" };

  it("ratkaisee Keplerin yhtälön", () => {
    for (const e of [0, 0.2, 0.9]) {
      for (const M of [0.1, 1, 3, 5]) {
        const E = eccentricAnomaly(M, e);
        expect(Math.atan2(Math.sin(E - e * Math.sin(E) - M), Math.cos(E - e * Math.sin(E) - M))).toBeCloseTo(0, 10);
      }
    }
  });

  it("planeettojen sijainnit vastaavat astronomy-enginen laskemia", () => {
    const toEcliptic = Astronomy.Rotation_EQJ_ECL();
    for (const iso of ["1990-03-01T00:00:00Z", "2026-11-13T12:00:00Z", "2040-07-15T00:00:00Z"]) {
      const time = Date.parse(iso);
      for (const { name } of PLANETS) {
        const v = Astronomy.RotateVector(toEcliptic, Astronomy.HelioVector(Astronomy.Body[BODIES[name]], new Date(time)));
        const [x, y, z] = helio(name, time), r = Math.hypot(v.x, v.y, v.z);
        // Rata-alkioiden tarkkuus: Jupiterin ja Saturnuksen keskinäiset häiriöt jättävät muutaman kaariminuutin eron.
        const arcmin = (Math.hypot(x - v.x, y - v.y, z - v.z) / r) * (180 / Math.PI) * 60;
        expect(arcmin, `${name} ${iso}`).toBeLessThan(15);
      }
    }
  });
});

describe("ratamekaniikka", async () => {
  const { helio, helioState, PLANETS, AU_KM } = await import("../js/planets.js");
  const F = await import("../js/flight.js");
  const Astronomy = await import("astronomy-engine");
  const BODIES = { Merkurius: "Mercury", Venus: "Venus", Maa: "EMB", Mars: "Mars", Jupiter: "Jupiter", Saturnus: "Saturn", Uranus: "Uranus", Neptunus: "Neptune" };
  const toEcliptic = Astronomy.Rotation_EQJ_ECL();
  const close = (a, b, tol) => F.norm([a[0] - b[0], a[1] - b[1], a[2] - b[2]]) / F.norm(b) < tol;

  it("Standishin pitkän aikavälin alkiot pitävät sijainnit tarkkoina vuosisadan päähän", () => {
    for (const iso of ["1850-01-01T00:00:00Z", "2026-11-14T00:00:00Z", "2075-06-01T00:00:00Z", "2150-01-01T00:00:00Z"]) {
      const time = Date.parse(iso);
      for (const { name } of PLANETS) {
        const v = Astronomy.RotateVector(toEcliptic, Astronomy.HelioVector(Astronomy.Body[BODIES[name]], new Date(time)));
        const [x, y, z] = helio(name, time);
        const arcmin = (Math.hypot(x - v.x, y - v.y, z - v.z) / Math.hypot(v.x, v.y, v.z)) * (180 / Math.PI) * 60;
        expect(arcmin, `${name} ${iso}`).toBeLessThan(15);
      }
    }
  });

  it("planeettojen nopeusvektorit vastaavat astronomy-enginen laskemia", () => {
    const time = Date.parse("2026-11-14T00:00:00Z");
    for (const { name } of PLANETS) {
      const s = Astronomy.HelioState(Astronomy.Body[BODIES[name]], new Date(time));
      const v = Astronomy.RotateVector(toEcliptic, new Astronomy.Vector(s.vx, s.vy, s.vz, s.t));
      expect(close(helioState(name, time).vel, [v.x, v.y, v.z], 0.01), name).toBe(true);
    }
    // Maan ratanopeus on noin 29,8 km/s.
    expect(F.norm(F.planetState("Maa", time).v)).toBeCloseTo(29.8, 0);
  });

  it("radan eteneminen säilyttää energian ja liikemäärämomentin", () => {
    const r0 = [AU_KM, 0, 0];
    for (const [v0, dt] of [
      [[0, 30, 1], 200 * 86400], // lähes ympyrärata
      [[5, 38, 2], 3 * 365 * 86400], // venynyt ellipsi
      [[0, 38, 0], 40 * 365 * 86400], // monta kierrosta
      [[10, 45, 3], 5 * 365 * 86400], // hyperbeli
      [[0, 30, 0], -150 * 86400], // taaksepäin
    ]) {
      const a = F.invariants(r0, v0), { r, v } = F.propagate(r0, v0, dt), b = F.invariants(r, v);
      expect(Math.abs(b.energy / a.energy - 1), `${v0} ${dt}`).toBeLessThan(1e-9);
      expect(close(b.h, a.h, 1e-9), `${v0} ${dt}`).toBe(true);
      // Eteneminen takaisin palauttaa alkutilan.
      expect(close(F.propagate(r, v, -dt).r, r0, 1e-8), `${v0} ${dt}`).toBe(true);
    }
    // Ympyrärata palaa kierroksen jälkeen alkuun.
    const vc = Math.sqrt(F.MU_SUN / AU_KM), period = 2 * Math.PI * Math.sqrt(AU_KM ** 3 / F.MU_SUN);
    expect(close(F.propagate(r0, [0, vc, 0], period / 4).r, [0, AU_KM, 0], 1e-9)).toBe(true);
  });

  it("Lambertin ratkaisu toistaa annetun loppupisteen", () => {
    const r1 = [AU_KM, 0, 0];
    for (const [r2, days] of [
      [[0, 1.5 * AU_KM, 0.05 * AU_KM], 150],
      [[-1.2 * AU_KM, 0.3 * AU_KM, 0], 300],
      [[0.2 * AU_KM, -1.4 * AU_KM, 0], 400], // pitkä kaari
      [[0.5 * AU_KM, 0.5 * AU_KM, 0], 20], // hyperbolinen pikalento
      [[-5 * AU_KM, 1 * AU_KM, 0.1 * AU_KM], 1000],
    ]) {
      const sol = F.lambert(r1, r2, days * 86400);
      expect(sol, `${r2}`).not.toBeNull();
      const end = F.propagate(r1, sol.v1, days * 86400);
      expect(close(end.r, r2, 1e-7), `${r2} ${days}`).toBe(true);
      expect(close(end.v, sol.v2, 1e-7), `${r2} ${days}`).toBe(true);
      // Rata kulkee planeettojen suuntaan.
      expect(F.cross(r1, sol.v1)[2]).toBeGreaterThan(0);
    }
  });

  it("Maa→Mars Hohmann kestää noin 259 vrk ja lähtö LEO:sta vaatii noin 3,6 km/s", () => {
    const h = F.hohmann(AU_KM, 1.524 * AU_KM);
    expect(h.tof / 86400).toBeCloseTo(259, 0);
    expect(F.burnDv("Maa", h.vinfDep)).toBeCloseTo(3.6, 1);
    // Lähes 180° siirto Lambertilla vastaa Hohmannia.
    const sol = F.lambert([AU_KM, 0, 0], [-1.524 * AU_KM, 1e-3 * AU_KM, 0], h.tof);
    expect(F.norm(sol.v1) - Math.sqrt(F.MU_SUN / AU_KM)).toBeCloseTo(h.vinfDep, 2);
  });

  it("löytää vuoden 2026 Mars-ikkunan oikeilla planeettojen paikoilla", () => {
    let best = null;
    for (let d = Date.parse("2026-09-01T00:00:00Z"); d < Date.parse("2027-03-01T00:00:00Z"); d += 5 * 86400000) {
      for (let tof = 150; tof <= 400; tof += 10) {
        const tr = F.transfer("Maa", "Mars", d, tof);
        if (tr && (!best || tr.dvDep < best.dvDep)) best = tr;
      }
    }
    // Halvin lähtö on vuodenvaihteen tienoilla, ja Δv LEO:sta on Hohmannin luokkaa.
    expect(best.dvDep).toBeGreaterThan(3.4);
    expect(best.dvDep).toBeLessThan(4);
    expect(best.depart).toBeGreaterThan(Date.parse("2026-10-01T00:00:00Z"));
    expect(best.depart).toBeLessThan(Date.parse("2027-02-01T00:00:00Z"));
    // Alus saapuu Marsin luo siirtoradan päässä.
    const end = F.shipState(best, best.arrive);
    expect(F.norm([end.r[0] - best.r2[0], end.r[1] - best.r2[1], end.r[2] - best.r2[2]])).toBeLessThan(1000);
  });

  it("vaikutuspiirien säteet ovat oikeaa suuruusluokkaa", () => {
    expect(F.FLIGHT_BODIES.Maa.soiKm / 1e6).toBeCloseTo(0.925, 1);
    expect(F.FLIGHT_BODIES.Jupiter.soiKm / 1e6).toBeCloseTo(48.2, 0);
    expect(F.FLIGHT_BODIES.Mars.soiKm / 1e6).toBeCloseTo(0.577, 1);
  });
});

describe("laukaisuikkunat", async () => {
  const F = await import("../js/flight.js");
  const start = Date.parse("2026-11-14T00:00:00Z"), DAY = 86400000;

  it("löytää Maa→Mars-lennolle halvimman ja nopeamman vaihtoehdon", () => {
    const it = F.windowSearch("Maa", "Mars", start);
    let r, last = -1;
    while (!(r = it.next()).done) {
      expect(r.value).toBeGreaterThan(last);
      last = r.value;
    }
    expect(last).toBe(1);
    const [cheapest, faster] = r.value;
    expect(cheapest.kind).toBe("cheapest");
    expect(cheapest.dvTotal).toBeLessThan(6.5);
    expect(cheapest.fuelOk).toBe(true);
    expect(faster.kind).toBe("faster");
    expect(faster.arrive - faster.depart).toBeLessThanOrEqual(0.7 * (cheapest.arrive - cheapest.depart) + DAY);
    expect(faster.dvTotal).toBeGreaterThan(cheapest.dvTotal);
    for (const o of r.value) {
      expect(o.depart).toBeGreaterThanOrEqual(start);
      expect(o.depart).toBeLessThanOrEqual(start + 731 * DAY);
    }
  });

  it("pitää ulkoplaneettojen lentoajan kohtuullisena ja kertoo, riittääkö polttoaine", () => {
    const [cheapest] = F.findWindows("Maa", "Neptunus", start);
    expect((cheapest.arrive - cheapest.depart) / DAY / 365.25).toBeLessThan(36);
    expect(cheapest.fuelOk).toBe(true);
    const poor = F.findWindows("Maa", "Jupiter", start, { fuel: 5 });
    expect(poor.every((o) => !o.fuelOk)).toBe(true);
  });

  it("muotoilee lentoajan kelloksi", () => {
    expect(F.fmtDuration(123 * DAY + 4 * 3600000 + 12 * 60000 + 33500)).toBe("123 vrk 04:12:33");
    expect(F.fmtDuration(-5)).toBe("0 vrk 00:00:00");
  });
});

describe("ohjaamonäkymä", async () => {
  const F = await import("../js/flight.js");
    const start = Date.parse("2026-11-14T00:00:00Z"), DAY = 86400000;
  const [tr] = F.findWindows("Maa", "Mars", start);
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];


  it("alus ei ole planeetan sisällä lähtiessä eikä saapuessa", () => {
    const dep = F.norm(sub(F.shipView(tr, tr.depart).r, F.planetState("Maa", tr.depart).r));
    const arr = F.norm(sub(F.shipView(tr, tr.arrive).r, F.planetState("Mars", tr.arrive).r));
    expect(dep).toBeGreaterThan(F.FLIGHT_BODIES.Maa.periKm);
    expect(dep).toBeLessThan(50000);
    expect(arr).toBeGreaterThan(F.FLIGHT_BODIES.Mars.periKm);
    // Ennen laukaisua alus kulkee Maan mukana.
    const before = F.shipView(tr, tr.depart - 30 * DAY);
    expect(F.norm(sub(before.r, F.planetState("Maa", tr.depart - 30 * DAY).r))).toBeCloseTo(dep, 0);
    // Keskellä lentoa näkymä on siirtorata.
    const mid = (tr.depart + tr.arrive) / 2;
    expect(F.norm(sub(F.shipView(tr, mid).r, F.shipState(tr, mid).r))).toBe(0);
  });

  it("vaikutuspiiristä poistutaan muutamassa vuorokaudessa", () => {
    const days = (F.soiExit(tr) - tr.depart) / DAY;
    expect(days).toBeGreaterThan(1);
    expect(days).toBeLessThan(10);
    expect(F.soiEntry(tr)).toBeGreaterThan(F.soiExit(tr));
  });
});

describe("saapuminen ja jatkolennot", async () => {
  const F = await import("../js/flight.js");
  const { PLANET_INFO } = await import("../js/planetinfo.js");
  const { PLANETS } = await import("../js/planets.js");
  const start = Date.parse("2026-11-14T00:00:00Z");
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];

  it("pysäköintirata kiertää planeettaa oikealla korkeudella ja nopeudella", () => {
    const s = F.parkingState("Maa", start), p = F.planetState("Maa", start);
    const r = F.norm(sub(s.r, p.r));
    expect(r).toBeGreaterThanOrEqual(F.FLIGHT_BODIES.Maa.periKm - 1);
    expect(r).toBeLessThanOrEqual(F.FLIGHT_BODIES.Maa.apoKm + 1);
    // Matalan Maan kiertoradan nopeus on noin 7,8 km/s.
    expect(F.norm(s.rel.v)).toBeCloseTo(7.79, 1);
  });

  it("lentää Auringon kiertoradalta (ohilennon jälkeen) uuteen kohteeseen", () => {
    const [tr] = F.findWindows("Maa", "Mars", start);
    const s = F.shipState(tr, tr.arrive);
    const drift = { r: s.r, v: s.v, t: tr.arrive };
    expect(F.isPlanet(drift)).toBe(false);
    expect(F.norm(sub(F.departureState(drift, tr.arrive).r, s.r))).toBeLessThan(1e-3);
    const options = F.findWindows(drift, "Jupiter", tr.arrive, { fuel: 20 });
    expect(options.length).toBeGreaterThan(0);
    // Auringon kiertoradalta lähtö on suoraan nopeuksien erotus.
    expect(options[0].dvDep).toBeCloseTo(options[0].vinfDep, 10);
    expect(F.soiExit(options[0])).toBe(options[0].depart);
    expect(F.norm(sub(F.shipView(options[0], options[0].depart - 86400000).r, F.departureState(drift, options[0].depart - 86400000).r))).toBeLessThan(1);
  });

  it("laskee lennon pituuden ja huippunopeuden lokikirjaan", () => {
    const [tr] = F.findWindows("Maa", "Mars", start);
    const { km, maxSpeed } = F.flightStats(tr);
    // Maa→Mars-siirtorata on noin puolikas ellipsi: 400–600 miljoonaa km, nopeus suurin lähdössä.
    expect(km / 1e6).toBeGreaterThan(350);
    expect(km / 1e6).toBeLessThan(650);
    expect(maxSpeed).toBeCloseTo(F.norm(tr.v1), 1);
  });

  it("jokaisella planeetalla on tietokortti", () => {
    for (const { name } of PLANETS) {
      const info = PLANET_INFO[name];
      for (const key of ["diameter", "mass", "gravity", "day", "year", "temperature", "atmosphere", "moons"]) expect(info[key], `${name} ${key}`).toBeTruthy();
      expect(info.facts.length, name).toBeGreaterThanOrEqual(2);
    }
  });
});

describe("kurssikorjaukset", async () => {
  const F = await import("../js/flight.js");
  const start = Date.parse("2026-11-14T00:00:00Z"), DAY = 86400000;
  const [tr] = F.findWindows("Maa", "Mars", start);
  const mid = tr.depart + 60 * DAY;

  it("ennuste vastaa suunniteltua lentoa, kun kurssia ei ole muutettu", () => {
    const p = F.predict(tr, mid);
    expect(p.miss).toBe(false);
    expect(p.missKm).toBeLessThan(1000);
    expect(Math.abs(p.arrive - tr.arrive)).toBeLessThan(DAY / 4);
    expect(p.dvArr).toBeCloseTo(tr.dvArr, 1);
  });

  it("poltto muuttaa rataa heti ja korjaus palauttaa kohteeseen", () => {
    const burned = F.applyBurn(tr, mid, "prograde", 0.5);
    // Polton hetkellä paikka ei muutu, mutta nopeus kasvaa 0,5 km/s.
    const before = F.shipState(tr, mid), after = F.shipState(burned, mid + 1);
    expect(F.norm(after.v) - F.norm(before.v)).toBeCloseTo(0.5, 2);
    expect(burned.miss).toBe(true);
    expect(burned.missKm).toBeGreaterThan(F.FLIGHT_BODIES.Mars.soiKm);
    const fix = F.autoCorrect(burned, mid + 5 * DAY);
    expect(fix.flight.miss).toBe(false);
    expect(fix.dv).toBeGreaterThan(0.1);
    expect(fix.dv).toBeLessThan(2);
    // Ennen poltto-osuutta rata on ennallaan.
    expect(F.norm(F.shipState(fix.flight, mid - DAY).r.map((x, i) => x - F.shipState(tr, mid - DAY).r[i]))).toBeLessThan(1e-3);
  });

  it("polton suunnat ovat kohtisuorassa toisiinsa nähden", () => {
    const s = F.shipState(tr, mid);
    const pro = F.burnVector(s, "prograde", 1), out = F.burnVector(s, "outward", 1);
    expect(F.dot(pro, out)).toBeCloseTo(0, 10);
    expect(F.norm(F.burnVector(s, "inward", 0.3))).toBeCloseTo(0.3, 10);
    expect(F.dot(F.burnVector(s, "retrograde", 1), pro)).toBeCloseTo(-1, 10);
  });
});

describe("linkoukset, kuut ja alukset", async () => {
  const F = await import("../js/flight.js");
  const { PLANET_INFO } = await import("../js/planetinfo.js");
  const start = Date.parse("2026-11-14T00:00:00Z"), DAY = 86400000;
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];

  it("ohilento kääntää ylinopeutta vain fysikaalisesti mahdollisen määrän", () => {
    // Pieni käännös onnistuu ilman polttoa, kun nopeus säilyy.
    const ok = F.flybyDv("Jupiter", [10, 0, 0], [10 * Math.cos(0.5), 10 * Math.sin(0.5), 0]);
    expect(ok.dv).toBeCloseTo(0, 10);
    expect(ok.rp).toBeGreaterThan(F.FLIGHT_BODIES.Jupiter.radiusKm);
    // Täyskäännös vaatisi perikeskuksen planeetan sisällä.
    expect(F.flybyDv("Mars", [5, 0, 0], [-5, 0, 0])).toBeNull();
    // Nopeuden muutos poltetaan perikeskuksessa.
    expect(F.flybyDv("Jupiter", [10, 0, 0], [11, 0.1, 0]).dv).toBeGreaterThan(0);
  });

  it("ehdottaa Merkuriukseen Venus-linkousta, jonka osuudet kohtaavat ja joka on suoraa lentoa halvempi", () => {
    const options = F.findWindows("Maa", "Merkurius", start);
    const tr = options.find((o) => o.kind === "assist");
    expect(tr?.via).toBe("Venus");
    expect(tr.dvTotal).toBeLessThan(options[0].dvTotal);
    expect(tr.dvTotal).toBeCloseTo(tr.dvDep + tr.dvFlyby + tr.dvArr, 10);
    const at = F.shipState(tr, tr.flyby.t), venus = F.planetState("Venus", tr.flyby.t);
    expect(F.norm(sub(at.r, venus.r))).toBeLessThan(10);
    expect(F.norm(sub(F.shipState(tr, tr.arrive).r, F.planetState("Merkurius", tr.arrive).r))).toBeLessThan(10);
    // Ohjaamossa alus ohittaa Venuksen sen ulkopuolelta.
    expect(F.norm(sub(F.shipView(tr, tr.flyby.t).r, venus.r))).toBeGreaterThan(F.FLIGHT_BODIES.Venus.radiusKm);
  }, 20000);

  it("lentää kuuhun emoplaneetan kiertoradalta ja takaisin", () => {
    const go = F.localTransfer("Maa", "Kuu", start);
    // Kuulento: noin 5 vrk, lähtö noin 3,1 km/s ja jarrutus noin 0,8 km/s.
    expect((go.arrive - go.depart) / DAY).toBeCloseTo(5, 0);
    expect(go.dvDep).toBeCloseTo(3.1, 1);
    expect(go.dvArr).toBeCloseTo(0.8, 1);
    expect(F.norm(sub(F.shipState(go, go.arrive).r, F.bodyState("Kuu", go.arrive).r))).toBeLessThan(1);
    const back = F.localTransfer("Kuu", "Maa", start);
    expect(F.norm(sub(F.shipState(back, back.depart).r, F.bodyState("Kuu", back.depart).r))).toBeLessThan(1);
    expect(back.dvTotal).toBeCloseTo(go.dvTotal, 6);
    // Ohjaamossa alus ei ole kuun sisällä.
    expect(F.norm(sub(F.shipView(go, go.arrive).r, F.bodyState("Kuu", go.arrive).r))).toBeGreaterThanOrEqual(F.orbitOf("Kuu").periKm - 1);
    for (const m of Object.keys(F.MOONS)) expect(PLANET_INFO[m]?.facts.length, m).toBeGreaterThanOrEqual(2);
  });

  it("ionialuksen lähtö on spiraali, joka ehtii ennen lähtöhetkeä", () => {
    const options = F.findWindows("Maa", "Mars", start, { ship: "ioni", fuel: F.SHIPS.ioni.fuel });
    expect(options.every((o) => o.kind !== "assist")).toBe(true);
    for (const o of options) {
      expect(o.spiralOut).toBeGreaterThan(30 * DAY);
      expect(o.depart - o.spiralOut).toBeGreaterThanOrEqual(start);
    }
    expect(F.canRefuel("ydin", "Mars")).toBe(false);
    expect(F.canRefuel("ydin", "Jupiter")).toBe(true);
    expect(F.canRefuel("kemiallinen", "Mars")).toBe(true);
  });
});

describe("laukaisu, lähtöpoltto ja saapumisrata (flight.js)", async () => {
  const F = await import("../js/flight.js");
  const liftoff = Date.parse("2027-01-01T10:00:00Z"), seco = liftoff + F.ASCENT_S * 1000;
  const sub = (a, b) => [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
  const angleGap = (a, b) => Math.abs(((a - b + Math.PI) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI) - Math.PI);

  it("alus seisoo alustalla Maan pinnalla ja nokka osoittaa ylös", () => {
    for (const s of [F.launchState(null, liftoff), F.launchState(liftoff, liftoff - 5000)]) {
      expect(s.alt).toBeLessThan(0.1);
      expect(s.speed).toBe(0);
      // Nokka on säteen suuntainen.
      expect(F.dot(s.nose, s.rel.r) / F.norm(s.rel.r)).toBeCloseTo(1, 6);
    }
    expect(F.launchState(null, liftoff).phase).toBe("Laukaisualusta");
    expect(F.launchState(liftoff, liftoff - 5000).phase).toBe("Lähtölaskenta");
    expect(F.launchState(liftoff, liftoff - 1000).shake).toBeGreaterThan(0);
  });

  it("nousu päättyy täsmälleen kiertoradan tilaan", () => {
    const end = F.launchState(liftoff, seco), orbit = F.parkingState("Maa", seco, F.launchOrbit(liftoff));
    expect(end.alt).toBeCloseTo(200, 6);
    expect(end.speed).toBeCloseTo(7.79, 1);
    expect(F.norm(sub(end.r, orbit.r))).toBeLessThan(1e-3);
    expect(F.norm(sub(end.v, orbit.v))).toBeLessThan(1e-6);
    // Lopussa nokka on menosuuntaan ja katto poispäin Maasta.
    expect(F.dot(end.nose, end.rel.v) / F.norm(end.rel.v)).toBeCloseTo(1, 6);
    expect(F.dot(end.up, end.rel.r) / F.norm(end.rel.r)).toBeCloseTo(1, 6);
  });

  it("korkeus ja nopeus kasvavat koko nousun ajan ja vaiheet vaihtuvat oikeilla hetkillä", () => {
    let prev = F.launchState(liftoff, liftoff);
    for (let tau = 5; tau <= F.ASCENT_S; tau += 5) {
      const s = F.launchState(liftoff, liftoff + tau * 1000);
      expect(s.alt).toBeGreaterThan(prev.alt);
      expect(s.speed).toBeGreaterThan(prev.speed);
      prev = s;
    }
    const at = (tau) => F.launchState(liftoff, liftoff + tau * 1000);
    expect(at(2).phase).toBe("Laukaisu");
    expect(at(F.ASCENT_EVENTS.maxQ).phase).toBe("Max Q");
    expect(at(F.ASCENT_EVENTS.meco + 2).phase).toBe("Vaiheen erotus");
    expect(at(F.ASCENT_EVENTS.meco + 2).g).toBe(0);
    expect(at(300).phase).toBe("Vaihe 2");
    // Tärinä on kovimmillaan laukaisussa ja suurimman aerodynaamisen kuorman kohdalla, vaiheessa 2 vähäistä.
    expect(at(2).shake).toBe(1);
    expect(at(F.ASCENT_EVENTS.maxQ).shake).toBeGreaterThan(at(40).shake);
    expect(at(300).shake).toBeLessThan(0.2);
  });

  it("lähtöpoltto ajoittuu kohtaan, josta hyperbelin asymptootti osoittaa lähtösuuntaan", () => {
    const orbit = F.launchOrbit(liftoff), now = seco + 60000;
    const tr = F.transfer("Maa", "Mars", now, 259);
    const vinf = sub(tr.v1, F.planetState("Maa", now).v);
    const t = F.injectionTime("Maa", vinf, now, orbit);
    expect(t).toBeGreaterThanOrEqual(now);
    expect(t - now).toBeLessThanOrEqual(F.orbitPeriod("Maa") * 1000 + 1);
    const { mu, periKm } = F.FLIGHT_BODIES.Maa, e = 1 + periKm * F.dot(vinf, vinf) / mu;
    const rel = F.parkingState("Maa", t, orbit).rel.r;
    expect(angleGap(Math.atan2(rel[1], rel[0]), Math.atan2(vinf[1], vinf[0]) - Math.acos(-1 / e))).toBeLessThan(1e-6);
  });

  it("venyneellä radalla lähtöpoltto tehdään seuraavassa perikeskuksessa", () => {
    const orbit = { epoch: liftoff, arg: 1 }, period = F.orbitPeriod("Jupiter") * 1000;
    const t = F.injectionTime("Jupiter", [3, 4, 0], liftoff + 0.3 * period, orbit);
    expect(t).toBeCloseTo(liftoff + period, -1);
    const rel = F.parkingState("Jupiter", t, orbit).rel.r;
    expect(F.norm(rel)).toBeCloseTo(F.FLIGHT_BODIES.Jupiter.periKm, 0);
  });

  it("jarrutuksen jälkeen alus jatkaa radalla saapumiskohdastaan", () => {
    const t = liftoff, p = F.planetState("Mars", t), dir = [Math.cos(2.2), Math.sin(2.2), 0];
    const r = p.r.map((x, i) => x + dir[i] * F.FLIGHT_BODIES.Mars.periKm);
    const s = F.parkingState("Mars", t, F.orbitAt("Mars", r, t));
    expect(F.norm(sub(s.r, r))).toBeLessThan(1e-3);
  });

  it("ilmajarrutus vie jättiläisplaneetalla matalalle ympyräradalle, jolta lähtö on kallis", () => {
    for (const name of ["Jupiter", "Saturnus", "Uranus", "Neptunus"]) {
      const b = F.FLIGHT_BODIES[name], high = F.burnDv(name, 5.5);
      expect(F.hasLowOrbit(name)).toBe(true);
      // Radan nosto ilmajarrutuksen jälkeen on halpa.
      expect(F.aerobrakeDv(name)).toBeGreaterThan(0.1);
      expect(F.aerobrakeDv(name)).toBeLessThan(1);
      F.setLowOrbit(name, true);
      expect(b.apoKm).toBe(b.periKm);
      expect(b.periKm - b.radiusKm).toBeLessThanOrEqual(5000);
      const low = F.burnDv(name, 5.5);
      // Matalalla radalla kierros kestää tunteja, venyneellä päiviä.
      expect(F.orbitPeriod(name)).toBeLessThan(6 * 3600);
      F.setLowOrbit(name, false);
      expect(low).toBeGreaterThan(high + 5);
      expect(F.burnDv(name, 5.5)).toBeCloseTo(high, 12);
      expect(F.orbitPeriod(name)).toBeGreaterThan(86400);
    }
    // Jupiterin matalalta radalta lähtö ylittää kemiallisen raketin koko budjetin.
    F.setLowOrbit("Jupiter", true);
    expect(F.burnDv("Jupiter", 5.5)).toBeGreaterThan(F.SHIPS.kemiallinen.fuel);
    F.setLowOrbit("Jupiter", false);
    expect(F.hasLowOrbit("Mars")).toBe(false);
    F.setLowOrbit("Mars", true);
    expect(F.FLIGHT_BODIES.Mars.periKm - F.FLIGHT_BODIES.Mars.radiusKm).toBe(500);
  });

  it("saapumisradat ovat matalia ja kemiallinen raketti pääsee niille", () => {
    const alt = (name) => F.FLIGHT_BODIES[name].periKm - F.FLIGHT_BODIES[name].radiusKm;
    for (const name of ["Merkurius", "Venus", "Mars"]) {
      expect(alt(name)).toBe(500);
      expect(F.FLIGHT_BODIES[name].apoKm).toBe(F.FLIGHT_BODIES[name].periKm);
    }
    expect(alt("Maa")).toBe(200);
    for (const name of ["Jupiter", "Saturnus", "Uranus", "Neptunus"]) expect(alt(name)).toBeLessThanOrEqual(5000);
    // Tyypillinen saapuminen Marsiin (v∞ 2,6 km/s) ja Jupiteriin (5,6 km/s) mahtuu selvästi 14 km/s:n budjettiin.
    expect(F.burnDv("Mars", 2.6)).toBeLessThan(2.5);
    expect(F.burnDv("Jupiter", 5.6)).toBeLessThan(2);
  });
});
