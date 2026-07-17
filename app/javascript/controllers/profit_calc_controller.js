import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["total", "share", "totalDisplay"]

  update() {
    const total = parseFloat(this.totalTarget.value) || 0
    this.shareTargets.forEach(el => {
      const pct = parseFloat(el.dataset.pct) || 0
      const share = (total * pct / 100)
      el.textContent = share > 0 ? "ج.م. " + share.toFixed(2) : "—"
    })
    this.totalDisplayTarget.textContent = total > 0 ? "ج.م. " + total.toFixed(2) : "—"
  }
}
