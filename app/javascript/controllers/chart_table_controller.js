import { Controller } from "@hotwired/stimulus"

// Chart / Table switch for a chart card: shows either every [data-chart-table-view="chart"]
// or every [data-chart-table-view="table"] element inside the card. A separate
// controller from `tabs` so it can sit around a tabs card (By day / By hour)
// and flip all its panels at once. Remembers the choice per storageKey.
export default class extends Controller {
  static targets = ["button"]
  static values = { storageKey: String }

  connect() {
    this.select(this.readStored() === "table" ? "table" : "chart")
  }

  switch(event) {
    this.select(event.params.view)
  }

  select(view) {
    this.buttonTargets.forEach((button) => {
      const active = button.dataset.chartTableViewParam === view
      button.classList.toggle("bg-white", active)
      button.classList.toggle("text-gray-900", active)
      button.classList.toggle("shadow-sm", active)
      button.classList.toggle("text-gray-500", !active)
      button.setAttribute("aria-pressed", active)
    })

    this.element.querySelectorAll("[data-chart-table-view]").forEach((el) => {
      el.hidden = el.dataset.chartTableView !== view
    })

    this.writeStored(view)
    if (view === "chart") this.resizeCharts()
  }

  // A chart drawn while hidden has no width; resize once it is visible again.
  resizeCharts() {
    requestAnimationFrame(() => {
      window.Chartkick?.eachChart((chart) => {
        if (!this.element.contains(chart.element)) return
        chart.getChartObject()?.resize?.()
      })
    })
  }

  readStored() {
    if (!this.hasStorageKeyValue) return null
    try {
      return localStorage.getItem(`chart-table:${this.storageKeyValue}`)
    } catch {
      return null
    }
  }

  writeStored(view) {
    if (!this.hasStorageKeyValue) return
    try {
      localStorage.setItem(`chart-table:${this.storageKeyValue}`, view)
    } catch {
      // storage unavailable — just don't remember
    }
  }
}
