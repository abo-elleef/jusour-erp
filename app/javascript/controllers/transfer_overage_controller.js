import { Controller } from "@hotwired/stimulus"

// The kitchen sends what is ready, which can be more than the branch asked for.
// That is allowed, but never silent: gate the submit on an explicit confirmation
// listing the affected lines, and only then set the flag the server needs to
// accept the overage.
export default class extends Controller {
  static targets = ["input", "flag"]
  static values = { message: String }

  confirm(event) {
    if (this.flagTarget.value === "1") return

    const over = this.inputTargets.filter((input) => {
      const pending = parseFloat(input.dataset.pending)
      const value = parseFloat(input.value)
      return Number.isFinite(pending) && Number.isFinite(value) && value > pending
    })
    if (over.length === 0) return

    event.preventDefault()

    const lines = over.map((input) => `• ${input.dataset.ingredient}: ${input.dataset.pending} → ${input.value}`)
    if (window.confirm(`${this.messageValue}\n\n${lines.join("\n")}`)) {
      this.flagTarget.value = "1"
      // Deferred: requestSubmit() is a no-op while the form is still dispatching
      // this submit event, so resubmitting inline would silently do nothing.
      setTimeout(() => this.element.requestSubmit(), 0)
    }
  }

  // Re-arm the confirmation whenever the numbers change, so an edit after a
  // confirmed overage is not waved through on the previous answer.
  reset() {
    this.flagTarget.value = "0"
  }
}
