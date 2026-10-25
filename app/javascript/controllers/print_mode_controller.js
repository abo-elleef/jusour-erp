import { Controller } from "@hotwired/stimulus"

// Prints the page in a named mode: sets <html data-print-mode="…"> for the
// print dialog only, so print CSS can show a different cut of the same page
// (e.g. balances without the availability checkboxes).
export default class extends Controller {
  static values = { mode: String }

  print() {
    const root = document.documentElement
    root.dataset.printMode = this.modeValue
    window.addEventListener("afterprint", () => delete root.dataset.printMode, { once: true })
    window.print()
  }
}
