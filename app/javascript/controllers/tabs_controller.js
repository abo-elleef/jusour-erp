import { Controller } from "@hotwired/stimulus"

// Generic client-side tab switcher: one button per tab (data-tabs-name-param),
// one panel per tab (data-tab-panel), matched by name. No page reload.
//
// Remembers the last selected tab in localStorage (per storageKey value), so it
// survives a full page reload triggered by something else on the same page —
// e.g. applying a date range or a filter — instead of always resetting to the
// first tab.
export default class extends Controller {
  static targets = ["tab", "panel"]
  static values = { storageKey: String }

  connect() {
    const remembered = this.readStoredTab()
    const initial = this.tabTargets.find((tab) => tab.dataset.tabsNameParam === remembered) || this.tabTargets[0]
    if (initial) this.select(initial.dataset.tabsNameParam)
  }

  switch(event) {
    this.select(event.params.name)
  }

  select(name) {
    this.tabTargets.forEach((tab) => {
      const active = tab.dataset.tabsNameParam === name
      tab.classList.toggle("border-amber-600", active)
      tab.classList.toggle("text-amber-700", active)
      tab.classList.toggle("border-transparent", !active)
      tab.classList.toggle("text-gray-500", !active)
    })

    this.panelTargets.forEach((panel) => {
      panel.hidden = panel.dataset.tabPanel !== name
    })

    this.writeStoredTab(name)
  }

  readStoredTab() {
    if (!this.hasStorageKeyValue) return null

    try {
      return localStorage.getItem(this.storageName)
    } catch {
      return null
    }
  }

  writeStoredTab(name) {
    if (!this.hasStorageKeyValue) return

    try {
      localStorage.setItem(this.storageName, name)
    } catch {
      // private browsing, storage disabled, etc. — fine to just not remember
    }
  }

  get storageName() {
    return `tabs:${this.storageKeyValue}`
  }
}
