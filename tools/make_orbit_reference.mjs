// Vanha selainversio (web/) poistettiin versiossa 1.0.0. Sen saa takaisin työkopioksi esim.
// git worktree add ../sisunautti-web 5a2375b, ja skriptiä ajetaan siellä (cd web && npm ci).
// Tuottaa vertailuarvot Godot-version ratamekaniikan testeille (tests/orbit_test.gd) selainversion
// ratamekaniikasta (web/js/flight.js, web/js/planets.js) ja astronomy-enginestä.
// Käyttö: (cd web && npm ci) && node tools/make_orbit_reference.mjs  → tests/data/orbit_reference.json
import { writeFileSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const P = await import(join(root, "web/js/planets.js"));
const F = await import(join(root, "web/js/flight.js"));
const Astronomy = createRequire(join(root, "web/package.json"))("astronomy-engine");
const DAY = 86400000, AU = P.AU_KM;
const BODIES = { Merkurius: "Mercury", Venus: "Venus", Maa: "EMB", Mars: "Mars", Jupiter: "Jupiter", Saturnus: "Saturn", Uranus: "Uranus", Neptunus: "Neptune" };
const toEcl = Astronomy.Rotation_EQJ_ECL();
// JSON ei tunne äärettömiä: ne kirjoitetaan merkkijonoina.
const clean = (x) => JSON.parse(JSON.stringify(x, (k, v) => (typeof v === "number" && !Number.isFinite(v) ? String(v) : v)));

const out = { astronomy: [], planets: [], kepler: [], propagate: [], lambert: [], transfer: [], assist: [], searches: [], launch: [], parking: [], local: [], course: [], view: [] };

// astronomy-enginen sijainnit (AU, ekliptika J2000) ja nopeudet (AU/vrk)
for (const iso of ["1850-01-01T00:00:00Z", "1990-03-01T00:00:00Z", "2026-11-13T12:00:00Z", "2026-11-14T00:00:00Z", "2040-07-15T00:00:00Z", "2075-06-01T00:00:00Z", "2150-01-01T00:00:00Z"]) {
  const time = Date.parse(iso);
  for (const name of Object.keys(BODIES)) {
    const s = Astronomy.HelioState(Astronomy.Body[BODIES[name]], new Date(time));
    const p = Astronomy.RotateVector(toEcl, new Astronomy.Vector(s.x, s.y, s.z, s.t));
    const v = Astronomy.RotateVector(toEcl, new Astronomy.Vector(s.vx, s.vy, s.vz, s.t));
    out.astronomy.push({ name, time, pos: [p.x, p.y, p.z], vel: [v.x, v.y, v.z] });
    out.planets.push({ name, time, elements: P.elements(name, time), state: P.helioState(name, time), helio: P.helio(name, time) });
  }
}
for (const e of [0, 0.2, 0.9]) for (const M of [0.1, 1, 3, 5, -2]) out.kepler.push({ M, e, E: P.eccentricAnomaly(M, e) });

const r0 = [AU, 0, 0];
for (const [v0, dt, mu] of [
  [[0, 30, 1], 200 * 86400], [[5, 38, 2], 3 * 365 * 86400], [[0, 38, 0], 40 * 365 * 86400],
  [[10, 45, 3], 5 * 365 * 86400], [[0, 30, 0], -150 * 86400], [[0, 42.1, 0], 2 * 365 * 86400],
  [[1, 7.9, 0.5], 5000, 398600.44],
]) out.propagate.push({ r0: mu ? [6571, 0, 0] : r0, v0, dt, mu: mu ?? F.MU_SUN, result: F.propagate(mu ? [6571, 0, 0] : r0, v0, dt, mu ?? F.MU_SUN) });

for (const [r2, days] of [
  [[0, 1.5 * AU, 0.05 * AU], 150], [[-1.2 * AU, 0.3 * AU, 0], 300], [[0.2 * AU, -1.4 * AU, 0], 400],
  [[0.5 * AU, 0.5 * AU, 0], 20], [[-5 * AU, 1 * AU, 0.1 * AU], 1000], [[2 * AU, 0, 0], 100],
]) out.lambert.push({ r1: r0, r2, tof: days * 86400, result: F.lambert(r0, r2, days * 86400) });

const start = Date.parse("2026-11-14T00:00:00Z");
for (const [from, to, d, tof, ship] of [["Maa", "Mars", start + 40 * DAY, 210], ["Maa", "Jupiter", start + 100 * DAY, 900], ["Maa", "Venus", start, 120, "ioni"], ["Mars", "Maa", start, 250, "ydin"]])
  out.transfer.push({ from, to, depart: d, tof, ship: ship ?? "kemiallinen", result: F.transfer(from, to, d, tof, ship) });
out.assist.push({ from: "Maa", via: "Venus", to: "Merkurius", depart: start + 200 * DAY, tof1: 140, tof2: 110, result: F.assistTransfer("Maa", "Venus", "Merkurius", start + 200 * DAY, 140, 110) });
out.flyby = [
  { via: "Jupiter", vin: [10, 0, 0], vout: [10 * Math.cos(0.5), 10 * Math.sin(0.5), 0] },
  { via: "Mars", vin: [5, 0, 0], vout: [-5, 0, 0] },
  { via: "Jupiter", vin: [10, 0, 0], vout: [11, 0.1, 0] },
].map((c) => ({ ...c, result: F.flybyDv(c.via, c.vin, c.vout) }));

// Haut: edistymisrivit ja vaihtoehdot
const search = (from, to, at, opts = {}) => {
  const it = F.windowSearch(from, to, at, opts), progress = [];
  let r;
  while (!(r = it.next()).done) progress.push(r.value);
  return { from, to, start: at, opts, progress, result: r.value };
};
const [mars] = F.findWindows("Maa", "Mars", start);
const end = F.shipState(mars, mars.arrive);
const drift = { r: end.r, v: end.v, t: mars.arrive };
out.searches.push(search("Maa", "Mars", start));
out.searches.push(search("Maa", "Merkurius", start));
out.searches.push(search("Maa", "Mars", start, { ship: "ioni", fuel: F.SHIPS.ioni.fuel }));
out.searches.push(search("Maa", "Jupiter", start, { fuel: 5 }));
out.searches.push(search("Maa", "Neptunus", start));
out.searches.push(search(drift, "Jupiter", mars.arrive, { fuel: 20 }));
out.searches.push(search("Maa", "Mars", Date.parse("2026-01-01T00:00:00Z"), { days: 365, assists: false }));

const liftoff = Date.parse("2027-01-01T10:00:00Z");
for (const tau of [-20, -5, -1, 0, 2, 30, 70, 100, 152, 159, 300, 509, 510, 600]) {
  const s = F.launchState(liftoff, liftoff + tau * 1000);
  out.launch.push({ liftoff, time: liftoff + tau * 1000, result: s });
}
out.launch.push({ liftoff: null, time: liftoff, result: F.launchState(null, liftoff) });
out.launchOrbit = { liftoff, result: F.launchOrbit(liftoff) };

const orbit = F.launchOrbit(liftoff);
for (const [body, t, o] of [["Maa", start, null], ["Maa", liftoff + 3600000, orbit], ["Mars", start, { epoch: start - 5000000, arg: 2.2 }], ["Jupiter", start, { epoch: liftoff, arg: 1 }], ["Kuu", start, null], ["Titan", start, { epoch: start, arg: -1 }]])
  out.parking.push({ body, time: t, orbit: o, result: F.parkingState(body, t, o), period: F.orbitPeriod(body) });
const now = liftoff + 570000, trInj = F.transfer("Maa", "Mars", now, 259), vinf = trInj.v1.map((x, i) => x - F.planetState("Maa", now).v[i]);
out.injection = [
  { body: "Maa", vinf, after: now, orbit, result: F.injectionTime("Maa", vinf, now, orbit) },
  { body: "Jupiter", vinf: [3, 4, 0], after: liftoff + 0.3 * F.orbitPeriod("Jupiter") * 1000, orbit: { epoch: liftoff, arg: 1 }, result: F.injectionTime("Jupiter", [3, 4, 0], liftoff + 0.3 * F.orbitPeriod("Jupiter") * 1000, { epoch: liftoff, arg: 1 }) },
];
out.orbitAt = { body: "Mars", r: [1e8, 2e8, 1e5], time: start, result: F.orbitAt("Mars", [1e8, 2e8, 1e5], start) };
out.aero = ["Jupiter", "Saturnus", "Uranus", "Neptunus"].map((b) => ({ body: b, dv: F.aerobrakeDv(b), high: F.burnDv(b, 5.5) }));
out.soi = Object.fromEntries(Object.entries(F.FLIGHT_BODIES).map(([k, b]) => [k, b.soiKm]));

for (const [from, to] of [["Maa", "Kuu"], ["Kuu", "Maa"], ["Jupiter", "Europa"], ["Neptunus", "Triton"], ["Mars", "Phobos"]]) {
  const tr = F.localTransfer(from, to, start);
  out.local.push({ from, to, depart: start, result: tr, mid: F.shipState(tr, (tr.depart + tr.arrive) / 2), view: F.shipView(tr, tr.arrive) });
}

const mid = mars.depart + 60 * DAY;
const burned = F.applyBurn(mars, mid, "prograde", 0.5);
const fix = F.autoCorrect(burned, mid + 5 * DAY);
out.course.push({ flight: mars, mid, predict: F.predict(mars, mid), burned, fix,
  vectors: F.BURN_DIRECTIONS.map((d) => F.burnVector(F.shipState(mars, mid), d, 0.7)),
  soiEntry: F.soiEntry(mars), soiExit: F.soiExit(mars), stats: F.flightStats(mars), statsBurned: F.flightStats(burned, 500),
  encounter: F.encounter(mars, mid, mars.arrive + 30 * DAY), nearest: F.nearestPlanet(F.shipState(mars, mid).r, F.shipState(mars, mid).v, mid) });
for (const t of [mars.depart - 30 * DAY, mars.depart, mars.depart + 2 * DAY, (mars.depart + mars.arrive) / 2, mars.arrive - DAY, mars.arrive])
  out.view.push({ time: t, flight: "mars", result: F.shipView(mars, t) });
const merc = out.searches[1].result.find((o) => o.kind === "assist");
if (merc) for (const t of [merc.flyby.t - DAY, merc.flyby.t, merc.arrive]) out.view.push({ time: t, flight: "merkurius", result: F.shipView(merc, t) });
out.view.push({ time: burned.depart + 70 * DAY, flight: "burned", result: F.shipView(burned, burned.depart + 70 * DAY) });
out.fmt = [[123 * DAY + 4 * 3600000 + 12 * 60000 + 33500, F.fmtDuration(123 * DAY + 4 * 3600000 + 12 * 60000 + 33500)], [-5, F.fmtDuration(-5)], [9.9e11, F.fmtDuration(9.9e11)]];

writeFileSync(join(root, "tests/data/orbit_reference.json"), JSON.stringify(clean(out)));
console.log("tests/data/orbit_reference.json:", Object.entries(out).map(([k, v]) => `${k} ${Array.isArray(v) ? v.length : 1}`).join(", "));
