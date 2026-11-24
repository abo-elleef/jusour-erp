import { Controller } from "@hotwired/stimulus"

// The Place order fee popup and the payment modal: picking a delivery area puts its fee into the fee
// box and moves the cursor there, so the cashier can change it or press Enter to
// place the order. Clearing the area leaves the typed fee alone.
export default class extends Controller {
  static targets = ["fee"]

  apply(event) {
    const picker = event.target.closest("[data-searchable-select-options]")
    let options = []
    try { options = JSON.parse(picker?.dataset.searchableSelectOptions || "[]") } catch { options = [] }
    const area = options.find((option) => String(option.value) === String(event.target.value))
    if (!area || !this.hasFeeTarget) return

    this.feeTarget.value = area.fee
    // Lets listeners re-price (the payment modal's amount due).
    this.feeTarget.dispatchEvent(new Event("input", { bubbles: true }))
    this.feeTarget.focus()
    this.feeTarget.select()
  }
}
