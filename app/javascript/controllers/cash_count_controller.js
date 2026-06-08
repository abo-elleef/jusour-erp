import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["denom", "total", "hidden"]

  connect() {
    this.recalculate()
  }

  recalculate() {
    let cents = 0
    this.denomTargets.forEach((input) => {
      const count = parseInt(input.value, 10) || 0
      cents += count * parseInt(input.dataset.cents, 10)
    })
    this.totalTarget.textContent = this.formatCents(cents)
    if (this.hasHiddenTarget) {
      this.hiddenTarget.value = (cents / 100).toFixed(2)
    }
  }

  syncHidden(event) {
    this.recalculate()
    const amount = parseFloat(this.hiddenTarget?.value || "0")
    if (!amount || amount <= 0) {
      event.preventDefault()
    }
  }

  formatCents(cents) {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100)
  }
}
