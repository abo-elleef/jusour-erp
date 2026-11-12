import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tipInput", "tipHidden", "terminalStatus", "deliveryFee", "due", "amount"]
  static values = { orderTotal: Number, baseDue: Number, dueTemplate: String }

  // Runs for any of the payment forms (submit events bubble to the modal root).
  addDeliveryFee(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return
    // The form that saves the fee on its own has its own fee field.
    if (!form.querySelector('input[name="payment_method"]')) return
    form.querySelectorAll("input[data-delivery-fee]").forEach((el) => el.remove())

    // The delivery fee is typed once at the top and rides along with whichever
    // payment is submitted. A staff meal is charged the order as it stands.
    const method = form.querySelector('input[name="payment_method"]')?.value
    if (this.hasDeliveryFeeTarget && method !== "staff_deduction") {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "delivery_fee_pounds"
      input.value = (this.deliveryFeeCents() / 100).toFixed(2)
      input.dataset.deliveryFee = "1"
      form.appendChild(input)
    }
  }

  deliveryFeeCents() {
    if (!this.hasDeliveryFeeTarget) return 0
    const pounds = parseFloat(this.deliveryFeeTarget.value)
    return Number.isFinite(pounds) && pounds > 0 ? Math.round(pounds * 100) : 0
  }

  // Re-prices the amount due and refills every payment amount as the fee is typed.
  updateDeliveryFee() {
    if (!this.hasDeliveryFeeTarget) return
    const dueCents = this.baseDueValue + this.deliveryFeeCents()
    const pounds = dueCents / 100
    this.amountTargets.forEach((input) => { input.value = pounds.toFixed(2) })
    if (this.hasDueTarget && this.dueTemplateValue) {
      const formatted = pounds.toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
      this.dueTarget.textContent = this.dueTemplateValue.replace("__N__", formatted)
    }
  }

  setTip(event) {
    const pct = parseInt(event.currentTarget.dataset.percent, 10)
    const total = this.orderTotalValue || 0
    const tipCents = Math.round(total * pct / 100)
    if (this.hasTipInputTarget) this.tipInputTarget.value = (tipCents / 100).toFixed(2)
    if (this.hasTipHiddenTarget) this.tipHiddenTarget.value = tipCents
  }

  syncTip(event) {
    const pounds = parseFloat(event.target.value) || 0
    if (this.hasTipHiddenTarget) this.tipHiddenTarget.value = Math.round(pounds * 100)
  }

  orderId() {
    return this.element.querySelector('input[name="order_id"]')?.value
  }

  async submitCash(event) {
    if (navigator.onLine) return

    event.preventDefault()
    const form = event.target
    const orderId = form.querySelector('input[name="order_id"]')?.value
    const amountPounds = form.querySelector('input[name="amount_pounds"]')?.value
    const amountCents = Math.round((parseFloat(amountPounds) || 0) * 100)
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
      if (!response.ok) {
        // The server refuses with a reason the cashier can act on (e.g. missing table number).
        const refusal = await response.json().catch(() => ({}))
        const error = new Error(refusal.error || "Stripe unavailable")
        error.refusal = Boolean(refusal.error)
        throw error
      }
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
            tip_cents: this.tipHiddenTarget?.value || 0,
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
        this.terminalStatusTarget.textContent = e.refusal ? e.message : "Terminal unavailable. Check Stripe keys or use cash."
      }
    }
  }
}
