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

  // Only refreshes the hidden total. A zero count is a real answer (nothing sold,
  // no float), so it is the server that decides whether it is acceptable and says
  // why when it is not — blocking here made the button look dead.
  syncHidden() {
    this.recalculate()
  }

  formatCents(cents) {
    return new Intl.NumberFormat("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 }).format(cents / 100)
  }
}
