import { Controller } from "@hotwired/stimulus"

export const POS_BANNERS_CHANGED = "pos-banners:changed"

export default class extends Controller {
  static targets = ["container"]

  connect() {
    this.boundUpdate = () => this.updateOffset()

    this.resizeObserver = new ResizeObserver(this.boundUpdate)
    this.resizeObserver.observe(this.containerTarget)
    this.containerTarget.querySelectorAll(":scope > *").forEach((child) => {
      this.resizeObserver.observe(child)
    })

    this.mutationObserver = new MutationObserver(this.boundUpdate)
    this.mutationObserver.observe(this.containerTarget, {
      attributes: true,
      attributeFilter: ["class"],
      subtree: true,
      childList: true
    })

    document.addEventListener(POS_BANNERS_CHANGED, this.boundUpdate)
    this.updateOffset()
  }

  disconnect() {
    this.resizeObserver?.disconnect()
    this.mutationObserver?.disconnect()
    document.removeEventListener(POS_BANNERS_CHANGED, this.boundUpdate)
  }

  updateOffset() {
    const height = Array.from(this.containerTarget.children).reduce((total, child) => {
      if (child.classList.contains("hidden")) return total
      return total + child.getBoundingClientRect().height
    }, 0)

    const px = `${height}px`
    document.documentElement.style.setProperty("--pos-banner-offset", px)
    document.body.style.setProperty("--pos-banner-offset", px)
  }
}
