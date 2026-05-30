import { Controller } from "@hotwired/stimulus"

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
    document.querySelectorAll("[data-action*='filterCategory']").forEach((btn) => {
      btn.classList.remove("bg-amber-500", "text-white")
      btn.classList.add("bg-gray-200")
    })
    const active = activeButton || document.querySelector(`[data-category="${category}"]`)
    if (active) {
      active.classList.remove("bg-gray-200")
      active.classList.add("bg-amber-500", "text-white")
    }
  }

  openPayment() {
    document.getElementById("payment-modal")?.classList.remove("hidden")
  }

  closePayment() {
    document.getElementById("payment-modal")?.classList.add("hidden")
  }
}
