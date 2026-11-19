import { Controller } from "@hotwired/stimulus"

// One "select all on this page" box for a list of row checkboxes.
export default class extends Controller {
  static targets = ["all", "item"]

  toggle() {
    this.itemTargets.forEach((box) => { box.checked = this.allTarget.checked })
  }

  sync() {
    if (!this.hasAllTarget) return
    this.allTarget.checked = this.itemTargets.length > 0 && this.itemTargets.every((box) => box.checked)
  }
}
