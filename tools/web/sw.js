// Vanhan selainversion service workerin poisto. Selain hakee sw.js:n päivityksen itse, jolloin tämä worker korvaa
// vanhan: se tyhjentää välimuistit, poistaa rekisteröintinsä ja lataa avoimet sivut uudelleen verkosta.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) await caches.delete(key);
    await self.registration.unregister();
    for (const client of await self.clients.matchAll({ type: "window" })) client.navigate(client.url);
  })());
});
