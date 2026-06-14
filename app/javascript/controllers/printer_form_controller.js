import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["connectionType", "networkFields", "printerType", "menuItemsSection"]
  static values = { productionTypes: { type: Array, default: ["kitchen", "bar"] } }

  connect() {
    this.toggleNetwork()
    this.toggleMenuItems()
  }

  toggleNetwork() {
    const isNetwork = this.connectionTypeTarget.value === "network"
    this.networkFieldsTarget.classList.toggle("hidden", !isNetwork)
  }

  toggleMenuItems() {
    if (!this.hasMenuItemsSectionTarget || !this.hasPrinterTypeTarget) return

    const isProduction = this.productionTypesValue.includes(this.printerTypeTarget.value)
    this.menuItemsSectionTarget.classList.toggle("hidden", !isProduction)
  }
}
