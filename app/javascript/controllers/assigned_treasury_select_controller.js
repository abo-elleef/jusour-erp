import { Controller } from "@hotwired/stimulus"

// Syncs the treasury select to the cashier's assigned drawer when the user changes.
export default class extends Controller {
  static targets = ["user", "treasury"]

  connect() {
    this.sync()
  }

  sync() {
    if (!this.hasUserTarget || !this.hasTreasuryTarget) return

    const option = this.userTarget.selectedOptions[0]
    const treasuryId = option?.dataset?.assignedTreasuryId
    if (treasuryId) {
      this.treasuryTarget.value = treasuryId
    }
  }
}
