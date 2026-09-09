import { Controller } from "@hotwired/stimulus"

// Blocks a second submission of the same form, so a double click cannot dispatch
// the same goods twice. This is the comfort layer only — the server holds a
// one-shot token per send form and the unique index on it is what actually makes
// the operation safe. A guard that lives in the browser can always be bypassed
// by a slow network or a reloaded tab.
//
// Ordering matters where another controller also handles submit: list this one
// LAST in data-action. A guard that cancels the submit (the overage
// confirmation, say) leaves defaultPrevented set, and this bails out so its own
// deliberate re-submit still gets through.
export default class extends Controller {
  static targets = ["submit"]

  guard(event) {
    if (event.defaultPrevented) return

    if (this.element.dataset.submitted === "true") {
      event.preventDefault()
      return
    }
    this.element.dataset.submitted = "true"

    // Deferred: disabling a submit button while its own submit event is still
    // dispatching drops the button's name/value from the request.
    setTimeout(() => {
      this.submitTargets.forEach((button) => {
        button.disabled = true
        button.classList.add("opacity-60", "cursor-not-allowed")
      })
    }, 0)
  }
}
