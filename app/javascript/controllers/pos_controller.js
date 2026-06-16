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

  openPayment() {
    if (document.body.dataset.printAgentHealthy === "false") return
    document.getElementById("payment-modal")?.classList.remove("hidden")
  }

  closePayment() {
    document.getElementById("payment-modal")?.classList.add("hidden")
  }
}
