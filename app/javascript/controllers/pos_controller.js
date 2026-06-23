import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-gray-900", "text-white", "border-gray-900", "hover:bg-gray-800", "hover:text-white"]
const INACTIVE_CLASSES = ["bg-white", "text-gray-700", "border-gray-200", "hover:bg-stone-100", "hover:text-gray-800"]
const LEGACY_HOVER_CLASSES = ["hover:bg-gray-50"]

export default class extends Controller {
  connect() {
    this.highlightCategory("all")
  }

  filterCategory(event) {
    const category = event.currentTarget.dataset.category
    document.querySelectorAll(".menu-card").forEach((card) => {
      const show = category === "all" || card.dataset.category === category
      card.classList.toggle("hidden", !show)
    })
    this.highlightCategory(category, event.currentTarget)
  }

  highlightCategory(category, activeButton) {
    document.querySelectorAll(".pos-category-btn").forEach((btn) => {
      btn.classList.remove(...ACTIVE_CLASSES, ...INACTIVE_CLASSES, ...LEGACY_HOVER_CLASSES)
      btn.classList.add(...INACTIVE_CLASSES)
    })
    const active = activeButton || document.querySelector(`[data-category="${category}"]`)
    if (active) {
      active.classList.remove(...INACTIVE_CLASSES)
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
