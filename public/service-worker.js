// Keeps the POS usable when the internet is down.
//
// Three jobs:
//   1. Cache the compiled assets (JS, CSS, icons) as they are used, so the offline
//      register page can load them with no network.
//   2. Cache the offline register page itself (/pos/offline) every time it is
//      fetched online.
//   3. When a /pos page cannot be reached, show that cached register instead.
//
// It deliberately does NOT cache the normal POS pages: those carry the cashier's
// live cart and a CSRF token, and a stale copy is worse than none.

const CACHE_NAME = "pos-cache-v4"
const OFFLINE_PAGE = "/pos/offline"
const FALLBACK_PAGE = "/offline.html"
const PRECACHE_URLS = [FALLBACK_PAGE, "/icons/icon-192.png", "/icons/icon-512.png"]

// How long to wait for the server before assuming the line is down. A dead uplink
// can leave a request hanging far longer than a cashier will stand there.
const NETWORK_TIMEOUT_MS = 6000

self.addEventListener("install", (event) => {
  event.waitUntil(caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS)))
  self.skipWaiting()
})

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((key) => key !== CACHE_NAME).map((key) => caches.delete(key)))
    )
  )
  self.clients.claim()
})

self.addEventListener("fetch", (event) => {
  const { request } = event
  if (request.method !== "GET") return
  if (request.headers.get("Turbo-Frame")) return

  const url = new URL(request.url)
  if (url.origin !== self.location.origin) return

  if (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/icons/")) {
    event.respondWith(cacheFirst(request))
    return
  }

  if (url.pathname === OFFLINE_PAGE) {
    event.respondWith(offlinePage(request))
    return
  }

  if (url.pathname.startsWith("/pos") && wantsHtml(request)) {
    event.respondWith(pageOrOfflineRegister(request))
  }
})

function wantsHtml(request) {
  return request.mode === "navigate" || (request.headers.get("Accept") || "").includes("text/html")
}

// Fingerprinted assets never change under the same URL, so the cache is always
// right; fetch once, keep forever (old ones go when CACHE_NAME is bumped).
async function cacheFirst(request) {
  const cached = await caches.match(request, { ignoreVary: true })
  if (cached) return cached

  const response = await fetch(request)
  if (response.ok) {
    const copy = response.clone()
    caches.open(CACHE_NAME).then((cache) => cache.put(request, copy))
  }
  return response
}

function withTimeout(promise, ms) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error("timeout")), ms)
    promise.then(
      (value) => { clearTimeout(timer); resolve(value) },
      (error) => { clearTimeout(timer); reject(error) }
    )
  })
}

// The offline register: always try the network first so it is current, remember
// what comes back, and fall back to the remembered copy when it cannot be reached.
async function offlinePage(request) {
  try {
    const response = await withTimeout(fetch(request), NETWORK_TIMEOUT_MS)
    // A redirect means the session ended and this is the sign-in page. Caching it
    // would leave the register permanently replaced by a login form.
    if (response.ok && !response.redirected) {
      const copy = response.clone()
      caches.open(CACHE_NAME).then((cache) => cache.put(OFFLINE_PAGE, copy))
    }
    return response
  } catch {
    const cached = await caches.match(OFFLINE_PAGE, { ignoreSearch: true })
    return cached || caches.match(FALLBACK_PAGE)
  }
}

// Any other /pos page: the live one when the server answers, the offline register
// when it does not.
//
// Only real navigations get the register. Turbo Drive's own background fetches get
// a plain network error instead, which makes Turbo fall back to a full page load —
// and that load is the navigation that gets the register under the right URL.
async function pageOrOfflineRegister(request) {
  try {
    return await withTimeout(fetch(request), NETWORK_TIMEOUT_MS)
  } catch (error) {
    if (request.mode !== "navigate") throw error

    const register = await caches.match(OFFLINE_PAGE, { ignoreSearch: true })
    return register || caches.match(FALLBACK_PAGE)
  }
}
