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
    this.networkFieldsTarget.classList.toggle("hidden", val !== "network")
    if (this.hasUsbFieldsTarget) {
      this.usbFieldsTarget.classList.toggle("hidden", val !== "usb")
    }
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
