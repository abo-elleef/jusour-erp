import { Controller } from "@hotwired/stimulus"

// Shared by any report that plots more series than one chart can legibly show.
// The server renders every series but ticks only the biggest few; this drives the
// rest from a filterable checkbox list beside the chart, and keeps the data table
// under it in step.
//
// Wiring: each checkbox carries data-series-key and data-index; each table row
// carries the data-series-key of the series it belongs to (several rows may share
// one key). storage-key-value scopes what gets remembered, so two reports on the
// same origin do not overwrite each other.
//
// Two independent things act on this page, and keeping them separate is what
// makes it predictable:
//
//   SELECTION (the checkboxes) decides what the report shows — chart series and
//   table rows together. It is what gets remembered.
//
//   SEARCH only filters the checkbox list itself, as an aid to finding an item in
//   a long list. It never hides a chart line or a table row, so typing in it can
//   never make data appear to vanish.
export default class extends Controller {
  static targets = [
    "checkbox", "search", "row", "count", "empty",
    "tableRow", "tableEmpty", "swatch"
  ]
  static values = { chartId: String, storageKey: String }

  connect() {
    this.restore()
    this.applyAll()
  }

  // Chartkick renders after its own script runs, so the chart object may not
  // exist yet when this controller connects.
  async chart() {
    if (this._chart) return this._chart

    for (let attempt = 0; attempt < 60; attempt++) {
      const chart = window.Chartkick?.charts?.[this.chartIdValue]?.getChartObject?.()
      if (chart) {
        this._chart = chart
        return chart
      }
      await new Promise((resolve) => setTimeout(resolve, 50))
    }
    return null
  }

  // Table and storage are synchronous; only the chart has to wait for Chartkick,
  // so the rest must not be held up behind it.
  applyAll() {
    this.applyTable()
    this.updateCount()
    this.persist()
    this.applyChart()
  }

  async applyChart() {
    const chart = await this.chart()
    if (!chart) return

    this.checkboxTargets.forEach((box) => {
      chart.setDatasetVisibility(Number(box.dataset.index), box.checked)
    })
    chart.update()
    this.paintSwatches(chart)
  }

  // With 50+ items a legend is unusable, so the picker list carries the colour
  // instead. Read from the chart rather than reproducing its palette here — a
  // second copy of the colours is a swatch that eventually names the wrong line.
  paintSwatches(chart) {
    if (this._swatchesPainted) return

    this.swatchTargets.forEach((swatch) => {
      const dataset = chart.data.datasets[Number(swatch.dataset.index)]
      const color = dataset?.borderColor ?? dataset?.backgroundColor
      if (typeof color !== "string") return

      swatch.style.backgroundColor = color
      swatch.style.borderColor = color
    })
    this._swatchesPainted = true
  }

  // One series can own several table rows (an ingredient shipped on two routes,
  // say), so every row carrying its key follows the same checkbox.
  applyTable() {
    const selected = new Set(
      this.checkboxTargets.filter((box) => box.checked).map((box) => box.dataset.seriesKey)
    )

    let visibleIndex = 0
    this.tableRowTargets.forEach((row) => {
      const visible = selected.has(row.dataset.seriesKey)
      row.hidden = !visible

      // Numbering follows what is on screen, so the column stays 1..n however
      // much of the table is filtered out.
      const indexCell = row.querySelector("[data-row-index]")
      if (visible && indexCell) indexCell.textContent = ++visibleIndex
    })

    if (this.hasTableEmptyTarget) this.tableEmptyTarget.hidden = selected.size > 0
  }

  toggle() {
    this.applyAll()
  }

  showAll(event) {
    event.preventDefault()
    this.setVisible(() => true)
  }

  hideAll(event) {
    event.preventDefault()
    this.setVisible(() => false)
  }

  // The list is ordered by volume, so "the top ones" is just the first slice.
  showTop(event) {
    event.preventDefault()
    const limit = Number(event.currentTarget.dataset.limit || 10)
    this.setVisible((_box, index) => index < limit)
  }

  setVisible(predicate) {
    this.checkboxTargets.forEach((box, index) => {
      box.checked = predicate(box, index)
    })
    this.applyAll()
  }

  // Filters the picker list only — see the note at the top of this file.
  filter() {
    const term = this.searchTarget.value.trim().toLowerCase()
    let shown = 0

    this.rowTargets.forEach((row) => {
      const match = term === "" || row.dataset.name.toLowerCase().includes(term)
      row.hidden = !match
      if (match) shown++
    })

    if (this.hasEmptyTarget) this.emptyTarget.hidden = shown > 0
  }

  updateCount() {
    if (!this.hasCountTarget) return

    const visible = this.checkboxTargets.filter((box) => box.checked).length
    this.countTarget.textContent = `${visible} / ${this.checkboxTargets.length}`
  }

  // Remembered per browser, not per user record: this is a viewing preference,
  // the same kind of thing as the report date range.
  persist() {
    if (!this.hasStorageKeyValue) return

    const selected = this.checkboxTargets
      .filter((box) => box.checked)
      .map((box) => box.dataset.seriesKey)

    try {
      window.localStorage.setItem(this.storageKeyValue, JSON.stringify(selected))
    } catch (error) {
      // Private mode, or storage full. Losing the preference is not worth an error.
    }
  }

  restore() {
    if (!this.hasStorageKeyValue) return

    let stored
    try {
      stored = window.localStorage.getItem(this.storageKeyValue)
    } catch (error) {
      return
    }
    // No stored preference at all: keep the server's "top N" defaults. An empty
    // array is a real choice (everything hidden) and must not fall back to them.
    if (stored === null) return

    let ids
    try {
      ids = JSON.parse(stored)
    } catch (error) {
      return
    }
    if (!Array.isArray(ids)) return

    // Ids saved under different filters may not be on the page now; they are
    // simply ignored rather than clearing the whole preference.
    const selected = new Set(ids)
    this.checkboxTargets.forEach((box) => {
      box.checked = selected.has(box.dataset.seriesKey)
    })
  }
}
