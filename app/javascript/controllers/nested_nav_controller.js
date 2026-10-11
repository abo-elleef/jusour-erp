import { Controller } from "@hotwired/stimulus"

const OPEN_MODULE_KEY = "admin-sidebar:open-module"
const MODULE_OPENED_EVENT = "nested-nav:module-opened"

// Accordion for sidebar modules (Inventory / Accounting / Settings): module →
// groups → leaf links. Only one module is ever expanded sidebar-wide — opening
// one collapses whichever other module was open, whether it was just opened
// (via the module-opened event, for instances already connected) or is left
// over from browsing before this page loaded (via the shared sessionStorage
// key, checked on connect). Server-side "active" is authoritative: the module
// the current page actually belongs to always wins and claims the shared key,
// overriding any stale client-side state from a previous page.
export default class extends Controller {
  static targets = ["modulePanel", "moduleChevron", "groupPanel", "groupChevron", "groupButton"]
  static values = {
    key: String,
    open: { type: Boolean, default: false },
    openGroup: { type: String, default: "" }
  }

  connect() {
    if (this.openValue) {
      sessionStorage.setItem(OPEN_MODULE_KEY, this.keyValue)
    } else if (sessionStorage.getItem(OPEN_MODULE_KEY) === this.keyValue) {
      this.openValue = true
    }
    this.syncModule()

    this.boundCloseOnSiblingOpen = this.closeOnSiblingOpen.bind(this)
    document.addEventListener(MODULE_OPENED_EVENT, this.boundCloseOnSiblingOpen)

    const storedGroup = sessionStorage.getItem(this.groupStorageKey())
    const preferred = this.openGroupValue || storedGroup || ""
    this.openGroupKey = preferred
    this.syncGroups()
  }

  disconnect() {
    document.removeEventListener(MODULE_OPENED_EVENT, this.boundCloseOnSiblingOpen)
  }

  toggleModule(event) {
    event.preventDefault()
    this.openValue = !this.openValue
    if (this.openValue) {
      sessionStorage.setItem(OPEN_MODULE_KEY, this.keyValue)
      document.dispatchEvent(new CustomEvent(MODULE_OPENED_EVENT, { detail: { key: this.keyValue } }))
    } else if (sessionStorage.getItem(OPEN_MODULE_KEY) === this.keyValue) {
      sessionStorage.removeItem(OPEN_MODULE_KEY)
    }
    this.syncModule()
  }

  closeOnSiblingOpen(event) {
    if (event.detail.key === this.keyValue || !this.openValue) return

    this.openValue = false
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
