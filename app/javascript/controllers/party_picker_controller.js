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

    if (!showSearch) this.closeSearchMenu()

    if (showSearch) {
      const filtered = this.optionsValue.filter((option) => option.value.startsWith(`${type}:`))
      this.searchWrapTarget.dataset.searchableSelectOptions = JSON.stringify(filtered)
    }

    if (!resetSelection) return

    this.clearSearchSelection()
    if (!showSearch) return

    // Deferred on purpose: unhiding searchWrap and swapping its options
    // attribute can trigger a disconnect/reconnect of the nested
    // searchable-select controller (it warns about exactly this in its own
    // connect() — a parent's DOM mutation tearing down and rebuilding its
    // listeners). Focusing in the same tick can fire before the new instance's
    // "focus->searchable-select#open" listener is attached, leaving the field
    // focused but the dropdown never opening until some later event (like
    // typing) hits a since-reconnected instance. A macrotask delay — after any
    // pending MutationObserver callback has run — makes focus() land on a
    // listener that's actually there.
    setTimeout(() => this.focusSearch(), 0)
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

  // searchable-select moves its own menu out to <body> on connect (see its
  // own comment on why), so it's no longer a descendant of searchWrap by the
  // time we hide that — hiding searchWrap alone leaves an open menu stranded
  // and visible. Nothing else in this form has a reason to have one open at
  // the same time, so closing every visible one is safe.
  closeSearchMenu() {
    document.querySelectorAll('[data-searchable-select-target="menu"]:not(.hidden)')
      .forEach((menu) => menu.classList.add("hidden"))
    const input = this.searchWrapTarget.querySelector("[data-searchable-select-target='input']")
    input?.setAttribute("aria-expanded", "false")
  }
}
