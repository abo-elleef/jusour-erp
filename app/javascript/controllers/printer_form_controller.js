import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["connectionType", "networkFields", "usbFields", "printerType", "menuItemsSection"]
  static values = { productionTypes: { type: Array, default: ["kitchen", "bar"] } }

  connect() {
    this.toggleConnection()
    this.toggleMenuItems()
  }

  toggleConnection() {
    const val = this.connectionTypeTarget.value
    this.setSectionActive(this.networkFieldsTarget, val === "network")
    if (this.hasUsbFieldsTarget) {
      this.setSectionActive(this.usbFieldsTarget, val === "usb")
    }
  }

  // Both sections contain a printer[host] input. Hidden inputs are still
  // submitted, and the last one wins, so disable the inactive section's fields.
  setSectionActive(section, active) {
    section.classList.toggle("hidden", !active)
    section.querySelectorAll("input, select, textarea").forEach((el) => {
      el.disabled = !active
    })
  }

  // kept as alias so existing data-action="change->printer-form#toggleNetwork" still works
  toggleNetwork() {
    this.toggleConnection()
  }

  toggleMenuItems() {
    if (!this.hasMenuItemsSectionTarget || !this.hasPrinterTypeTarget) return

    const isProduction = this.productionTypesValue.includes(this.printerTypeTarget.value)
    this.menuItemsSectionTarget.classList.toggle("hidden", !isProduction)
  }
}
