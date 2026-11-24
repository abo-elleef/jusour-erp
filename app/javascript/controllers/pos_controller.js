import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-gray-900", "text-white", "border-gray-900", "hover:bg-gray-800", "hover:text-white"]
const INACTIVE_CLASSES = ["bg-white", "text-gray-700", "border-gray-200", "hover:bg-stone-100", "hover:text-gray-800"]
const OFFERS_INACTIVE = ["bg-white", "text-rose-800", "border-rose-200", "hover:bg-rose-50", "hover:text-rose-900"]
const LEGACY_HOVER_CLASSES = ["hover:bg-gray-50"]

export default class extends Controller {
  static targets = ["offersSection", "topSellersSection", "menuGrid"]

  connect() {
    this.highlightCategory("all")
    this.openPaymentFromUrl()
  }

  // Back from the pickup phone popup on the Charge path: open the payment modal
  // through the Charge button, so the amounts are synced as on a normal F9.
  openPaymentFromUrl() {
    const url = new URL(window.location.href)
    if (url.searchParams.get("open_payment") !== "1") return
    url.searchParams.delete("open_payment")
    window.history.replaceState(window.history.state, "", url)
    const charge = document.querySelector("[data-pos-shortcut='charge']:not([disabled])")
    if (charge) setTimeout(() => charge.click(), 0)
  }

  filterCategory(event) {
    const category = event.currentTarget.dataset.category
    document.querySelectorAll(".menu-card").forEach((card) => {
      const show = category === "all" || card.dataset.category === category
      card.classList.toggle("hidden", !show)
    })

    // Top-seller cards repeat full-menu ones, so the row only shows under "All".
    if (this.hasTopSellersSectionTarget) {
      this.topSellersSectionTarget.classList.toggle("hidden", category !== "all")
    }

    if (this.hasOffersSectionTarget) {
      const showOffers = category === "all" || category === "offers"
      this.offersSectionTarget.classList.toggle("hidden", !showOffers)
    }

    if (this.hasMenuGridTarget) {
      const showMenu = category !== "offers"
      this.menuGridTarget.classList.toggle("hidden", !showMenu)
    }

    this.highlightCategory(category, event.currentTarget)
  }

  highlightCategory(category, activeButton) {
    document.querySelectorAll(".pos-category-btn").forEach((btn) => {
      btn.classList.remove(...ACTIVE_CLASSES, ...INACTIVE_CLASSES, ...OFFERS_INACTIVE, ...LEGACY_HOVER_CLASSES)
      if (btn.dataset.category === "offers") {
        btn.classList.add(...OFFERS_INACTIVE)
      } else {
        btn.classList.add(...INACTIVE_CLASSES)
      }
    })
    const active = activeButton || document.querySelector(`.pos-category-btn[data-category="${category}"]`)
    if (active) {
      active.classList.remove(...INACTIVE_CLASSES, ...OFFERS_INACTIVE)
      active.classList.add(...ACTIVE_CLASSES)
    }
  }

  openPayment(event) {
    // A pickup order at a branch that asks for the customer: the phone popup comes
    // first, and the register reopens on this modal afterwards (?open_payment=1).
    const pickupDialog = document.getElementById("pickup-customer-dialog")
    if (pickupDialog) {
      this.application.getControllerForElementAndIdentifier(pickupDialog, "pickup-customer")?.open("charge")
      return
    }
    const btn = event?.currentTarget
    if (btn) {
      const amountCents = parseInt(btn.dataset.amountCents, 10)
      const totalCents = parseInt(btn.dataset.totalCents, 10)

      if (!isNaN(amountCents)) {
        const modal = document.getElementById("payment-modal-content")
        if (modal) {
          // Sync the "Due: X" display text
          const dueEl = modal.querySelector("[data-payment-due]")
          if (dueEl && btn.dataset.dueText) dueEl.textContent = btn.dataset.dueText

          // Sync all amount_cents inputs (cash tender + gift card hidden)
          modal.querySelectorAll("input[name='amount_cents']").forEach(el => { el.value = amountCents })

          // Sync tip controller's order total value for percentage calculation
          if (!isNaN(totalCents)) {
            const paymentEl = modal.querySelector("[data-controller='payment']")
            if (paymentEl) paymentEl.dataset.paymentOrderTotalValue = totalCents
          }

          // A delivery fee typed before the modal was last closed still counts.
          const feeEl = modal.querySelector("[data-controller='payment']")
          const payment = feeEl && this.application.getControllerForElementAndIdentifier(feeEl, "payment")
          payment?.updateDeliveryFee()
        }
      }
    }
    document.getElementById("payment-modal")?.classList.remove("hidden")
    // A delivery order its branch will not charge without an area: start in the
    // area search (Enter picks, then the fee box; the cash amount is a Tab away).
    if (document.querySelector("#payment-modal [data-testid='payment-area-required']")) {
      const area = document.querySelector("#payment-modal [data-testid='payment-area-picker'] input[type='text']")
      if (area) {
        area.focus()
        return
      }
    }
    // Keyboard path: the cash amount is ready to type over; Enter then lands on
    // the highlighted Pay cash button (enter-next) and a second Enter pays.
    const cash = document.querySelector("#payment-modal input[name='amount_pounds']")
    if (cash) {
      cash.focus()
      cash.select()
    }
  }

  closePayment() {
    document.getElementById("payment-modal")?.classList.add("hidden")
  }
}
