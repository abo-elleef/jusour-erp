import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-gray-900", "text-white", "border-gray-900"]
const INACTIVE_CLASSES = ["bg-white", "text-gray-700", "border-stone-200"]

export default class extends Controller {
  connect() {
    this.highlightCategory("all")
  }

  filterCategory(event) {
    const category = event.currentTarget.dataset.category
    document.querySelectorAll(".public-menu-card").forEach((card) => {
      const show = category === "all" || card.dataset.category === category
      card.classList.toggle("hidden", !show)
    })
    this.highlightCategory(category, event.currentTarget)
  }

  highlightCategory(category, activeButton) {
    document.querySelectorAll(".public-menu-category-btn").forEach((btn) => {
      btn.classList.remove(...ACTIVE_CLASSES, ...INACTIVE_CLASSES)
      btn.classList.add(...INACTIVE_CLASSES)
    })
    const active = activeButton || document.querySelector(`[data-category="${category}"]`)
    if (active) {
      active.classList.remove(...INACTIVE_CLASSES)
      active.classList.add(...ACTIVE_CLASSES)
    }
  }
}
