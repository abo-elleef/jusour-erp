import { Controller } from "@hotwired/stimulus"

// Two steps instead of one flat searchable list: pick a type (Supplier,
// Customer, Partner, Loan, Staff — and "Other" where that's offered), then
// the search box underneath narrows to just that type. Reuses the existing
// searchable-select controller unchanged: it reads its options list from
// data-searchable-select-options lazily on every render, so swapping that
// attribute here is all a type change needs to do.
export default class extends Controller {
  static targets = ["typeSelect", "searchWrap", "otherWrap"]
  static values = { options: Array }

  connect() {
    // Match whatever the type select already shows (server-rendered on an
    // edit form, or after a failed submit) without waiting for a change event.
    this.applyType(this.typeSelectTarget.value)
  }

  selectType() {
    this.applyType(this.typeSelectTarget.value, true)
  }

  applyType(type, resetSelection = false) {
    const showOther = type === "__other__"
    const showSearch = type !== "" && !showOther

    if (this.hasOtherWrapTarget) this.otherWrapTarget.hidden = !showOther
    this.searchWrapTarget.hidden = !showSearch

    if (showSearch) {
      const filtered = this.optionsValue.filter((option) => option.value.startsWith(`${type}:`))
      this.searchWrapTarget.dataset.searchableSelectOptions = JSON.stringify(filtered)
    }

    if (resetSelection) {
      this.clearSearchSelection()
      if (showSearch) this.focusSearch()
    }
  }

  clearSearchSelection() {
    const hidden = this.searchWrapTarget.querySelector("[data-searchable-select-target='hidden']")
    if (!hidden) return

    hidden.value = ""
    hidden.dispatchEvent(new Event("change", { bubbles: true }))
    const input = this.searchWrapTarget.querySelector("[data-searchable-select-target='input']")
    if (input) input.value = ""
  }

  focusSearch() {
    this.searchWrapTarget.querySelector("[data-searchable-select-target='input']")?.focus()
  }
}
