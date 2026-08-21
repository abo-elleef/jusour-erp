import { Controller } from "@hotwired/stimulus"

// Bulk expand/collapse for a set of native <details> sections.
//
// The sections themselves need no JS — <details> handles individual toggling and
// keyboard access on its own. This only drives the "expand all / collapse all"
// controls, so the report still works fully if the JS never loads.
export default class extends Controller {
  static targets = ["section"]

  expandAll() {
    this.setAll(true)
  }

  collapseAll() {
    this.setAll(false)
  }

  setAll(open) {
    this.sectionTargets.forEach((section) => { section.open = open })
  }
}
