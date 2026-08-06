import { Controller } from "@hotwired/stimulus"

// Accordion for sidebar modules (Accounting / Inventory): module → groups → leaf links.
// Open state is restored from sessionStorage; server-side "active" forces the module open
// when the current page lives under that module.
export default class extends Controller {
  static targets = ["modulePanel", "moduleChevron", "groupPanel", "groupChevron", "groupButton"]
  static values = {
    key: String,
    open: { type: Boolean, default: false },
    openGroup: { type: String, default: "" }
  }

  connect() {
    if (!this.openValue) {
      const stored = sessionStorage.getItem(this.moduleStorageKey())
      if (stored === "1") this.openValue = true
    }
    this.syncModule()

    const storedGroup = sessionStorage.getItem(this.groupStorageKey())
    const preferred = this.openGroupValue || storedGroup || ""
    this.openGroupKey = preferred
    this.syncGroups()
  }

  toggleModule(event) {
    event.preventDefault()
    this.openValue = !this.openValue
    sessionStorage.setItem(this.moduleStorageKey(), this.openValue ? "1" : "0")
    this.syncModule()
  }

  toggleGroup(event) {
    event.preventDefault()
    const key = event.currentTarget.dataset.groupKey
    if (!key) return

    this.openGroupKey = this.openGroupKey === key ? "" : key
    sessionStorage.setItem(this.groupStorageKey(), this.openGroupKey)
    this.syncGroups()
  }

  // ── private ──────────────────────────────────────────────────

  moduleStorageKey() {
    return `admin-nested-nav:${this.keyValue}:open`
  }

  groupStorageKey() {
    return `admin-nested-nav:${this.keyValue}:group`
  }

  syncModule() {
    if (this.hasModulePanelTarget) {
      this.modulePanelTarget.classList.toggle("hidden", !this.openValue)
    }
    const rtl = document.documentElement.dir === "rtl"
    this.moduleChevronTargets.forEach((el) => {
      el.classList.remove("rotate-90", "rotate-180")
      if (this.openValue) {
        el.classList.add("rotate-90")
      } else if (rtl) {
        el.classList.add("rotate-180")
      }
    })
    const button = this.element.querySelector("[data-nested-nav-module-button]")
    if (button) button.setAttribute("aria-expanded", this.openValue ? "true" : "false")
  }

  syncGroups() {
    const rtl = document.documentElement.dir === "rtl"
    this.groupPanelTargets.forEach((panel) => {
      const key = panel.dataset.groupKey
      const open = key === this.openGroupKey
      panel.classList.toggle("hidden", !open)
    })
    this.groupButtonTargets.forEach((button) => {
      const key = button.dataset.groupKey
      const open = key === this.openGroupKey
      button.setAttribute("aria-expanded", open ? "true" : "false")
    })
    this.groupChevronTargets.forEach((el) => {
      const key = el.dataset.groupKey
      const open = key === this.openGroupKey
      el.classList.remove("rotate-90", "rotate-180")
      if (open) {
        el.classList.add("rotate-90")
      } else if (rtl) {
        el.classList.add("rotate-180")
      }
    })
  }
}
