import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "list", "template", "row", "unitLabel", "expiresOn", "unitPriceDollars",
    "runningTotal", "runningTotalWrap", "subtotalDisplay", "grandTotalDisplay", "discountPreviewWrap"
  ]
  static values = { units: Object, shelfLifeDays: Object, unitPriceDollars: Object }

  connect() {
    this.rowTargets.forEach((row) => {
      this.syncRowUnit(row)
      this.syncRowExpiry(row)
    })
    this.recalculate()
  }

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now())
    this.listTarget.insertAdjacentHTML("beforeend", content)
    this.recalculate()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-vendor-invoice-lines-target='row']")
    const destroy = row.querySelector("[data-vendor-invoice-lines-target='destroy']")
    const idField = row.querySelector("input[name*='[id]']")

    if (idField?.value) {
      destroy.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
    this.recalculate()
  }

  ingredientChanged(event) {
    const row = event.target.closest("[data-vendor-invoice-lines-target='row']")
    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const ingredientId = hidden?.value

    this.syncRowUnit(row, ingredientId)
    this.syncRowExpiry(row, ingredientId)
    this.syncRowUnitPrice(row, ingredientId)
  }

  receivedOnChanged() {
    this.rowTargets.forEach((row) => this.syncRowExpiry(row))
  }

  syncRowUnit(row, ingredientId = null) {
    const label = row.querySelector("[data-vendor-invoice-lines-target='unitLabel']")
    if (!label) return

    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const id = ingredientId ?? hidden?.value
    label.textContent = id && this.unitsValue[id] ? this.unitsValue[id] : "—"
  }

  syncRowExpiry(row, ingredientId = null) {
    const expiresField = row.querySelector("[data-vendor-invoice-lines-target='expiresOn']")
    if (!expiresField) return

    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const id = ingredientId ?? hidden?.value
    const shelfLifeDays = id ? this.shelfLifeDaysValue[id] : null
    const receivedOn = this.receivedOnValue

    if (!shelfLifeDays || !receivedOn) return

    expiresField.value = this.addDays(receivedOn, Number(shelfLifeDays))
  }

  syncRowUnitPrice(row, ingredientId = null) {
    const priceField = row.querySelector("[data-vendor-invoice-lines-target='unitPriceDollars']")
    if (!priceField) return

    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const id = ingredientId ?? hidden?.value
    const dollars = id ? this.unitPriceDollarsValue[id] : null

    if (dollars == null) return

    priceField.value = dollars
    this.recalculate()
  }

  recalculate() {
    let subtotalCents = 0

    this.rowTargets.forEach((row) => {
      if (row.classList.contains("hidden")) return

      const qty = parseFloat(row.querySelector("input[name*='[quantity]']")?.value) || 0
      const price = parseFloat(row.querySelector("[data-vendor-invoice-lines-target='unitPriceDollars']")?.value) || 0
      subtotalCents += Math.round(qty * price * 100)
    })

    if (this.hasRunningTotalTarget) {
      this.runningTotalTarget.textContent = this.formatMoney(subtotalCents)
    }
    if (this.hasRunningTotalWrapTarget) {
      this.runningTotalWrapTarget.classList.toggle("hidden", subtotalCents === 0)
    }

    if (this.hasSubtotalDisplayTarget) {
      this.subtotalDisplayTarget.textContent = this.formatMoney(subtotalCents)
    }

    let discountCents = 0
    const discountType = this.element.querySelector("[data-vendor-invoice-discount-target='type']")?.value
    if (discountType === "percentage") {
      const pct = parseFloat(this.element.querySelector("[data-vendor-invoice-discount-target='percentageField']")?.value) || 0
      discountCents = Math.round(subtotalCents * pct / 100)
    } else if (discountType === "fixed_amount") {
      const fixedDollars = parseFloat(this.element.querySelector("[data-vendor-invoice-discount-target='fixedField']")?.value) || 0
      discountCents = Math.round(fixedDollars * 100)
    }

    const adjustmentDollars = parseFloat(this.element.querySelector("input[name='vendor_invoice[adjustment_amount_dollars]']")?.value) || 0
    const adjustmentCents = Math.round(adjustmentDollars * 100)

    const totalCents = Math.max(0, subtotalCents - discountCents + adjustmentCents)

    if (this.hasGrandTotalDisplayTarget) {
      this.grandTotalDisplayTarget.textContent = this.formatMoney(totalCents)
    }

    if (this.hasDiscountPreviewWrapTarget) {
      this.discountPreviewWrapTarget.classList.toggle("hidden", subtotalCents === 0)
    }
  }

  formatMoney(cents) {
    const dollars = cents / 100
    return "ج.م. " + dollars.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }

  addDays(dateString, days) {
    const date = new Date(`${dateString}T12:00:00`)
    date.setDate(date.getDate() + days)

    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, "0")
    const day = String(date.getDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }

  get receivedOnValue() {
    return this.element.querySelector("input[name='vendor_invoice[received_on]']")?.value
  }
}
