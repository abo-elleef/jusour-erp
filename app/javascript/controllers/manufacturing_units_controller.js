import { Controller } from "@hotwired/stimulus"

// Populates unit dropdowns (output yield + each input line) with the selected
// ingredient's available units. Existing selections are left untouched on load;
// options are only rebuilt when an ingredient picker changes. Works with both a
// native <select> (change event) and the searchable-select combobox
// (searchable-select:change custom event carrying the value in event.detail).
export default class extends Controller {
  static targets = ["yieldUnit"]
  static values = { units: Object }

  outputChanged(event) {
    if (this.hasYieldUnitTarget) this.fill(this.yieldUnitTarget, this.ingredientIdFrom(event))
  }

  lineChanged(event) {
    const row = event.target.closest("[data-mfg-line]")
    const unitSelect = row?.querySelector("[data-mfg-line-unit]")
    if (unitSelect) this.fill(unitSelect, this.ingredientIdFrom(event))
  }

  ingredientIdFrom(event) {
    if (event.detail && event.detail.value != null) return event.detail.value
    return event.target.value
  }

  fill(select, ingredientId) {
    const options = this.unitsValue[ingredientId] || []
    select.innerHTML = ""
    options.forEach(([label, value]) => {
      const opt = document.createElement("option")
      opt.value = value
      opt.textContent = label
      select.appendChild(opt)
    })
  }
}
