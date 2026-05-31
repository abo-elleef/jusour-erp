import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["connectionType", "networkFields"]

  connect() {
    this.toggleNetwork()
  }

  toggleNetwork() {
    const isNetwork = this.connectionTypeTarget.value === "network"
    this.networkFieldsTarget.classList.toggle("hidden", !isNetwork)
  }
}
