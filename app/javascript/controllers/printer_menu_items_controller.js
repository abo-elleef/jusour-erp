import { Controller } from "@hotwired/stimulus"

// Printer form: menu items grouped by category, with a search box,
// a per-category "select all" checkbox and a live selected count.
export default class extends Controller {
  static targets = ["search", "group", "item", "groupToggle", "count", "empty"]
  static values = { countTemplate: String }

  connect() {
    this.refresh()
  }

  filter() {
    const query = this.normalize(this.searchTarget.value)

    let anyVisible = false
    this.groupTargets.forEach((group) => {
      const categoryMatches = query === "" || this.normalize(group.dataset.categoryName).includes(query)
      let groupVisible = false

      group.querySelectorAll("[data-printer-menu-items-target='item']").forEach((item) => {
        const show = categoryMatches || this.normalize(item.dataset.itemName).includes(query)
        item.classList.toggle("hidden", !show)
        if (show) groupVisible = true
      })

      group.classList.toggle("hidden", !groupVisible)
      if (groupVisible) anyVisible = true
    })

    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", anyVisible)
    this.refresh()
  }

  // Enter in the search box should not submit the printer form.
  ignoreEnter(event) {
    event.preventDefault()
  }

  // Ticks/unticks the items of a category that are visible under the current search.
  toggleGroup(event) {
    const group = event.target.closest("[data-printer-menu-items-target='group']")
    this.visibleCheckboxes(group).forEach((box) => { box.checked = event.target.checked })
    this.refresh()
  }

  refresh() {
    this.groupTargets.forEach((group) => {
      const toggle = group.querySelector("[data-printer-menu-items-target='groupToggle']")
      if (!toggle) return

      const boxes = this.visibleCheckboxes(group)
      const checked = boxes.filter((box) => box.checked).length
      toggle.checked = boxes.length > 0 && checked === boxes.length
      toggle.indeterminate = checked > 0 && checked < boxes.length

      const counter = group.querySelector("[data-group-count]")
      if (counter) {
        const all = this.checkboxes(group)
        counter.textContent = `${all.filter((box) => box.checked).length}/${all.length}`
      }
    })

    if (this.hasCountTarget) {
      const total = this.itemTargets.filter((item) => item.querySelector("input[type=checkbox]").checked).length
      this.countTarget.textContent = this.countTemplateValue.replace("%{count}", total)
    }
  }

  checkboxes(group) {
    return Array.from(group.querySelectorAll("[data-printer-menu-items-target='item'] input[type=checkbox]"))
  }

  visibleCheckboxes(group) {
    return this.checkboxes(group).filter((box) => !box.closest("[data-printer-menu-items-target='item']").classList.contains("hidden"))
  }

  // Case-insensitive, and forgiving of Arabic letter variants and diacritics.
  normalize(text) {
    return (text || "")
      .toLowerCase()
      .replace(/[ً-ْـ]/g, "")
      .replace(/[أإآ]/g, "ا")
      .replace(/ة/g, "ه")
      .replace(/ى/g, "ي")
      .trim()
  }
}
