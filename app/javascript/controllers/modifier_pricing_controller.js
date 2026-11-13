import { Controller } from "@hotwired/stimulus"
import { priceFor, priceWithOption } from "utils/modifier_pricing"
import { formatMoney } from "utils/offline_totals"

// Customize modal (POS and offline POS): keeps the price beside every choice,
// the header and the add button showing the full item price for what is picked.
export default class extends Controller {
  static values = { config: Object }
  static targets = ["total", "buttonTotal", "quantity"]

  connect() {
    this.refresh()
  }

  selectedIds() {
    return [...this.element.querySelectorAll("input[data-modifier-option]:checked")].map((input) => input.value)
  }

  refresh() {
    const config = this.configValue
    const selected = this.selectedIds()

    for (const group of config.groups) {
      for (const modifier of group.modifiers) {
        const slot = this.element.querySelector(`[data-modifier-price="${modifier.id}"]`)
        if (slot) slot.innerHTML = this.priceHtml(priceWithOption(config, selected, group, modifier.id), "text-sm")
      }
    }

    const current = priceFor(config, selected)
    this.totalTargets.forEach((el) => { el.innerHTML = this.priceHtml(current, "text-lg") })
    // The add button shows the line total: unit price × the typed count.
    const lineTotal = formatMoney(current.final * this.quantity())
    this.buttonTotalTargets.forEach((el) => { el.textContent = lineTotal })
  }

  // Optional count field (online POS only); missing, blank or junk counts as 1.
  quantity() {
    if (!this.hasQuantityTarget) return 1
    const n = parseInt(this.quantityTarget.value, 10)
    return n > 0 ? n : 1
  }

  priceHtml({ list, discount, final }, size) {
    const now = `<span class="${size} font-bold ${discount ? "text-rose-700" : "text-gray-900"}">${formatMoney(final)}</span>`
    if (!discount) return now
    return `<span class="text-xs text-gray-400 line-through">${formatMoney(list)}</span> ${now}`
  }
}
