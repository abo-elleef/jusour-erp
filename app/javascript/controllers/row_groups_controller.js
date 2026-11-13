import { Controller } from "@hotwired/stimulus"

// Expand / collapse groups of table rows. Each group is a <tbody> target with a
// header row (the toggle) and child rows marked data-row-groups-child. Groups
// start collapsed unless the tbody carries data-expanded="true".
//
// A row can also open its own sub-rows: a row marked data-row-groups-item="key"
// (with click->row-groups#toggleItem) shows the rows marked
// data-row-groups-sub="key". Sub-rows inside a group stay hidden while that
// group is collapsed, and come back as they were when it opens.
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

  toggleItem(event) {
    const control = event.target.closest("button, a")
    if (control && !control.hasAttribute("data-row-groups-item-toggle")) return

    const row = event.currentTarget
    this.setItem(row, row.dataset.expanded !== "true")
  }

  expandAll() {
    this.itemRows().forEach((row) => this.setItem(row, true))
    this.groupTargets.forEach((group) => this.setGroup(group, true))
  }

  collapseAll() {
    this.itemRows().forEach((row) => this.setItem(row, false))
    this.groupTargets.forEach((group) => this.setGroup(group, false))
  }

  setGroup(group, expanded) {
    group.dataset.expanded = expanded
    group.querySelectorAll("[data-row-groups-child]").forEach((row) => { row.hidden = !expanded })
    group.querySelectorAll("[data-row-groups-chevron]").forEach((icon) => {
      icon.classList.toggle("rotate-90", expanded)
    })
    group.querySelectorAll("[aria-expanded]:not([data-row-groups-item-toggle])")
      .forEach((el) => el.setAttribute("aria-expanded", expanded))
    group.querySelectorAll("[data-row-groups-item]").forEach((row) => {
      this.showSubRows(row, expanded && row.dataset.expanded === "true")
    })
  }

  setItem(row, expanded) {
    row.dataset.expanded = expanded
    row.querySelectorAll("[data-row-groups-item-chevron]").forEach((icon) => {
      icon.classList.toggle("rotate-90", expanded)
    })
    row.querySelectorAll("[data-row-groups-item-toggle]").forEach((el) => el.setAttribute("aria-expanded", expanded))
    const group = row.closest("[data-row-groups-target~='group']")
    this.showSubRows(row, expanded && (!group || group.dataset.expanded === "true"))
  }

  showSubRows(row, visible) {
    this.element.querySelectorAll(`[data-row-groups-sub="${row.dataset.rowGroupsItem}"]`)
      .forEach((sub) => { sub.hidden = !visible })
  }

  itemRows() {
    return this.element.querySelectorAll("[data-row-groups-item]")
  }
}
