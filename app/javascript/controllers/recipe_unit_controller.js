import { Controller } from "@hotwired/stimulus"

// Populates the unit dropdown with the selected ingredient's available units.
export default class extends Controller {
  static targets = ["ingredient", "unit"]
  static values = { units: Object }

  connect() {
    this.populate()
  }

  ingredientChanged() {
    this.populate()
  }

  populate() {
    if (!this.hasUnitTarget || !this.hasIngredientTarget) return

    const options = this.unitsValue[this.ingredientTarget.value] || []
    this.unitTarget.innerHTML = ""
    options.forEach(([label, value]) => {
      const opt = document.createElement("option")
      opt.value = value
      opt.textContent = label
      this.unitTarget.appendChild(opt)
    })
  }
}
