import { Controller } from "@hotwired/stimulus"

// Promo form: the "only with this choice" select lists the choices of the
// menu item picked above it, and hides when that item has no choices.
export default class extends Controller {
  static targets = ["select", "wrapper"]
  static values = { choices: Object, anyLabel: String }

  connect() {
    this.refresh()
  }

  refresh() {
    const itemId = this.element.querySelector("[name='menu_promo[menu_item_id]']")?.value
    const choices = this.choicesValue[itemId] || []
    const current = this.selectTarget.value

    this.selectTarget.replaceChildren(new Option(this.anyLabelValue, ""))
    choices.forEach(({ id, label }) => {
      this.selectTarget.add(new Option(label, id, false, id === current))
    })
    if (!choices.some(({ id }) => id === current)) this.selectTarget.value = ""

    this.wrapperTarget.hidden = choices.length === 0
  }
}
