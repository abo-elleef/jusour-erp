import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "list", "template", "row", "unitSelect", "expiresOn",
    "lineTotalDollars", "unitPriceDisplay", "detailsModal", "detailsDot",
    "runningTotal", "runningTotalWrap", "subtotalDisplay", "grandTotalDisplay", "discountPreviewWrap",
    "freightAmount", "freightDisplay", "freightPreviewWrap"
  ]
  static values = { availableUnits: Object, shelfLifeDays: Object, unitPriceDollars: Object }

  connect() {
    // Existing rows keep their server-rendered unit selection; only sync expiry.
    this.rowTargets.forEach((row) => this.syncRowExpiry(row))
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

  openDetails(event) {
    event.preventDefault()
    const row = event.target.closest("[data-vendor-invoice-lines-target='row']")
    row.querySelector("[data-vendor-invoice-lines-target='detailsModal']")?.classList.remove("hidden")
  }

  closeDetails(event) {
    event.preventDefault()
    const modal = event.target.closest("[data-vendor-invoice-lines-target='detailsModal']")
    modal?.classList.add("hidden")

    const row = event.target.closest("[data-vendor-invoice-lines-target='row']")
    this.syncDetailsDot(row)
  }

  syncDetailsDot(row) {
    if (!row) return

    const dot = row.querySelector("[data-vendor-invoice-lines-target='detailsDot']")
    if (!dot) return

    const batch = row.querySelector("input[name*='[batch_reference]']")?.value?.trim()
    const notes = row.querySelector("[name*='[line_notes]']")?.value?.trim()
    dot.classList.toggle("hidden", !batch && !notes)
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
    const select = row.querySelector("[data-vendor-invoice-lines-target='unitSelect']")
    if (!select) return

    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const id = ingredientId ?? hidden?.value
    const options = id ? this.availableUnitsValue[id] : null

    select.innerHTML = ""
    if (!options) return

    // First option is the ingredient's base unit — default the selection to it.
    options.forEach(([label, value]) => {
      const opt = document.createElement("option")
      opt.value = value
      opt.textContent = label
      select.appendChild(opt)
    })
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
    this.recalculate()
  }

  recalculate() {
    let subtotalCents = 0

    this.rowTargets.forEach((row) => {
      if (row.classList.contains("hidden")) return

      const qty = parseFloat(row.querySelector("input[name*='[quantity]']")?.value) || 0
      const lineTotalDollars = parseFloat(row.querySelector("[data-vendor-invoice-lines-target='lineTotalDollars']")?.value) || 0
      const lineCents = Math.round(lineTotalDollars * 100)
      subtotalCents += lineCents

      const unitPriceDisplay = row.querySelector("[data-vendor-invoice-lines-target='unitPriceDisplay']")
      if (unitPriceDisplay) {
        if (lineCents > 0 && qty > 0) {
          const unitCents = lineCents / qty
          unitPriceDisplay.textContent = this.formatMoney(Math.round(unitCents))
        } else {
          unitPriceDisplay.textContent = "—"
        }
      }
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

    const discountCents = (() => {
      const discountType = this.element.querySelector("[data-vendor-invoice-discount-target='type']")?.value
      if (discountType === "percentage") {
        const pct = parseFloat(this.element.querySelector("[data-vendor-invoice-discount-target='percentageField']")?.value) || 0
        return Math.round(subtotalCents * pct / 100)
      }
      if (discountType === "fixed_amount") {
        const fixedDollars = parseFloat(this.element.querySelector("[data-vendor-invoice-discount-target='fixedField']")?.value) || 0
        return Math.round(fixedDollars * 100)
      }
      return 0
    })()

    const totalCents = Math.max(0, subtotalCents - discountCents)

    if (this.hasGrandTotalDisplayTarget) {
      const label = this.formatMoney(totalCents)
      this.grandTotalDisplayTargets.forEach((el) => { el.textContent = label })
    }

    if (this.hasDiscountPreviewWrapTarget) {
      this.discountPreviewWrapTarget.classList.toggle("hidden", subtotalCents === 0)
    }

    const freightDollars = this.hasFreightAmountTarget
      ? (parseFloat(this.freightAmountTarget.value) || 0)
      : 0
    const freightCents = Math.round(freightDollars * 100)
    if (this.hasFreightDisplayTarget) {
      this.freightDisplayTarget.textContent = this.formatMoney(freightCents)
    }
    if (this.hasFreightPreviewWrapTarget) {
      this.freightPreviewWrapTarget.classList.toggle("hidden", freightCents <= 0)
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
