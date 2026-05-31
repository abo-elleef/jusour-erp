import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["modal", "input", "error", "form"]
  static values = {
    verifyUrl: { type: String, default: "/pos/verify_manager_pin" },
    actionType: String,
    recordId: String
  }

  open(event) {
    event.preventDefault()
    this.actionTypeValue = event.params.actionType || this.actionTypeValue
    this.recordIdValue = event.params.recordId || this.recordIdValue
    this.inputTarget.value = ""
    if (this.hasErrorTarget) this.errorTarget.textContent = ""
    this.modalTarget.classList.remove("hidden")
    this.inputTarget.focus()
  }

  close() {
    this.modalTarget.classList.add("hidden")
  }

  async verify(event) {
    event.preventDefault()
    const pin = this.inputTarget.value.trim()
    if (pin.length !== 4) return

    const response = await fetch(this.verifyUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("[name='csrf-token']")?.content,
        Accept: "application/json"
      },
      body: JSON.stringify({
        pin,
        action_type: this.actionTypeValue,
        record_id: this.recordIdValue
      })
    })

    const data = await response.json().catch(() => ({}))
    if (response.ok && data.success) {
      this.close()
      if (this.hasFormTarget) {
        const pinField = this.formTarget.querySelector("[name='pin']")
        if (pinField) pinField.value = pin
        this.formTarget.requestSubmit()
      }
    } else if (this.hasErrorTarget) {
      this.errorTarget.textContent = data.error || "Invalid PIN"
    }
  }
}
