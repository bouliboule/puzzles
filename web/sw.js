// Offline support: precache the whole app, serve cache-first.
// VERSION is replaced at deploy time; bump it to ship an update.
const VERSION = 'dev';
const CACHE = 'puzzles-' + VERSION;
const PUZZLES = ['bridges', 'keen', 'loopy', 'pattern'];
const FILES = [
  './', 'index.html', 'manifest.webmanifest', 'css/app.css',
  'js/app.js', 'js/board.js', 'js/engine.js', 'js/puzzles.js', 'js/gen-worker.js',
  'icons/icon.svg', 'icons/icon-192.png', 'icons/icon-512.png', 'icons/apple-touch-icon.png',
  ...PUZZLES.flatMap(p => [`wasm/${p}.js`, `wasm/${p}.wasm`]),
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES.map(f => new Request(f, { cache: 'reload' })))));
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
    await self.clients.claim();
  })());
});

self.addEventListener('message', (e) => {
  if (e.data === 'skipWaiting') self.skipWaiting();
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;
  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const url = new URL(req.url);
    url.search = '';
    const key = req.mode === 'navigate' ? new URL('./', self.registration.scope).href : url.href;
    const hit = await cache.match(key);
    if (hit) return hit;
    try {
      const res = await fetch(req);
      if (res.ok) cache.put(key, res.clone());
      return res;
    } catch (err) {
      return (await cache.match(new URL('./', self.registration.scope).href)) || Response.error();
    }
  })());
});
