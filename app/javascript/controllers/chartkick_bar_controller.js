import { Controller } from "@hotwired/stimulus"

// Draws a Chartkick bar chart when the element connects. Used instead of
// Chartkick's inline <script> for charts inside a Turbo Frame that updates the
// URL (data-turbo-action="advance"): the frame renders the new chart, then
// Turbo's page-level render fires turbo:before-render, and Chartkick's
// autoDestroy wipes every chart, leaving a blank canvas. So the controller
// draws on connect and again after any page render that destroyed it.
// Writes each bar's value just past its end, so readers don't have to hover.
// Global but opt-in: only charts with options.plugins.barValueLabels.display.
const barValueLabels = {
  id: "barValueLabels",
  afterDatasetsDraw(chart, _args, opts) {
    if (!opts?.display) return
    const { ctx } = chart
    const horizontal = chart.options.indexAxis === "y"
    const format = new Intl.NumberFormat("en-US", { maximumFractionDigits: opts.decimals ?? 2 })
    ctx.save()
    ctx.font = "600 12px system-ui, -apple-system, sans-serif"
    ctx.fillStyle = opts.color || "#374151"
    chart.data.datasets.forEach((dataset, i) => {
      const meta = chart.getDatasetMeta(i)
      if (meta.hidden) return
      meta.data.forEach((bar, j) => {
        const value = dataset.data[j]
        if (value == null) return
        const text = format.format(typeof value === "object" ? (horizontal ? value.x : value.y) : value)
        if (horizontal) {
          ctx.textAlign = "left"
          ctx.textBaseline = "middle"
          ctx.fillText(text, bar.x + 6, bar.y)
        } else {
          ctx.textAlign = "center"
          ctx.textBaseline = "bottom"
          ctx.fillText(text, bar.x, bar.y - 4)
        }
      })
    })
    ctx.restore()
  }
}
let barValueLabelsRegistered = false

export default class extends Controller {
  static values = { data: Array, options: Object }

  connect() {
    this.draw()
    this.redrawIfDestroyed = () => {
      if (!this.element.isConnected) return
      if (window.Chartkick?.charts?.[this.element.id] !== this.chart) this.draw()
    }
    document.addEventListener("turbo:render", this.redrawIfDestroyed)
  }

  disconnect() {
    document.removeEventListener("turbo:render", this.redrawIfDestroyed)
    this.chart?.destroy()
    this.chart = null
  }

  draw() {
    if (!window.Chartkick) return
    if (window.Chart && !barValueLabelsRegistered) {
      window.Chart.register(barValueLabels)
      barValueLabelsRegistered = true
    }

    this.chart = new window.Chartkick.BarChart(this.element, this.dataValue, this.optionsValue)
  }
}
