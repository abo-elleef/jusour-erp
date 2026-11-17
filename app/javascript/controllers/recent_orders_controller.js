import { Controller } from "@hotwired/stimulus"

// Lets a self-ordering customer find their orders again after closing the browser.
//
// The order status page calls `remember` (it is where the customer lands after
// sending, so every order passes through it). The branch menu shows the saved
// orders from the last day as links back to their status pages.
//
// Lives only in this browser's localStorage: no login, nothing shared, and a
// different phone or cleared site data starts empty. Never put anything here the
// status link itself doesn't already show.
const KEEP_MS = 24 * 60 * 60 * 1000
const MAX_ENTRIES = 5
const FINAL_STATUSES = ["rejected", "expired"]

export default class extends Controller {
  static targets = ["list"]
  static values = {
    storageKey: String,
    mode: { type: String, default: "list" }, // "list" (menu) or "remember" (status page)
    order: Object,                           // remember: { token, url, placedAt, total, status }
    labels: Object                           // list: { pending, accepted, view }
  }

  connect() {
    if (this.modeValue === "remember") this.remember()
    else this.render()
  }

  remember() {
    const order = this.orderValue
    let entries = this.load().filter((entry) => entry.token !== order.token)
    // A rejected or expired order has nothing left to follow, so drop it.
    if (!FINAL_STATUSES.includes(order.status)) entries.unshift(order)
    this.save(entries.slice(0, MAX_ENTRIES))
  }

  render() {
    const entries = this.load()
    if (entries.length === 0) return

    this.listTarget.replaceChildren(...entries.map((entry) => this.row(entry)))
    this.element.classList.remove("hidden")
  }

  row(entry) {
    const link = document.createElement("a")
    link.href = entry.url
    link.className = "flex items-center justify-between gap-3 rounded-xl border border-amber-200 bg-white px-4 py-3 text-sm hover:bg-amber-50"

    const info = document.createElement("span")
    info.className = "flex flex-col"
    const status = document.createElement("span")
    status.className = "font-medium text-stone-900"
    status.textContent = this.labelsValue[entry.status] || this.labelsValue.pending
    const meta = document.createElement("span")
    meta.className = "text-xs text-stone-500 tabular-nums"
    meta.textContent = `${this.formatTime(entry.placedAt)} · ${entry.total}`
    info.append(status, meta)

    const view = document.createElement("span")
    view.className = "shrink-0 font-semibold text-amber-800"
    view.textContent = this.labelsValue.view

    link.append(info, view)
    return link
  }

  formatTime(iso) {
    const date = new Date(iso)
    const lang = document.documentElement.lang || undefined
    try {
      return date.toLocaleTimeString(lang, { hour: "numeric", minute: "2-digit" })
    } catch (_e) {
      return date.toLocaleTimeString()
    }
  }

  // Entries older than a day are dropped on every read.
  load() {
    try {
      const raw = window.localStorage.getItem(this.storageKeyValue)
      const entries = raw ? JSON.parse(raw) : []
      const cutoff = Date.now() - KEEP_MS
      return Array.isArray(entries)
        ? entries.filter((entry) => entry && entry.token && entry.url && Date.parse(entry.placedAt) > cutoff)
        : []
    } catch (_e) {
      return []
    }
  }

  save(entries) {
    try {
      window.localStorage.setItem(this.storageKeyValue, JSON.stringify(entries))
    } catch (_e) {
      // Private mode or storage blocked: the status link still works on its own.
    }
  }
}
