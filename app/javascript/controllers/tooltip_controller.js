import { Controller } from "@hotwired/stimulus"

// An info icon that reveals its panel on hover where the device supports hover,
// and on tap where it doesn't (touch devices fire no real hover, and a tap that
// only opened it would need a second, unrelated tap elsewhere to close it again).
// Keyboard focus always reveals it, independent of pointer capability.
export default class extends Controller {
  static targets = ["panel"]

  connect() {
    this.hoverCapable = window.matchMedia?.("(hover: hover)").matches ?? true
    this.onOutsideClick = this.onOutsideClick.bind(this)
    this.onEscape = this.onEscape.bind(this)
  }

  disconnect() {
    this.removeDismissListeners()
  }

  onMouseEnter() {
    if (this.hoverCapable) this.open()
  }

  onMouseLeave() {
    if (this.hoverCapable) this.close()
  }

  onFocus() {
    this.open()
  }

  onBlur() {
    this.close()
  }

  // Hover already opens/closes it on a hover-capable device, so a click there
  // would just re-close what the mouseenter above it opened.
  toggle(event) {
    if (this.hoverCapable) return

    event.stopPropagation()
    this.panelTarget.classList.contains("hidden") ? this.open() : this.close()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    this.clampToViewport()
    document.addEventListener("click", this.onOutsideClick)
    document.addEventListener("keydown", this.onEscape)
  }

  close() {
    this.panelTarget.classList.add("hidden")
    this.panelTarget.style.transform = ""
    this.removeDismissListeners()
  }

  // The panel always anchors to the trigger's start edge, which is correct
  // until the trigger sits near either edge of the screen (e.g. the last tile
  // in a row) and the panel would run off-screen. A physical pixel shift via
  // transform corrects for that regardless of LTR/RTL, which only affects
  // which logical edge "start" was in the first place.
  clampToViewport() {
    const panel = this.panelTarget
    panel.style.transform = ""
    const rect = panel.getBoundingClientRect()
    const margin = 12
    let shiftX = 0
    if (rect.right > window.innerWidth - margin) shiftX = window.innerWidth - margin - rect.right
    if (rect.left + shiftX < margin) shiftX = margin - rect.left
    if (shiftX !== 0) panel.style.transform = `translateX(${shiftX}px)`
  }

  removeDismissListeners() {
    document.removeEventListener("click", this.onOutsideClick)
    document.removeEventListener("keydown", this.onEscape)
  }

  onOutsideClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  onEscape(event) {
    if (event.key === "Escape") this.close()
  }
}
