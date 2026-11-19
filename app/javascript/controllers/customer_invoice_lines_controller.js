import { Controller } from "@hotwired/stimulus"

// Dynamic line editor for a customer (sales) invoice: add/remove rows, refresh
// the unit options when an ingredient is picked, and keep per-line and running
// totals live from quantity × unit price.
export default class extends Controller {
  static targets = ["list", "template", "row", "runningTotal", "deliveryFeeInput"]
  static values = { availableUnits: Object, sellingPrices: Object, unitCosts: Object }

  connect() {
    this.rowTargets.forEach((row) => this.markBelowCost(row))
  }

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

    // Start the unit price at the product's selling price. A new product
    // replaces the old one's price; the user may then type their own (the line
    // is marked "price changed" on save when it differs).
    const priceInput = row.querySelector("[data-role='price']")
    const suggested = Number((this.sellingPricesValue || {})[hidden?.value])
    if (priceInput && suggested > 0) {
      priceInput.value = suggested.toFixed(2)
    }

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

  // Red warning when the price is under the product's standard cost for the
  // chosen unit. A warning only — the line still saves. No cost, no warning.
  markBelowCost(row) {
    const warning = row.querySelector("[data-role='below-cost']")
    if (!warning) return
    const ingredientId = row.querySelector("input[name*='[ingredient_id]']")?.value
    const unit = row.querySelector("select[data-role='unit']")?.value
    const cost = Number(((this.unitCostsValue || {})[ingredientId] || {})[unit])
    const price = this.toNumber(row.querySelector("[data-role='price']")?.value)
    const below = cost > 0 && price < cost
    warning.classList.toggle("hidden", !below)
    const costEl = warning.querySelector("[data-role='cost']")
    if (costEl && below) costEl.textContent = this.format(cost)
  }

  // Prices may be typed with Arabic-Indic digits; arabic-numerals normally
  // converts them first, but don't rely on listener order.
  toNumber(value) {
    const ascii = String(value || "")
      .replace(/[\u0660-\u0669]/g, (d) => d.charCodeAt(0) - 0x0660)
      .replace(/[\u06F0-\u06F9]/g, (d) => d.charCodeAt(0) - 0x06F0)
      .replace(/[\u066B]/g, ".")
    return parseFloat(ascii) || 0
  }

  recalc() {
    let total = 0
    this.rowTargets.forEach((row) => {
      if (row.style.display === "none") return
      const qty = parseFloat(row.querySelector("[data-role='qty']")?.value) || 0
      const price = this.toNumber(row.querySelector("[data-role='price']")?.value)
      const line = qty * price
      this.markBelowCost(row)
      total += line
      // A row has more than one line-total element (mobile + desktop) — update all.
      row.querySelectorAll("[data-role='line-total']").forEach((el) => { el.textContent = this.format(line) })
    })
    if (this.hasDeliveryFeeInputTarget) total += parseFloat(this.deliveryFeeInputTarget.value) || 0
    if (this.hasRunningTotalTarget) this.runningTotalTarget.textContent = this.format(total)
  }

  format(value) {
    return value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
