import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row", "debitTotal", "creditTotal", "balanceBadge", "submitBtn"]

  connect() {
    this.recalculate()
  }

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_LINE/g, Date.now())
    this.listTarget.insertAdjacentHTML("beforeend", content)
    // Focus the account select in the new row
    const rows = this.rowTargets
    const newRow = rows[rows.length - 1]
    newRow?.querySelector("select")?.focus()
    this.recalculate()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-journal-entry-lines-target='row']")
    if (this.rowTargets.length <= 2) return  // minimum 2 lines
    row.remove()
    this.recalculate()
  }

  // Called when debit field changes — clear credit on same row
  debitChanged(event) {
    const row = event.target.closest("[data-journal-entry-lines-target='row']")
    const credit = row.querySelector("[data-side='credit']")
    if (event.target.value && parseFloat(event.target.value) > 0) {
      credit.value = ""
      credit.disabled = true
    } else {
      credit.disabled = false
    }
    this.recalculate()
  }

  // Called when credit field changes — clear debit on same row
  creditChanged(event) {
    const row = event.target.closest("[data-journal-entry-lines-target='row']")
    const debit = row.querySelector("[data-side='debit']")
    if (event.target.value && parseFloat(event.target.value) > 0) {
      debit.value = ""
      debit.disabled = true
    } else {
      debit.disabled = false
    }
    this.recalculate()
  }

  recalculate() {
    let totalDebit = 0
    let totalCredit = 0

    this.rowTargets.forEach(row => {
      const debitVal = parseFloat(row.querySelector("[data-side='debit']")?.value) || 0
      const creditVal = parseFloat(row.querySelector("[data-side='credit']")?.value) || 0
      totalDebit += debitVal
      totalCredit += creditVal
    })

    const debitCents = Math.round(totalDebit * 100)
    const creditCents = Math.round(totalCredit * 100)
    const balanced = debitCents > 0 && debitCents === creditCents

    if (this.hasDebitTotalTarget)  this.debitTotalTarget.textContent  = this.fmt(debitCents)
    if (this.hasCreditTotalTarget) this.creditTotalTarget.textContent = this.fmt(creditCents)

    if (this.hasBalanceBadgeTarget) {
      const badge = this.balanceBadgeTarget
      if (debitCents === 0 && creditCents === 0) {
        badge.textContent = "—"
        badge.className = "text-xs px-3 py-1 rounded-full font-semibold bg-gray-100 text-gray-500 border border-gray-200"
      } else if (balanced) {
        badge.textContent = badge.dataset.labelBalanced || "Balanced ✓"
        badge.className = "text-xs px-3 py-1 rounded-full font-semibold bg-emerald-100 text-emerald-700 border border-emerald-200"
      } else {
        const diff = Math.abs(debitCents - creditCents)
        badge.textContent = `${badge.dataset.labelOff || "Off by"} ${this.fmt(diff)}`
        badge.className = "text-xs px-3 py-1 rounded-full font-semibold bg-red-100 text-red-700 border border-red-200"
      }
    }

    if (this.hasSubmitBtnTarget) {
      this.submitBtnTarget.disabled = !balanced
      this.submitBtnTarget.classList.toggle("opacity-50", !balanced)
      this.submitBtnTarget.classList.toggle("cursor-not-allowed", !balanced)
    }
  }

  fmt(cents) {
    return "ج.م. " + (cents / 100).toLocaleString("en-US", { minimumFractionDigits: 2 })
  }
}
