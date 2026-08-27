import { Controller } from "@hotwired/stimulus"

// Dynamic line editor for a customer (sales) invoice: add/remove rows, refresh
// the unit options when an ingredient is picked, and keep per-line and running
// totals live from quantity × unit price.
export default class extends Controller {
  static targets = ["list", "template", "row", "runningTotal"]
  static values = { availableUnits: Object }

  add(event) {
    event.preventDefault()
    this._seq = (this._seq || 0) + 1
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, `${Date.now()}${this._seq}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.recalc()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-customer-invoice-lines-target='row']")
    if (!row) return
    const destroy = row.querySelector("input[data-role='destroy']")
    if (destroy) {
      destroy.value = "1"
      row.style.display = "none"
    } else {
      row.remove()
    }
    this.recalc()
  }

  // Repopulate a row's unit <select> from the chosen ingredient's available units.
  ingredientChanged(event) {
    const row = event.target.closest("[data-customer-invoice-lines-target='row']")
    if (!row) return
    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const unitSelect = row.querySelector("select[data-role='unit']")
    const units = (this.availableUnitsValue || {})[hidden?.value] || []
    if (unitSelect && units.length) {
      unitSelect.innerHTML = units.map(([label, val]) => `<option value="${val}">${label}</option>`).join("")
    }
    this.recalc()
  }

  recalc() {
    let total = 0
    this.rowTargets.forEach((row) => {
      if (row.style.display === "none") return
      const qty = parseFloat(row.querySelector("[data-role='qty']")?.value) || 0
      const price = parseFloat(row.querySelector("[data-role='price']")?.value) || 0
      const line = qty * price
      total += line
      const disp = row.querySelector("[data-role='line-total']")
      if (disp) disp.textContent = this.format(line)
    })
    if (this.hasRunningTotalTarget) this.runningTotalTarget.textContent = this.format(total)
  }

  format(value) {
    return value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
