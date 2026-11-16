import { Controller } from "@hotwired/stimulus"

// A shared PIN (branch edit/void-orders, manager) must leave nothing a browser can
// offer back to the next person at the till. The box the user types into has no
// name and a random id, so form-autocomplete history has no key to file it under,
// and it is wiped when the form submits. The value travels in a hidden input,
// which browsers never record. See ApplicationHelper#pin_field_tag.
export default class extends Controller {
  static targets = ["input", "value"]

  connect() {
    this.form = this.element.closest("form")
    this.onSubmit = () => {
      this.sync()
      this.inputTarget.value = ""
    }
    // On the form itself, so it runs before Turbo's document-level listener reads it.
    this.form?.addEventListener("submit", this.onSubmit)
  }

  disconnect() {
    this.form?.removeEventListener("submit", this.onSubmit)
  }

  sync() {
    this.valueTarget.value = this.inputTarget.value
  }
}
