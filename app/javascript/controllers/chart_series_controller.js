import { Controller } from "@hotwired/stimulus"

// A transfer report routinely carries 50+ ingredients, which is far past what one
// line chart can show. The server renders every series but marks only the biggest
// few visible; this drives the rest from a filterable checkbox list beside the
// chart, so the manager builds the comparison they actually want.
export default class extends Controller {
  static targets = ["checkbox", "search", "row", "count", "empty"]
  static values = { chartId: String }

  connect() {
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

  async applyAll() {
    const chart = await this.chart()
    if (!chart) return

    this.checkboxTargets.forEach((box) => {
      chart.setDatasetVisibility(Number(box.dataset.index), box.checked)
    })
    chart.update()
    this.updateCount()
  }

  async toggle(event) {
    const chart = await this.chart()
    if (!chart) return

    chart.setDatasetVisibility(Number(event.target.dataset.index), event.target.checked)
    chart.update()
    this.updateCount()
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

  // Filters the list only — hiding a row leaves its series exactly as it was, so
  // searching never silently changes what the chart shows.
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
}
