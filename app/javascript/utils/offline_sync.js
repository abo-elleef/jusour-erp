// Everything that moves data between the browser's offline store and the server:
// keeping the menu snapshot fresh while online, caching the offline register page,
// and pushing queued orders once the internet is back.
import { allOrders, deleteMeta, deleteOrder, getMeta, putOrder, setMeta } from "utils/offline_db"

// These mirror config/routes.rb (pos/offline*). They are constants rather than
// data attributes because the same code runs on the online POS and the cached
// offline page, and neither should depend on the other for them.
export const OFFLINE_PAGE_URL = "/pos/offline"
export const SNAPSHOT_URL = "/pos/offline/snapshot"
export const ORDERS_URL = "/pos/offline/orders"

const SNAPSHOT_MAX_AGE_MS = 3 * 60 * 1000

// navigator.onLine only says there is a network — a router with a dead uplink still
// reads "online". The only honest test is asking our own server, so do that.
export async function isReachable(timeoutMs = 4000) {
  if (!navigator.onLine) return false

  const controller = new AbortController()
  const timer = setTimeout(() => controller.abort(), timeoutMs)
  try {
    const response = await fetch(`/up?_=${Date.now()}`, { cache: "no-store", credentials: "omit", signal: controller.signal })
    return response.ok
  } catch {
    return false
  } finally {
    clearTimeout(timer)
  }
}

// The order that was on the online register when the internet dropped. The page
// renders it (pos/_offline_handoff) in two places that refresh at different times,
// so the copy rendered last is the true one. Saved under meta "handoff" for the
// offline register to open with; nothing saved means the register starts empty.
export async function saveHandoff(root = document) {
  let latest = null
  root.querySelectorAll("script[data-offline-handoff]").forEach((el) => {
    try {
      const data = JSON.parse(el.textContent)
      if (data && (!latest || data.rendered_at > latest.rendered_at)) latest = data
    } catch {
      // A half-rendered copy is no worse than none.
    }
  })

  try {
    if (latest?.order) await setMeta("handoff", { ...latest.order, saved_at: Date.now() })
    else await deleteMeta("handoff")
  } catch {
    // Without IndexedDB there is no offline register to hand it to anyway.
  }
}

export async function isOfflineReady() {
  try {
    const snapshot = await getMeta("snapshot")
    if (!snapshot) return false
    if (typeof caches === "undefined") return false

    return !!(await caches.match(OFFLINE_PAGE_URL, { ignoreSearch: true, ignoreVary: true }))
  } catch {
    return false
  }
}

// Returns { ok, authRequired }. Stores the snapshot on success.
export async function refreshSnapshot({ force = false } = {}) {
  const current = await getMeta("snapshot")
  if (!force && current && Date.now() - (current.saved_at || 0) < SNAPSHOT_MAX_AGE_MS) {
    return { ok: true, authRequired: false, skipped: true }
  }

  try {
    const response = await fetch(SNAPSHOT_URL, {
      credentials: "same-origin",
      cache: "no-store",
      headers: { Accept: "application/json" }
    })
    if (response.status === 401 || response.status === 403) return { ok: false, authRequired: true }
    if (!response.ok || !(response.headers.get("content-type") || "").includes("json")) return { ok: false, authRequired: false }

    const snapshot = await response.json()
    snapshot.saved_at = Date.now()
    await setMeta("snapshot", snapshot)
    return { ok: true, authRequired: false }
  } catch {
    return { ok: false, authRequired: false }
  }
}

// Pulls the offline page through the service worker so it is cached for the next
// time the line drops. Harmless to repeat.
async function cacheOfflinePage() {
  try {
    await fetch(OFFLINE_PAGE_URL, { credentials: "same-origin", headers: { Accept: "text/html" } })
  } catch {
    // Best effort — the next online page load tries again.
  }
}

// Called from every online POS page: keep the snapshot and the cached page fresh.
export async function prepareOffline() {
  const result = await refreshSnapshot()
  if (result.ok && !result.skipped) await cacheOfflinePage()
  return result
}

function orderPayload(order) {
  return {
    client_uuid: order.client_uuid,
    offline_number: order.offline_number,
    created_at: order.created_at,
    user_id: order.user_id,
    location_id: order.location_id,
    workstation_id: order.workstation_id,
    drawer_session_id: order.drawer_session_id,
    order_type: order.order_type,
    table_number: order.table_number,
    customer_name: order.customer_name,
    customer_phone: order.customer_phone,
    delivery_address: order.delivery_address,
    notes: order.notes,
    replaces_order_id: order.replaces_order_id || null,
    tendered_cents: order.tendered_cents,
    items: order.items.map((line) => ({
      menu_item_id: line.menu_item_id,
      combo_id: line.combo_id,
      quantity: line.quantity,
      unit_price_cents: line.unit_price_cents,
      notes: line.notes,
      promo_id: line.promo_id,
      promo_label: line.promo_label,
      promo_discount_cents: line.promo_discount_cents,
      modifiers: (line.modifiers || []).map((m) => ({ id: m.id, name: m.name, price_adjustment_cents: m.price_adjustment_cents }))
    }))
  }
}

// One POST. Resolves with:
//   { status: "synced" }                    — the server has it (or already had it)
//   { status: "rejected", error }           — the server will never accept it as is
//   { status: "retry" }                     — network/server trouble, try later
//   { status: "auth" }                      — signed out or token stale
async function postOrder(order, csrfToken) {
  let response
  try {
    response = await fetch(ORDERS_URL, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": csrfToken || "" },
      body: JSON.stringify({ order: orderPayload(order) })
    })
  } catch {
    return { status: "retry" }
  }

  const isJson = (response.headers.get("content-type") || "").includes("json")
  if (response.ok) return { status: "synced" }
  if (response.status === 401) return { status: "auth" }
  if (response.status >= 500) return { status: "retry" }
  if (!isJson) return { status: "auth" } // a CSRF failure renders an HTML 422

  const body = await response.json().catch(() => ({}))
  const error = (body.errors || [body.error]).filter(Boolean).join(", ") || `HTTP ${response.status}`
  return { status: "rejected", error }
}

async function syncOnce(retryRejected) {
  const result = { synced: 0, rejected: 0, remaining: 0, authRequired: false }
  const everything = await allOrders()
  // An order the server refused will be refused again; leave it alone until a
  // person asks for another try.
  const queued = retryRejected ? everything : everything.filter((order) => order.sync?.status !== "rejected")
  if (queued.length === 0) return { ...result, remaining: everything.length }

  // A fresh snapshot is also a fresh CSRF token, and tells us at once whether the
  // session is still signed in.
  const refreshed = await refreshSnapshot({ force: true })
  if (refreshed.authRequired) return { ...result, remaining: everything.length, authRequired: true }

  const snapshot = await getMeta("snapshot")
  const csrfToken = snapshot?.csrf_token || document.querySelector("meta[name='csrf-token']")?.content

  for (const order of queued) {
    const outcome = await postOrder(order, csrfToken)

    if (outcome.status === "synced") {
      await deleteOrder(order.client_uuid)
      result.synced += 1
    } else if (outcome.status === "rejected") {
      await putOrder({ ...order, sync: { status: "rejected", error: outcome.error } })
      result.rejected += 1
    } else if (outcome.status === "auth") {
      result.authRequired = true
      break
    } else {
      break // the connection is not good enough; the rest wait for the next round
    }
  }

  result.remaining = (await allOrders()).length
  return result
}

// Pushes every queued order. Two tabs calling this at once take turns, so an order
// is never posted twice at the same moment (the server would also catch it, but
// there is no reason to make it).
export function syncQueuedOrders({ retryRejected = false } = {}) {
  const run = () => syncOnce(retryRejected)
  if (navigator.locks) return navigator.locks.request("jusour-offline-sync", run)
  return run()
}

export async function queuedCount() {
  try {
    return (await allOrders()).length
  } catch {
    return 0
  }
}
