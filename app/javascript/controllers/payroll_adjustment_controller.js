import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["fixedAmount", "overtimeHours", "unitType", "kind"]

  connect() {
    this.refreshUnitTypes()
    this.toggleUnitFields()
  }

  kindChanged() {
    this.refreshUnitTypes()
    this.toggleUnitFields()
  }

  unitTypeChanged() {
    this.toggleUnitFields()
  }

  refreshUnitTypes() {
    if (!this.hasKindTarget || !this.hasUnitTypeTarget) return

    const kind = this.kindTarget.value
    const unitSelect = this.unitTypeTarget
    const currentValue = unitSelect.value
    const bonusValues = ["full_day", "half_day", "quarter_day", "fixed", "overtime"]
    const penaltyValues = ["full_day", "half_day", "quarter_day", "fixed"]
    const allowed = kind === "bonus" ? bonusValues : penaltyValues

    Array.from(unitSelect.options).forEach((option) => {
      option.hidden = !allowed.includes(option.value)
      option.disabled = !allowed.includes(option.value)
    })

    if (!allowed.includes(currentValue)) {
      unitSelect.value = allowed[0]
    }
  }

  toggleUnitFields() {
    if (!this.hasUnitTypeTarget) return

    const unitType = this.unitTypeTarget.value

    if (this.hasFixedAmountTarget) {
      this.fixedAmountTarget.classList.toggle("hidden", unitType !== "fixed")
    }

    if (this.hasOvertimeHoursTarget) {
      this.overtimeHoursTarget.classList.toggle("hidden", unitType !== "overtime")
    }
  }
}
