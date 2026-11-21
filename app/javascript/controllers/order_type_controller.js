import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "tableFields", "deliveryFields", "addressSelect", "deliveryAddress", "deliveryArea", "deliveryFee"]

  connect() {
    this.toggleFields()
  }

  selectType() {
    this.toggleFields()
    this.submitForm()
  }

  toggleFields() {
    const selected = this.formTarget.querySelector('input[name="order_type"]:checked')?.value
    if (this.hasTableFieldsTarget) {
      this.tableFieldsTarget.classList.toggle("hidden", selected !== "table")
    }
    if (this.hasDeliveryFieldsTarget) {
      this.deliveryFieldsTarget.classList.toggle("hidden", selected !== "delivery")
    }
  }

  submitForm() {
    this.formTarget.requestSubmit()
  }

  applySavedAddress(event) {
    if (!this.hasDeliveryAddressTarget) return

    const option = event.target.selectedOptions[0]
    const address = option?.value
    if (address) {
      this.deliveryAddressTarget.value = address
      this.submitForm()
    }
  }

  // Picking a delivery area (searchable select → hidden field change) fills in
  // its fee (the cashier may still edit it) and saves both. Clearing the area
  // leaves whatever fee is already typed.
  applyDeliveryArea(event) {
    const picker = event.target.closest("[data-searchable-select-options]")
    let options = []
    try { options = JSON.parse(picker?.dataset.searchableSelectOptions || "[]") } catch { options = [] }
    const area = options.find((option) => String(option.value) === String(event.target.value))
    if (area && this.hasDeliveryFeeTarget) {
      this.deliveryFeeTarget.value = area.fee
    }
    this.submitForm()
  }
}
