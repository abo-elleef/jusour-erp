const CACHE_NAME = "pos-cache-v3";

const PRECACHE_URLS = [
  "/pos",
  "/offline.html",
  "/icons/icon-192.png",
  "/icons/icon-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => cache.addAll(PRECACHE_URLS))
  );
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(keys.filter((k) => k !== CACHE_NAME).map((k) => caches.delete(k)))
    )
  );
  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  if (event.request.method !== "GET") return;
  if (event.request.headers.get("Turbo-Frame")) return;

  const url = new URL(event.request.url);
  if (url.origin !== self.location.origin) return;

  if (url.pathname.startsWith("/assets/") || url.pathname.startsWith("/icons/")) {
    event.respondWith(
      caches.match(event.request).then((cached) => cached || fetch(event.request))
    );
    return;
  }

  if (url.pathname.startsWith("/pos") || url.pathname.startsWith("/menu")) {
    event.respondWith(
      fetch(event.request)
        .then((response) => {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
          return response;
        })
        .catch(() =>
          caches.match(event.request).then((cached) => cached || caches.match("/offline.html"))
        )
    );
  }
});

self.addEventListener("sync", (event) => {
  if (event.tag === "sync-offline-payments") {
    event.waitUntil(syncOfflinePayments());
  }
});

async function syncOfflinePayments() {
  const db = await openOfflineDB();
  const tx = db.transaction("payments", "readonly");
  const payments = await getAllFromStore(tx.objectStore("payments"));

  for (const entry of payments) {
    try {
      const response = await fetch("/pos/orders/sync", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": entry.csrfToken
        },
        body: JSON.stringify({ order: entry.data })
      });

      if (response.ok) {
        const delTx = db.transaction("payments", "readwrite");
        delTx.objectStore("payments").delete(entry.id);
      }
    } catch (e) {
      console.warn("Sync failed for payment", entry.id, e);
    }
  }
}

function openOfflineDB() {
  return new Promise((resolve, reject) => {
    const req = indexedDB.open("pos-offline", 1);
    req.onupgradeneeded = (e) => {
      const db = e.target.result;
      if (!db.objectStoreNames.contains("payments")) {
        db.createObjectStore("payments", { keyPath: "id", autoIncrement: true });
      }
    };
    req.onsuccess = (e) => resolve(e.target.result);
    req.onerror = (e) => reject(e.target.error);
  });
}

function getAllFromStore(store) {
  return new Promise((resolve, reject) => {
    const req = store.getAll();
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}
