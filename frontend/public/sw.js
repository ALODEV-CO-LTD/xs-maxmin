// Service worker: keeps the app shell (index.html + hashed JS/CSS assets)
// available offline. API calls are never cached here - offline data lives in
// IndexedDB (see src/offline.js).
const CACHE = 'mamba-shell-v3'

// Files at fixed (un-hashed) URLs: pre-cached for offline, but always fetched
// network-first so a replaced manifest/icon is never stuck behind the cache.
const FIXED = [
  '/favicon.svg',
  '/manifest.webmanifest',
  '/favicon.png',
  '/icons/icon-192.png',
  '/icons/icon-512.png',
  '/icons/icon-maskable-512.png',
  '/icons/apple-touch-icon-180.png',
]

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches
      .open(CACHE)
      // '/' must succeed; the icons are best-effort so one 404 cannot block install.
      .then((c) => c.add('/').then(() => Promise.all(FIXED.map((u) => c.add(u).catch(() => {})))))
      .then(() => self.skipWaiting()),
  )
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (event) => {
  const req = event.request
  if (req.method !== 'GET') return
  const url = new URL(req.url)
  if (url.origin !== self.location.origin || url.pathname.startsWith('/api/')) return

  if (req.mode === 'navigate') {
    // Network first so a new deploy shows up; fall back to the cached shell.
    event.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone()
          caches.open(CACHE).then((c) => c.put('/', copy))
          return res
        })
        .catch(() => caches.match('/')),
    )
    return
  }

  if (FIXED.includes(url.pathname)) {
    event.respondWith(
      fetch(req)
        .then((res) => {
          if (res.ok) {
            const copy = res.clone()
            caches.open(CACHE).then((c) => c.put(req, copy))
          }
          return res
        })
        .catch(() => caches.match(req)),
    )
    return
  }

  // Static assets: cache first (build file names are content-hashed), filled lazily.
  event.respondWith(
    caches.match(req).then(
      (hit) =>
        hit ||
        fetch(req).then((res) => {
          if (res.ok) {
            const copy = res.clone()
            caches.open(CACHE).then((c) => c.put(req, copy))
          }
          return res
        }),
    ),
  )
})
