import { Controller } from "@hotwired/stimulus"

// Product page photo gallery: clicking a thumbnail swaps the main photo.
export default class extends Controller {
  static targets = ["main", "thumb"]

  show(event) {
    const thumb = event.currentTarget
    if (!this.hasMainTarget || !thumb.dataset.src) return

    this.mainTarget.src = thumb.dataset.src
    this.thumbTargets.forEach((el) => {
      const active = el === thumb
      el.classList.toggle("border-amber-600", active)
      el.classList.toggle("border-transparent", !active)
    })
  }
}
