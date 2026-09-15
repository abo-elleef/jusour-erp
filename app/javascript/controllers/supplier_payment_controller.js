import { Controller } from "@hotwired/stimulus"

// Live preview of how a lump-sum supplier payment will land on their open
// invoices — oldest first, same rule the server applies in
// Accounting::PaySupplierService. The user sees which invoices close and which
// one takes the partial before they commit, so no payment is a surprise.
//
// Mirrors server logic deliberately: this is a preview, never the source of
// truth. The server re-plans from scratch and rejects anything over the open
// total, so a stale page cannot overpay.
export default class extends Controller {
  static targets = ["amount", "row", "allocated", "state", "unallocated", "unallocatedWrap", "submit"]
  static values = { currency: String, settledLabel: String, partialLabel: String, untouchedLabel: String }

  connect() {
    this.allocate()
  }

  allocate() {
    let remaining = Math.round(parseFloat(this.amountTarget.value || "0") * 100)
    if (!Number.isFinite(remaining) || remaining < 0) remaining = 0

    this.rowTargets.forEach((row, index) => {
      const due = parseInt(row.dataset.dueCents, 10)
      const applied = Math.max(0, Math.min(remaining, due))
      remaining -= applied

      this.allocatedTargets[index].textContent = this.money(applied)
      this.paint(this.stateTargets[index], applied, due)
      row.classList.toggle("opacity-40", applied === 0)
    })

    // Anything left over has no invoice to land on. The server refuses it, so
    // say so here rather than letting the user submit into an error.
    this.unallocatedTarget.textContent = this.money(remaining)
    this.unallocatedWrapTarget.classList.toggle("hidden", remaining <= 0)
    if (this.hasSubmitTarget) this.submitTarget.disabled = remaining > 0
  }

  paint(el, applied, due) {
    el.className = "text-xs font-semibold px-2 py-0.5 rounded-full border"
    if (applied <= 0) {
      el.textContent = this.untouchedLabelValue
      el.classList.add("border-gray-200", "text-gray-400")
    } else if (applied >= due) {
      el.textContent = this.settledLabelValue
      el.classList.add("border-emerald-200", "bg-emerald-50", "text-emerald-700")
    } else {
      el.textContent = this.partialLabelValue
      el.classList.add("border-amber-200", "bg-amber-50", "text-amber-700")
    }
  }

  money(cents) {
    return (cents / 100).toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })
  }
}
