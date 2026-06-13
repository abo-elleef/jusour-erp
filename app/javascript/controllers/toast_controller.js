import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]
  static values = { dismissAfter: { type: Number, default: 4000 } }

  connect() {
    this.prepareAll()
    this.observer = new MutationObserver(() => this.prepareAll())
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
    this.itemTargets.forEach((item) => this.clearDismissTimer(item))
  }

  dismiss(event) {
    const item = event.currentTarget.closest("[data-toast-target='item']")
    if (item) this.removeItem(item)
  }

  prepareAll() {
    this.itemTargets.forEach((item) => this.prepare(item))
  }

  prepare(item) {
    if (item.dataset.toastPrepared === "true") return

    item.dataset.toastPrepared = "true"
    this.animateIn(item)
    this.scheduleDismiss(item)
  }

  scheduleDismiss(item) {
    this.clearDismissTimer(item)

    const timeout = Number(item.dataset.toastDismissValue || this.dismissAfterValue)
    item._toastTimeout = window.setTimeout(() => this.removeItem(item), timeout)
  }

  clearDismissTimer(item) {
    if (item._toastTimeout) {
      window.clearTimeout(item._toastTimeout)
      item._toastTimeout = null
    }
  }

  removeItem(item) {
    this.clearDismissTimer(item)

    item.style.transition = "opacity 0.3s ease, transform 0.3s ease"
    item.style.opacity = "0"
    item.style.transform = "translateY(-0.5rem) scale(0.98)"

    window.setTimeout(() => item.remove(), 300)
  }

  animateIn(item) {
    item.style.opacity = "0"
    item.style.transform = "translateY(-0.5rem) scale(0.98)"

    window.requestAnimationFrame(() => {
      item.style.transition = "opacity 0.3s ease, transform 0.3s ease"
      item.style.opacity = "1"
      item.style.transform = "translateY(0) scale(1)"
    })
  }
}
