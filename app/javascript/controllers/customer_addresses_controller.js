import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template"]

  add() {
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now())
    this.listTarget.insertAdjacentHTML("beforeend", content)
  }

  remove(event) {
    const row = event.target.closest("[data-customer-addresses-target='row']")
    const destroy = row.querySelector("[data-customer-addresses-target='destroy']")
    const idField = row.querySelector("input[name*='[id]']")

    if (idField?.value) {
      destroy.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
  }
}
