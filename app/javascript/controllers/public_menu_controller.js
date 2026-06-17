import { Controller } from "@hotwired/stimulus"

const ACTIVE_CLASSES = ["bg-amber-100", "text-amber-950", "border-amber-300"]
const INACTIVE_CLASSES = ["bg-stone-50", "text-stone-700", "border-stone-200"]

export default class extends Controller {
  static targets = ["branchDrawer", "branchPanel"]

  connect() {
    this.highlightCategory("all")
    this.handleEscape = this.handleEscape.bind(this)
  }

  disconnect() {
    document.removeEventListener("keydown", this.handleEscape)
    document.body.classList.remove("overflow-hidden")
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

  openBranchDrawer(event) {
    event.preventDefault()
    if (!this.hasBranchDrawerTarget) return

    this.branchDrawerTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    document.addEventListener("keydown", this.handleEscape)

    if (this.hasBranchPanelTarget) {
      this.branchPanelTarget.classList.add("translate-y-full")
      requestAnimationFrame(() => {
        this.branchPanelTarget.classList.remove("translate-y-full")
      })
    }
  }

  closeBranchDrawer(event) {
    if (event) event.preventDefault()
    if (!this.hasBranchDrawerTarget) return

    const hide = () => {
      this.branchDrawerTarget.classList.add("hidden")
      document.body.classList.remove("overflow-hidden")
      document.removeEventListener("keydown", this.handleEscape)
    }

    if (this.hasBranchPanelTarget) {
      this.branchPanelTarget.classList.add("translate-y-full")
      setTimeout(hide, 280)
    } else {
      hide()
    }
  }

  handleEscape(event) {
    if (event.key === "Escape") this.closeBranchDrawer()
  }
}
