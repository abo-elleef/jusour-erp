import { Controller } from "@hotwired/stimulus"

// Replaces a Chartkick chart's tooltip with lines the server already wrote
// (localised, money formatted the Rails way), so no figure is formatted twice.
//
//   titles: one title per bar, e.g. "6:00 AM – 7:00 AM"
//   lines:  lines[datasetIndex][barIndex] = array of tooltip lines
export default class extends Controller {
  static values = { chartId: String, titles: Array, lines: Array }

  connect() {
    this.attach()
  }

  // Chartkick renders after its own script runs, so the chart object may not
  // exist yet when this controller connects.
  async attach() {
    for (let attempt = 0; attempt < 60; attempt++) {
      const chart = window.Chartkick?.charts?.[this.chartIdValue]?.getChartObject?.()
      if (chart) return this.apply(chart)
      await new Promise((resolve) => setTimeout(resolve, 50))
    }
  }

  apply(chart) {
    const titles = this.titlesValue
    const lines = this.linesValue
    const tooltip = (chart.options.plugins ||= {}).tooltip ||= {}
    tooltip.callbacks = {
      ...(tooltip.callbacks || {}),
      title: (items) => (items.length ? titles[items[0].dataIndex] ?? "" : ""),
      label: (ctx) => lines[ctx.datasetIndex]?.[ctx.dataIndex] ?? ""
    }
    chart.update("none")
  }
}
