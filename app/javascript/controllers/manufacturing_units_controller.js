import { Controller } from "@hotwired/stimulus"

// Populates unit dropdowns (output yield + each input line) with the selected
// ingredient's available units. Existing selections are left untouched on load;
// options are only rebuilt when an ingredient picker changes. Works with both a
// native <select> (change event) and the searchable-select combobox
// (searchable-select:change custom event carrying the value in event.detail).
export default class extends Controller {
  static targets = ["yieldUnit", "list", "template", "row"]
  static values = { units: Object }

  // Add a blank input line by cloning the template row (fresh index each time).
  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now())
    this.listTarget.insertAdjacentHTML("beforeend", content)
  }

  // Remove a line: persisted rows are flagged for destruction and hidden;
  // unsaved rows are dropped from the DOM entirely.
  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-manufacturing-units-target='row']")
    const idField = row.querySelector("input[name*='[id]']")

    if (idField?.value) {
      row.querySelector("[data-manufacturing-units-target='destroy']").value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }
  }

  outputChanged(event) {
    if (this.hasYieldUnitTarget) this.fill(this.yieldUnitTarget, this.ingredientIdFrom(event))
  }

  lineChanged(event) {
    const row = event.target.closest("[data-mfg-line]")
    const unitSelect = row?.querySelector("[data-mfg-line-unit]")
    if (unitSelect) this.fill(unitSelect, this.ingredientIdFrom(event))
  }

  ingredientIdFrom(event) {
    if (event.detail && event.detail.value != null) return event.detail.value
    return event.target.value
  }

  fill(select, ingredientId) {
    const options = this.unitsValue[ingredientId] || []
    select.innerHTML = ""
    options.forEach(([label, value]) => {
      const opt = document.createElement("option")
      opt.value = value
      opt.textContent = label
      select.appendChild(opt)
    })
  }
}
