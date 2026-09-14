import { Controller } from "@hotwired/stimulus"

// Dynamic line editor for a vendor credit note: add/remove rows, refresh the
// unit options when an ingredient is picked, and keep per-line and running
// totals live from quantity × unit price.
export default class extends Controller {
  static targets = ["list", "template", "row", "runningTotal", "locationField", "invoiceSelect"]
  static values = { availableUnits: Object, supplierInvoices: Object }

  connect() {
    this.renumber()
    this.recalc()
    this.kindChanged()
  }

  // Only that supplier's own open invoices can take this credit, so swap the list
  // whenever the supplier changes rather than offering every invoice in the system.
  supplierChanged(event) {
    if (!this.hasInvoiceSelectTarget) return

    const blank = this.invoiceSelectTarget.querySelector("option[value='']")
    const invoices = (this.supplierInvoicesValue || {})[event.target.value] || []
    this.invoiceSelectTarget.innerHTML = ""
    if (blank) this.invoiceSelectTarget.appendChild(blank)
    invoices.forEach(([label, value]) => {
      const opt = document.createElement("option")
      opt.value = value
      opt.textContent = label
      this.invoiceSelectTarget.appendChild(opt)
    })
  }

  // Only a goods return moves stock, so the location picker is relevant only then.
  kindChanged() {
    if (!this.hasLocationFieldTarget) return

    const kind = this.element.querySelector("select[name*='[kind]']")?.value
    const isReturn = kind === "goods_return"
    this.locationFieldTarget.classList.toggle("opacity-50", !isReturn)
    const select = this.locationFieldTarget.querySelector("select")
    if (select) select.required = isReturn
  }

  add(event) {
    event.preventDefault()
    this._seq = (this._seq || 0) + 1
    const html = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, `${Date.now()}${this._seq}`)
    this.listTarget.insertAdjacentHTML("beforeend", html)
    this.renumber()
    this.recalc()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-vendor-credit-note-lines-target='row']")
    if (!row) return

    const destroy = row.querySelector("input[data-role='destroy']")
    const idField = row.querySelector("input[name*='[id]']")
    if (destroy && idField?.value) {
      destroy.value = "1"
      row.style.display = "none"
    } else {
      row.remove()
    }
    this.renumber()
    this.recalc()
  }

  // Repopulate a row's unit <select> from the chosen ingredient's available units.
  ingredientChanged(event) {
    const row = event.target.closest("[data-vendor-credit-note-lines-target='row']")
    if (!row) return

    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const unitSelect = row.querySelector("select[data-role='unit']")
    const units = (this.availableUnitsValue || {})[hidden?.value] || []
    if (unitSelect) {
      unitSelect.innerHTML = units.map(([label, val]) => `<option value="${val}">${label}</option>`).join("")
    }
    this.recalc()
  }

  visibleRows() {
    return this.rowTargets.filter((row) => row.style.display !== "none")
  }

  // Keep the submitted positions matching the on-screen order.
  renumber() {
    this.visibleRows().forEach((row, index) => {
      const position = row.querySelector("input[data-role='position']")
      if (position) position.value = String(index)
    })
  }

  recalc() {
    let total = 0
    this.visibleRows().forEach((row) => {
      const qty = parseFloat(row.querySelector("[data-role='qty']")?.value) || 0
      const price = parseFloat(row.querySelector("[data-role='price']")?.value) || 0
      const line = qty * price
      total += line
      const display = row.querySelector("[data-role='line-total']")
      if (display) display.textContent = line > 0 ? this.format(line) : "—"
    })
    if (this.hasRunningTotalTarget) {
      this.runningTotalTarget.textContent = total > 0 ? this.format(total) : "—"
    }
  }

  format(value) {
    return value.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
