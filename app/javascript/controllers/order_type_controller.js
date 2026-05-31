import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "tableFields", "deliveryFields", "addressSelect", "deliveryAddress"]

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
}
