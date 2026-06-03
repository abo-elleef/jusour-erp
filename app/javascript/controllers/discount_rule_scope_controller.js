import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["appliesTo", "itemScope", "categoryScope"]

  connect() {
    this.update()
  }

  update() {
    const value = this.appliesToTarget.value
    this.itemScopeTarget.classList.toggle("hidden", value !== "item")
    this.categoryScopeTarget.classList.toggle("hidden", value !== "category")

    const itemSelect = this.itemScopeTarget.querySelector("select")
    const categorySelect = this.categoryScopeTarget.querySelector("select")
    if (itemSelect) itemSelect.disabled = value !== "item"
    if (categorySelect) categorySelect.disabled = value !== "category"
  }
}
