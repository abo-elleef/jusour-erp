import { Controller } from "@hotwired/stimulus"

// Dynamic line editor for a customer (sales) invoice: add/remove rows, refresh
// the unit options when an ingredient is picked, and keep per-line and running
// totals live from quantity × unit price.
export default class extends Controller {
  static targets = ["list", "template", "row", "runningTotal"]
  static values = { availableUnits: Object, sellingPrices: Object }

  add(event) {
    event.preventDefault()
    this._seq = (this._seq || 0) + 1
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, `${Date.now()}${this._seq}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.markDuplicates()
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
    this.markDuplicates()
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

    // Prefill the unit price with the product's selling price (a guide). The
    // field defaults to 0, so fill when it's empty OR still zero — but never
    // clobber a price the user has already typed.
    const priceInput = row.querySelector("[data-role='price']")
    const suggested = Number((this.sellingPricesValue || {})[hidden?.value])
    const current = parseFloat(priceInput?.value) || 0
    if (priceInput && suggested > 0 && current === 0) {
      priceInput.value = suggested
    }
    this.syncPriceDisplay(row)

    this.markDuplicates()
    this.recalc()
  }

  // Flag rows that repeat a product already on the invoice, so the user notices
  // before saving. Same visual language as repeated lines on transfer templates.
  markDuplicates() {
    const counts = {}
    const visibleRows = this.rowTargets.filter((row) => row.style.display !== "none")

    visibleRows.forEach((row) => {
      const id = row.querySelector("input[name*='[ingredient_id]']")?.value
      if (id) counts[id] = (counts[id] || 0) + 1
    })

    visibleRows.forEach((row) => {
      const id = row.querySelector("input[name*='[ingredient_id]']")?.value
      const repeated = !!id && counts[id] > 1
      row.classList.toggle("bg-amber-50/80", repeated)
      const badge = row.querySelector("[data-role='duplicate-badge']")
      if (badge) badge.classList.toggle("hidden", !repeated)
    })
  }

  // The unit price is locked: the value lives in a hidden field, so mirror it
  // into the visible read-only box.
  syncPriceDisplay(row) {
    const price = parseFloat(row.querySelector("[data-role='price']")?.value) || 0
    const display = row.querySelector("[data-role='price-display']")
    if (display) display.textContent = this.format(price)
  }

  recalc() {
    let total = 0
    this.rowTargets.forEach((row) => {
      if (row.style.display === "none") return
      const qty = parseFloat(row.querySelector("[data-role='qty']")?.value) || 0
      const price = parseFloat(row.querySelector("[data-role='price']")?.value) || 0
      const line = qty * price
      total += line
      // A row has more than one line-total element (mobile + desktop) — update all.
      row.querySelectorAll("[data-role='line-total']").forEach((el) => { el.textContent = this.format(line) })
    })
    if (this.hasRunningTotalTarget) this.runningTotalTarget.textContent = this.format(total)
  }

  format(value) {
    return value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
