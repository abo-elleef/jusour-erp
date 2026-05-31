import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tipInput", "tipHidden", "terminalStatus"]
  static values = { orderTotal: Number }

  setTip(event) {
    const pct = parseInt(event.currentTarget.dataset.percent, 10)
    const total = this.orderTotalValue || 0
    const tip = Math.round(total * pct / 100)
    if (this.hasTipInputTarget) this.tipInputTarget.value = tip
    if (this.hasTipHiddenTarget) this.tipHiddenTarget.value = tip
  }

  orderId() {
    return this.element.querySelector('input[name="order_id"]')?.value
  }

  async submitCash(event) {
    if (navigator.onLine) return

    event.preventDefault()
    const form = event.target
    const orderId = form.querySelector('input[name="order_id"]')?.value
    const amountCents = form.querySelector('input[name="amount_cents"]')?.value
    const tipCents = form.querySelector('input[name="tip_cents"]')?.value || 0

    const offline = this.application.getControllerForElementAndIdentifier(
      document.body,
      "offline-order"
    )
    if (!offline) return

    await offline.queuePayment({
      order_id: orderId,
      tip_cents: tipCents,
      payments_attributes: [{ payment_method: "cash", amount_cents: amountCents }]
    })

    const msg = offline.savedMessageValue
    if (msg) alert(msg)
    window.location.href = "/pos"
  }

  async payCard(event) {
    event.preventDefault()
    if (!navigator.onLine) {
      if (this.hasTerminalStatusTarget) {
        this.terminalStatusTarget.textContent = "Card payments require an internet connection."
      }
      return
    }
    if (this.hasTerminalStatusTarget) {
      this.terminalStatusTarget.textContent = "Connecting to Stripe Terminal..."
    }
    try {
      const body = JSON.stringify({ order_id: this.orderId() })
      const response = await fetch("/pos/payments/stripe_intent", {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
          "Accept": "application/json",
          "Content-Type": "application/json"
        },
        body: body
      })
      if (!response.ok) throw new Error("Stripe unavailable")
      const data = await response.json()
      if (this.hasTerminalStatusTarget) {
        this.terminalStatusTarget.textContent = "Processing card payment..."
      }
      if (data.payment_intent_id) {
        const capture = await fetch("/pos/payments/capture_stripe", {
          method: "POST",
          headers: {
            "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
            "Accept": "application/json",
            "Content-Type": "application/json"
          },
          body: JSON.stringify({
            payment_intent_id: data.payment_intent_id,
            tip_cents: this.tipInputTarget?.value || 0,
            order_id: this.orderId()
          })
        })
        if (capture.ok) {
          const result = await capture.json()
          window.location.href = result.redirect_url || window.location.href
        }
        else throw new Error("Capture failed")
      }
    } catch (e) {
      if (this.hasTerminalStatusTarget) {
        this.terminalStatusTarget.textContent = "Terminal unavailable. Check Stripe keys or use cash."
      }
    }
  }
}
