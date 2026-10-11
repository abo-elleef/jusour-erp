import { Controller } from "@hotwired/stimulus"

const OPEN_MODULE_KEY = "admin-sidebar:open-module"
const MODULE_OPENED_EVENT = "nested-nav:module-opened"

// Accordion for a sidebar module (Inventory / Accounting / Settings): module
// header toggles open/closed, every item beneath it is flat and immediately
// clickable. Only one module is ever expanded sidebar-wide — opening one
// collapses whichever other module was open, whether it was just opened (via
// the module-opened event, for instances already connected) or is left over
// from browsing before this page loaded (via the shared sessionStorage key,
// checked on connect). Server-side "active" is authoritative: the module the
// current page actually belongs to always wins and claims the shared key,
// overriding any stale client-side state from a previous page.
export default class extends Controller {
  static targets = ["modulePanel", "moduleChevron"]
  static values = {
    key: String,
    open: { type: Boolean, default: false }
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

  // ── private ──────────────────────────────────────────────────

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
}
