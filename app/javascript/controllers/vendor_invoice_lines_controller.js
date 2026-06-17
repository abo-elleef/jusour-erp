import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row", "unitLabel"]
  static values = { units: Object }

  connect() {
    this.rowTargets.forEach((row) => this.syncRowUnit(row))
  }

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now())
    this.listTarget.insertAdjacentHTML("beforeend", content)
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-vendor-invoice-lines-target='row']")
    const destroy = row.querySelector("[data-vendor-invoice-lines-target='destroy']")
    const idField = row.querySelector("input[name*='[id]']")

    if (idField?.value) {
      destroy.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
  }

  ingredientChanged(event) {
    const row = event.target.closest("[data-vendor-invoice-lines-target='row']")
    this.syncRowUnit(row, event.target.value)
  }

  syncRowUnit(row, ingredientId = null) {
    const label = row.querySelector("[data-vendor-invoice-lines-target='unitLabel']")
    if (!label) return

    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const id = ingredientId ?? hidden?.value
    label.textContent = id && this.unitsValue[id] ? this.unitsValue[id] : "—"
  }
}
