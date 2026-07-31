import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-gray-900", "text-white", "border-gray-900", "hover:bg-gray-800", "hover:text-white"]
const INACTIVE_CLASSES = ["bg-white", "text-gray-700", "border-gray-200", "hover:bg-stone-100", "hover:text-gray-800"]
const OFFERS_INACTIVE = ["bg-white", "text-rose-800", "border-rose-200", "hover:bg-rose-50", "hover:text-rose-900"]
const LEGACY_HOVER_CLASSES = ["hover:bg-gray-50"]

export default class extends Controller {
  static targets = ["offersSection", "menuGrid"]

  connect() {
    this.highlightCategory("all")
  }

  filterCategory(event) {
    const category = event.currentTarget.dataset.category
    document.querySelectorAll(".menu-card").forEach((card) => {
      const show = category === "all" || card.dataset.category === category
      card.classList.toggle("hidden", !show)
    })

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
        }
      }
    }
    document.getElementById("payment-modal")?.classList.remove("hidden")
  }

  closePayment() {
    document.getElementById("payment-modal")?.classList.add("hidden")
  }
}
