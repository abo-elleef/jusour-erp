import { Controller } from "@hotwired/stimulus"

const CLOSED_CLASS = "sidebar-panel--closed"

export default class extends Controller {
  static targets = ["panel", "overlay"]

  toggle() {
    this.panelTarget.classList.toggle(CLOSED_CLASS)
    this.overlayTarget.classList.toggle("hidden")
  }

  close() {
    this.panelTarget.classList.add(CLOSED_CLASS)
    this.overlayTarget.classList.add("hidden")
  }
}
