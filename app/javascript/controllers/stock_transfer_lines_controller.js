import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row", "destroy", "unitSelect"]
  static values = { availableUnits: Object }

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now())
    this.listTarget.insertAdjacentHTML("beforeend", content)
  }

  // Repopulate a row's unit dropdown with the selected ingredient's units.
  ingredientChanged(event) {
    const row = event.target.closest("[data-stock-transfer-lines-target='row']")
    const select = row?.querySelector("[data-stock-transfer-lines-target='unitSelect']")
    if (!select) return

    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    const options = this.availableUnitsValue[hidden?.value] || []
    select.innerHTML = ""
    options.forEach(([label, value]) => {
      const opt = document.createElement("option")
      opt.value = value
      opt.textContent = label
      select.appendChild(opt)
    })
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-stock-transfer-lines-target='row']")
    const destroy = row.querySelector("[data-stock-transfer-lines-target='destroy']")
    const idField = row.querySelector("input[name*='[id]']")

    if (idField?.value) {
      destroy.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
  }
}
