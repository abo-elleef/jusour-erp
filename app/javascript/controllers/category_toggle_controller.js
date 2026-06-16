import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["checkbox", "availableField"]

  toggle() {
    this.availableFieldTarget.value = this.checkboxTarget.checked
    this.element.requestSubmit()
  }
}
