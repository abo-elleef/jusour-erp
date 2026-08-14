import { Controller } from "@hotwired/stimulus"

// Intercepts bulk production submit and shows a summary confirm. Bulk recording
// moves stock for every filled row and is hard to undo, so the operator must
// see the list before it goes through.
export default class extends Controller {
  static targets = ["row"]
  static values = {
    warning: String,
    noneFilled: String,
    heading: String
  }

  connect() {
    this.confirmed = false
  }

  submit(event) {
    if (this.confirmed) return

    event.preventDefault()
    event.stopImmediatePropagation()

    const filled = this.filledRows()
    if (filled.length === 0) {
      window.alert(this.noneFilledValue)
      return
    }

    const location = this.element.querySelector("[data-bulk-location]")
    const date = this.element.querySelector("[data-bulk-date]")
    const heading = this.headingValue
      .replaceAll("{{count}}", String(filled.length))
      .replaceAll("{{location}}", location?.selectedOptions?.[0]?.textContent?.trim() || "")
      .replaceAll("{{date}}", date?.value || "")
    const message = [heading, "", this.warningValue, "", ...filled].join("\n")
    if (!window.confirm(message)) return

    this.confirmed = true
    this.element.requestSubmit()
  }

  filledRows() {
    return this.rowTargets.flatMap((row) => {
      const qty = row.querySelector("[data-bulk-qty]")
      if (!qty || qty.value === "" || Number(qty.value) <= 0) return []

      const unitSelect = row.querySelector("[data-bulk-unit]")
      const unit = unitSelect?.selectedOptions?.[0]?.textContent?.trim() || row.dataset.unitLabel || ""
      const name = row.dataset.name || ""
      return [`• ${name} — ${qty.value} ${unit}`.trim()]
    })
  }
}
