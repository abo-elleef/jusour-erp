// IndexedDB storage for offline mode.
//
//   meta   — key/value: the menu snapshot, per-day order counters
//   orders — orders rung up offline, keyed by client_uuid, until the server has them
//
// Separate from the "pos-offline" database the old (never-working) payment queue
// used, so there is nothing to migrate.
const DB_NAME = "jusour-pos-offline"
const DB_VERSION = 1

let opening = null

function open() {
  if (!opening) {
    opening = new Promise((resolve, reject) => {
      const request = indexedDB.open(DB_NAME, DB_VERSION)
      request.onupgradeneeded = () => {
        const db = request.result
        if (!db.objectStoreNames.contains("meta")) db.createObjectStore("meta")
        if (!db.objectStoreNames.contains("orders")) db.createObjectStore("orders", { keyPath: "client_uuid" })
      }
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => {
        opening = null
        reject(request.error)
      }
    })
  }
  return opening
}

// Runs `work(store)` in one transaction and resolves with the value `work` returns
// (an IDBRequest's result is read once the transaction has committed).
async function transact(storeName, mode, work) {
  const db = await open()
  return new Promise((resolve, reject) => {
    const tx = db.transaction(storeName, mode)
    const outcome = work(tx.objectStore(storeName))
    tx.oncomplete = () => resolve(outcome && "result" in outcome ? outcome.result : outcome)
    tx.onerror = () => reject(tx.error)
    tx.onabort = () => reject(tx.error)
  })
}

export function getMeta(key) {
  return transact("meta", "readonly", (store) => store.get(key))
}

export function setMeta(key, value) {
  return transact("meta", "readwrite", (store) => {
    store.put(value, key)
  })
}

export function deleteMeta(key) {
  return transact("meta", "readwrite", (store) => {
    store.delete(key)
  })
}

export function putOrder(order) {
  return transact("orders", "readwrite", (store) => {
    store.put(order)
  })
}

export function getOrder(clientUuid) {
  return transact("orders", "readonly", (store) => store.get(clientUuid))
}

export function deleteOrder(clientUuid) {
  return transact("orders", "readwrite", (store) => {
    store.delete(clientUuid)
  })
}

export async function allOrders() {
  const orders = await transact("orders", "readonly", (store) => store.getAll())
  return orders.sort((a, b) => a.created_at.localeCompare(b.created_at))
}

// Next number for the given day (a "YYYY-MM-DD" string). Read and written in a
// single transaction so two tabs can never be handed the same number.
export async function nextCounter(dayKey) {
  const key = `counter:${dayKey}`
  let next = 0
  await transact("meta", "readwrite", (store) => {
    const read = store.get(key)
    read.onsuccess = () => {
      next = (read.result || 0) + 1
      store.put(next, key)
    }
  })
  return next
}

// A short code made up once per browser, used in offline order numbers when no
// workstation is chosen, so two registers without one still print different numbers.
export async function deviceCode() {
  const existing = await getMeta("device_code")
  if (existing) return existing
  const letters = "ABCDEFGHJKLMNPQRSTUVWXYZ"
  const code = Array.from(crypto.getRandomValues(new Uint8Array(2)), (n) => letters[n % letters.length]).join("")
  await setMeta("device_code", code)
  return code
}
