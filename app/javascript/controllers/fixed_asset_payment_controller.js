import { Controller } from "@hotwired/stimulus"

// A treasury only means something when the asset is paid outright — on credit,
// nothing leaves until an installment is recorded, so the field is irrelevant.
export default class extends Controller {
  static targets = ["onCredit", "treasuryWrap"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasOnCreditTarget || !this.hasTreasuryWrapTarget) return

    this.treasuryWrapTarget.classList.toggle("hidden", this.onCreditTarget.checked)
  }
}
