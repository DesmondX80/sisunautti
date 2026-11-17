// Service worker: tekee pelistä asennettavan ja pelattavan ilman verkkoa.
// Kaikki haetaan ensin verkosta; välimuistiin turvaudutaan vain, kun verkko ei vastaa.
// Julkaisu korvaa VERSION-arvon commitin tunnisteella, jolloin selain asentaa uuden workerin.
const VERSION = "dev";
const SHELL_CACHE = `shell-${VERSION}`;

// Pelin tiedostot, jotka haetaan talteen heti asennuksessa (testi varmistaa, että lista kattaa kaikki tiedostot).
// Valokuvatekstuurit (textures/, noin 41 Mt) eivät ole listalla: ne talletetaan vasta, kun ohjaamo hakee ne.
const SHELL = [
  "./",
  "styles.css",
  "manifest.webmanifest",
  "js/main.js",
  "js/cabin.js",
  "js/cockpit.js",
  "js/core.js",
  "js/flight.js",
  "js/land.js",
  "js/planetinfo.js",
  "js/planets.js",
  "js/solarsystem.js",
  "js/stars.js",
  "js/textures.js",
  "js/vendor/three-0.170.0.module.min.js",
  "js/voyage.js",
  "icons/icon.svg",
  "icons/icon-180.png",
  "icons/icon-192.png",
  "icons/icon-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches
      .open(SHELL_CACHE)
      // cache: "reload" ohittaa selaimen HTTP-välimuistin, jotta talteen ei jää vanhaa versiota.
      .then((cache) => cache.addAll(SHELL.map((url) => new Request(url, { cache: "reload" }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((names) => Promise.all(names.filter((n) => n.startsWith("shell-") && n !== SHELL_CACHE).map((n) => caches.delete(n))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET" || new URL(request.url).origin !== self.location.origin) return;
  event.respondWith(shellResponse(request));
});

/** Pelin tiedostot: tuore versio verkosta (HTTP-välimuisti tarkistetaan palvelimelta), ilman verkkoa talletettu. */
async function shellResponse(request) {
  const cache = await caches.open(SHELL_CACHE);
  try {
    const response = await fetch(request, { cache: "no-cache" });
    if (response.ok) await cache.put(request, response.clone());
    return response;
  } catch (err) {
    // ignoreSearch: julkaisu lisää osoitteisiin ?v=<versio>, talletetut ovat ilman sitä.
    const hit = (await cache.match(request, { ignoreSearch: true })) ?? (request.mode === "navigate" ? await cache.match("./") : undefined);
    if (hit) return hit;
    throw err;
  }
}
