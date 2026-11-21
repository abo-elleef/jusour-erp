import { Controller } from "@hotwired/stimulus"

// Draws a Chartkick bar chart when the element connects. Used instead of
// Chartkick's inline <script> for charts inside a Turbo Frame that updates the
// URL (data-turbo-action="advance"): the frame renders the new chart, then
// Turbo's page-level render fires turbo:before-render, and Chartkick's
// autoDestroy wipes every chart, leaving a blank canvas. So the controller
// draws on connect and again after any page render that destroyed it.
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

    this.chart = new window.Chartkick.BarChart(this.element, this.dataValue, this.optionsValue)
  }
}
