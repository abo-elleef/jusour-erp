import { Controller } from "@hotwired/stimulus"

// Expand / collapse groups of table rows. Each group is a <tbody> target with a
// header row (the toggle) and child rows marked data-row-groups-child. Groups
// start collapsed unless the tbody carries data-expanded="true".
export default class extends Controller {
  static targets = ["group"]

  connect() {
    this.groupTargets.forEach((group) => this.setGroup(group, group.dataset.expanded === "true"))
  }

  toggle(event) {
    // Clicks on the row's own controls (e.g. the copy-amount button) are not a toggle.
    const control = event.target.closest("button, a")
    if (control && !control.hasAttribute("aria-expanded")) return

    const group = event.currentTarget.closest("tbody")
    this.setGroup(group, group.dataset.expanded !== "true")
  }

  expandAll() {
    this.groupTargets.forEach((group) => this.setGroup(group, true))
  }

  collapseAll() {
    this.groupTargets.forEach((group) => this.setGroup(group, false))
  }

  setGroup(group, expanded) {
    group.dataset.expanded = expanded
    group.querySelectorAll("[data-row-groups-child]").forEach((row) => { row.hidden = !expanded })
    group.querySelectorAll("[data-row-groups-chevron]").forEach((icon) => {
      icon.classList.toggle("rotate-90", expanded)
    })
    group.querySelectorAll("[aria-expanded]").forEach((el) => el.setAttribute("aria-expanded", expanded))
  }
}
