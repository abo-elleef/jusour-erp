import { Controller } from "@hotwired/stimulus"
import { renderStreamMessage } from "@hotwired/turbo"

// Serialises all "Add item" form submissions so requests are sent one at a time.
// Without this, fast taps fire concurrent requests whose responses can arrive
// out-of-order and leave the cart total in a stale state.
//
// Usage: attach [data-controller="pos-queue"] to the element wrapping the menu
// grid. All button_to forms inside it are intercepted automatically.
export default class extends Controller {
  static targets = ["pendingBadge"]

  connect() {
    this._queue = []
    this._inflight = false

    // Capture form submissions from button_to buttons before Turbo sees them.
    this._onSubmit = this._intercept.bind(this)
    this.element.addEventListener("submit", this._onSubmit, true)
  }

  disconnect() {
    this.element.removeEventListener("submit", this._onSubmit, true)
  }

  // ── private ──────────────────────────────────────────────────────────────

  _intercept(event) {
    const form = event.target
    if (!this._isManagedForm(form)) return

    event.preventDefault()
    event.stopImmediatePropagation()

    // Snapshot the form data and submitter button at click time.
    const entry = {
      url: form.action,
      method: (form.method || "post").toUpperCase(),
      body: new FormData(form),
      button: form.querySelector("button[type='submit'], input[type='submit']"),
    }

    this._queue.push(entry)
    this._updateBadge()
    this._drain()
  }

  _isManagedForm(form) {
    // Only intercept forms that submit to the order_items endpoint.
    return form.action?.includes("order_items")
  }

  async _drain() {
    if (this._inflight || this._queue.length === 0) return

    this._inflight = true
    const entry = this._queue.shift()
    this._updateBadge()

    // Visually disable the source button while its request is in flight.
    if (entry.button) entry.button.disabled = true

    try {
      const resp = await fetch(entry.url, {
        method: entry.method,
        headers: {
          Accept: "text/vnd.turbo-stream.html, text/html, application/xhtml+xml",
          "X-CSRF-Token": this._csrf(),
        },
        body: entry.body,
        credentials: "same-origin",
      })

      if (resp.ok) {
        const contentType = resp.headers.get("content-type") || ""
        if (contentType.includes("turbo-stream")) {
          renderStreamMessage(await resp.text())
        }
      }
    } catch (_err) {
      // Network error — re-enable button so cashier can retry.
    } finally {
      if (entry.button) entry.button.disabled = false
      this._inflight = false
      this._updateBadge()
      // Process next item immediately.
      this._drain()
    }
  }

  _csrf() {
    return document.querySelector("meta[name='csrf-token']")?.content ?? ""
  }

  _updateBadge() {
    if (!this.hasPendingBadgeTarget) return
    const pending = this._queue.length + (this._inflight ? 1 : 0)
    this.pendingBadgeTarget.textContent = pending
    this.pendingBadgeTarget.classList.toggle("hidden", pending === 0)
  }
}
