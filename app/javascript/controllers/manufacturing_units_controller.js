import { Controller } from "@hotwired/stimulus"

// Populates unit dropdowns (output yield + each input line) with the selected
// ingredient's available units. Existing selections are left untouched on load;
// options are only rebuilt when an ingredient dropdown changes.
export default class extends Controller {
  static targets = ["outputIngredient", "yieldUnit"]
  static values = { units: Object }

  outputChanged() {
    if (this.hasOutputIngredientTarget && this.hasYieldUnitTarget) {
      this.fill(this.yieldUnitTarget, this.outputIngredientTarget.value)
    }
  }

  lineChanged(event) {
    const row = event.target.closest("[data-mfg-line]")
    const unitSelect = row?.querySelector("[data-mfg-line-unit]")
    if (unitSelect) this.fill(unitSelect, event.target.value)
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
