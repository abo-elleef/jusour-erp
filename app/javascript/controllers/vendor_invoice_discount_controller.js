import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["type", "percentageField", "fixedField", "percentageInput", "fixedInput", "percentageWrap", "fixedWrap"]

  connect() {
    this.toggleFields()
  }

  typeChanged() {
    this.toggleFields()
  }

  toggleFields() {
    const type = this.typeTarget.value
    const isPercentage = type === "percentage"
    const isFixed = type === "fixed_amount"

    this.percentageWrapTarget.classList.toggle("hidden", !isPercentage)
    this.fixedWrapTarget.classList.toggle("hidden", !isFixed)

    if (this.hasPercentageInputTarget) {
      this.percentageInputTarget.disabled = !isPercentage
    }
    if (this.hasFixedInputTarget) {
      this.fixedInputTarget.disabled = !isFixed
    }
  }
}
