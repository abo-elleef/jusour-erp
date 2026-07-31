import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-amber-100", "text-amber-950", "border-amber-300"]
const INACTIVE_CLASSES = ["bg-stone-50", "text-stone-700", "border-stone-200"]
const OFFERS_INACTIVE = ["bg-white", "text-rose-800", "border-rose-200"]

export default class extends Controller {
  static targets = ["offersSection", "menuGrid"]

  connect() {
    this.highlightCategory("all")
  }

  filterCategory(event) {
    const category = event.currentTarget.dataset.category
    document.querySelectorAll(".public-menu-card").forEach((card) => {
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
    document.querySelectorAll(".public-menu-category-btn").forEach((btn) => {
      btn.classList.remove(...ACTIVE_CLASSES, ...INACTIVE_CLASSES, ...OFFERS_INACTIVE)
      if (btn.dataset.category === "offers") {
        btn.classList.add(...OFFERS_INACTIVE)
      } else {
        btn.classList.add(...INACTIVE_CLASSES)
      }
    })
    const active = activeButton || document.querySelector(`.public-menu-category-btn[data-category="${category}"]`)
    if (active) {
      active.classList.remove(...INACTIVE_CLASSES, ...OFFERS_INACTIVE)
      active.classList.add(...ACTIVE_CLASSES)
    }
  }
}
