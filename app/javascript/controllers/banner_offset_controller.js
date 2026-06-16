import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["container"]

  connect() {
    this.observer = new ResizeObserver(() => this.updateOffset())
    this.observer.observe(this.containerTarget)
    this.updateOffset()
  }

  disconnect() {
    this.observer?.disconnect()
  }

  updateOffset() {
    const height = this.containerTarget.getBoundingClientRect().height
    document.documentElement.style.setProperty("--pos-banner-offset", `${height}px`)
  }
}
