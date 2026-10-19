import { Controller } from "@hotwired/stimulus"

// Client-side table sort: click a <th data-sortable-table-target="header"
// data-sort-key="..."> to sort the body by the matching <td data-sort-key="...">
// in each row. A cell's data-sort-value (falls back to its text) is what gets
// compared, so formatted money/units still sort by their real amount; a header's
// data-sort-type="number" compares numerically, anything else as text. Clicking
// the same header again reverses the order. A row's "#" cell (data-index-cell)
// is renumbered 1..N after every sort, since it's a display position, not data.
//
// Remembers the last sort (per storageKey value) in localStorage, so it survives
// a full page reload triggered by something else on the page — e.g. applying a
// date range or a filter — instead of resetting to the unsorted, server order.
export default class extends Controller {
  static targets = ["header", "body"]
  static values = { storageKey: String }

  connect() {
    this.activeKey = null
    this.direction = 1

    const stored = this.readStoredSort()
    if (!stored) return

    const th = this.headerTargets.find((header) => header.dataset.sortKey === stored.key)
    if (th) this.applySort(th, stored.key, stored.direction)
  }

  sort(event) {
    const th = event.currentTarget
    const key = th.dataset.sortKey
    if (!key) return

    const direction = this.activeKey === key ? -this.direction : 1
    this.applySort(th, key, direction)
  }

  applySort(th, key, direction) {
    const numeric = th.dataset.sortType === "number"
    const rows = Array.from(this.bodyTarget.querySelectorAll(":scope > tr"))

    rows.sort((a, b) => {
      const av = this.valueFor(a, key, numeric)
      const bv = this.valueFor(b, key, numeric)
      if (numeric) return (av - bv) * direction
      return String(av).localeCompare(String(bv), undefined, { numeric: true }) * direction
    })

    rows.forEach((row) => this.bodyTarget.appendChild(row))
    this.activeKey = key
    this.direction = direction
    this.renumber()
    this.updateIndicators(th)
    this.writeStoredSort(key, direction)
  }

  valueFor(row, key, numeric) {
    const cell = row.querySelector(`[data-sort-key="${key}"]`)
    const raw = cell?.dataset.sortValue ?? cell?.textContent.trim() ?? ""
    return numeric ? parseFloat(raw) || 0 : raw
  }

  renumber() {
    this.bodyTarget.querySelectorAll(":scope > tr [data-index-cell]").forEach((cell, i) => {
      cell.textContent = i + 1
    })
  }

  updateIndicators(activeHeader) {
    this.headerTargets.forEach((th) => {
      const indicator = th.querySelector("[data-sort-indicator]")
      if (!indicator) return
      indicator.textContent = th === activeHeader ? (this.direction === 1 ? "▲" : "▼") : ""
    })
  }

  readStoredSort() {
    if (!this.hasStorageKeyValue) return null

    try {
      const parsed = JSON.parse(localStorage.getItem(this.storageName))
      if (!parsed || typeof parsed.key !== "string") return null

      return { key: parsed.key, direction: parsed.direction === -1 ? -1 : 1 }
    } catch {
      return null
    }
  }

  writeStoredSort(key, direction) {
    if (!this.hasStorageKeyValue) return

    try {
      localStorage.setItem(this.storageName, JSON.stringify({ key, direction }))
    } catch {
      // private browsing, storage disabled, etc. — fine to just not remember
    }
  }

  get storageName() {
    return `sortable-table:${this.storageKeyValue}`
  }
}
