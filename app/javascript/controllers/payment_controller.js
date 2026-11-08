import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["tipInput", "tipHidden", "terminalStatus", "printReceipt", "printProduction"]
  static values = { orderTotal: Number, kitchenSent: Boolean }

  // The modal is re-rendered on every cart change, so the print choices are restored
  // from this device's storage each time it connects.
  connect() {
    if (this.hasPrintReceiptTarget) {
      this.printReceiptTarget.checked = this.readChoice("receipt")
    }
    if (this.hasPrintProductionTarget) {
      // Tickets already went to the kitchen: default to not sending them again.
      this.printProductionTarget.checked = this.kitchenSentValue ? false : this.readChoice("production")
    }
  }

  readChoice(name) {
    try {
      return window.localStorage.getItem(`pos.print.${name}`) !== "0"
    } catch (_e) {
      return true
    }
  }

  writeChoice(name, on) {
    try {
      window.localStorage.setItem(`pos.print.${name}`, on ? "1" : "0")
    } catch (_e) { /* storage unavailable: the choice still applies to this sale */ }
  }

  rememberPrintChoices() {
    if (this.hasPrintReceiptTarget) this.writeChoice("receipt", this.printReceiptTarget.checked)
    // For an already-sent order the kitchen tick is a one-off, not a new default.
    if (this.hasPrintProductionTarget && !this.kitchenSentValue) {
      this.writeChoice("production", this.printProductionTarget.checked)
    }
  }

  // Runs for any of the payment forms (submit events bubble to the modal root).
  addPrintChoices(event) {
    const form = event.target
    if (!(form instanceof HTMLFormElement)) return
    form.querySelectorAll("input[data-print-choice]").forEach((el) => el.remove())
    const add = (name, target) => {
      if (!target) return
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = target.checked ? "1" : "0"
      input.dataset.printChoice = "1"
      form.appendChild(input)
    }
    add("print_receipt", this.hasPrintReceiptTarget ? this.printReceiptTarget : null)
    add("print_production", this.hasPrintProductionTarget ? this.printProductionTarget : null)
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
        this.terminalStatusTarget.textContent = "Terminal unavailable. Check Stripe keys or use cash."
      }
    }
  }
}
