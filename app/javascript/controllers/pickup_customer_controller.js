import { Controller } from "@hotwired/stimulus"

// The pickup phone popup (pos/_pickup_customer_dialog). Opened by Place (F8) or
// Charge (F9) through open(next); Enter on the phone submits, Skip shows the
// reasons and keys 1-3 pick one.
export default class extends Controller {
  static targets = ["form", "next", "skipReason", "customerId", "phone", "name", "matchLine", "results", "phoneStep", "skipStep"]
  static values = { lookupUrl: String, matchedLabel: String, newLabel: String }

  connect() {
    this.searchHint // remember the hint text before any lookup replaces it
  }

  open(next) {
    this.nextTarget.value = next
    this.showPhone()
    if (!this.element.open) this.element.showModal()
    this.phoneTarget.focus()
  }

  showPhone() {
    this.skipReasonTarget.value = ""
    this.skipStepTarget.classList.add("hidden")
    this.phoneStepTarget.classList.remove("hidden")
    this.phoneTarget.focus()
  }

  showSkip() {
    this.phoneStepTarget.classList.add("hidden")
    this.skipStepTarget.classList.remove("hidden")
    // Focus stays inside the dialog, so keys 1-3 reach keydown (and Enter picks
    // the first reason).
    this.skipStepTarget.querySelector("[data-reason]")?.focus()
  }

  skip(event) {
    this.submitSkip(event.currentTarget.dataset.reason)
  }

  submitSkip(reason) {
    this.skipReasonTarget.value = reason
    this.customerIdTarget.value = ""
    this.phoneTarget.value = ""
    this.nameTarget.value = ""
    delete this.nameTarget.dataset.prefilled
    this.formTarget.requestSubmit()
  }

  keydown(event) {
    if (this.skipStepTarget.classList.contains("hidden")) return
    const buttons = this.skipStepTarget.querySelectorAll("[data-reason]")
    const index = parseInt(event.key, 10) - 1
    if (index >= 0 && index < buttons.length) {
      event.preventDefault()
      this.submitSkip(buttons[index].dataset.reason)
    }
  }

  // Search as the cashier types (4+ digits or 2+ letters, see
  // Customers::SearchController#render_phone_match). ↓/↑ move through the list;
  // Enter picks the highlighted one. With nothing highlighted, Enter goes on with
  // the typed number: the server reuses the exact match or makes a new customer.
  // A partial match is never picked on its own.
  lookup() {
    clearTimeout(this.timer)
    this.customerIdTarget.value = ""
    const query = this.phoneTarget.value.trim()
    const digits = query.replace(/[\s-]+/g, "")
    const searchable = /^\+?\d{4,}$/.test(digits) || (query.length >= 2 && !/\d/.test(query))
    if (!searchable) {
      this.showResults([])
      this.showMatch(undefined)
      return
    }
    this.timer = setTimeout(async () => {
      const url = new URL(this.lookupUrlValue, window.location.origin)
      url.searchParams.set("q", query)
      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const { exact, results } = await response.json()
      if (this.phoneTarget.value.trim() !== query) return
      this.showResults(results)
      // The match line only speaks for a full phone number.
      this.showMatch(/^\+?\d{8,}$/.test(digits) ? exact : undefined)
    }, 200)
  }

  // exact: a customer, null (a full number nobody has yet), or undefined (still
  // searching / not a phone).
  showMatch(exact) {
    if (exact === undefined) {
      this.matchLineTarget.textContent = this.searchHint
      this.matchLineTarget.className = "text-xs mt-1.5 min-h-4 text-stone-500"
    } else {
      this.matchLineTarget.textContent = exact ? `${this.matchedLabelValue}: ${exact.label}` : this.newLabelValue
      this.matchLineTarget.className = `text-xs mt-1.5 min-h-4 ${exact ? "text-emerald-700" : "text-stone-500"}`
    }
    if (exact?.name) {
      this.prefillName(exact.name)
    } else {
      this.clearPrefilledName()
    }
  }

  showResults(results) {
    this.results = results
    this.highlighted = -1
    this.resultsTarget.innerHTML = ""
    results.forEach((customer, index) => {
      const item = document.createElement("li")
      item.setAttribute("role", "option")
      item.dataset.index = index
      item.className = "flex justify-between gap-3 px-4 py-2.5 text-sm cursor-pointer hover:bg-stone-50"
      const name = document.createElement("span")
      name.className = "font-medium text-stone-900 truncate"
      name.textContent = customer.name || "—"
      const phone = document.createElement("span")
      phone.className = "tabular-nums text-stone-600 shrink-0"
      phone.dir = "ltr"
      phone.textContent = customer.phone
      item.append(name, phone)
      // mousedown, so the phone field keeps focus until the pick submits.
      item.addEventListener("mousedown", (event) => {
        event.preventDefault()
        this.pick(index)
      })
      this.resultsTarget.append(item)
    })
    this.resultsTarget.classList.toggle("hidden", results.length === 0)
  }

  phoneKeydown(event) {
    const count = this.results?.length || 0
    if (event.key === "ArrowDown" && count) {
      event.preventDefault()
      this.highlight(Math.min(this.highlighted + 1, count - 1))
    } else if (event.key === "ArrowUp" && count) {
      event.preventDefault()
      this.highlight(this.highlighted - 1)
    } else if (event.key === "Enter" && this.highlighted >= 0) {
      event.preventDefault()
      this.pick(this.highlighted)
    }
  }

  highlight(index) {
    this.highlighted = Math.max(index, -1)
    this.resultsTarget.querySelectorAll("[role=option]").forEach((item, i) => {
      const on = i === this.highlighted
      item.classList.toggle("bg-amber-100", on)
      item.classList.toggle("ring-2", on)
      item.classList.toggle("ring-inset", on)
      item.classList.toggle("ring-amber-400", on)
      item.setAttribute("aria-selected", on)
    })
  }

  // A picked customer carries on straight away, as Continue would.
  pick(index) {
    const customer = this.results[index]
    if (!customer) return
    this.customerIdTarget.value = customer.id
    this.phoneTarget.value = customer.phone
    if (customer.name) this.prefillName(customer.name)
    this.formTarget.requestSubmit()
  }

  get searchHint() {
    this._searchHint ??= this.matchLineTarget.textContent
    return this._searchHint
  }

  prefillName(name) {
    // A name the cashier typed themselves is never overwritten.
    if (this.nameTarget.value.trim() && this.nameTarget.dataset.prefilled !== "true") return
    this.nameTarget.value = name
    this.nameTarget.dataset.prefilled = "true"
  }

  // Typing in the name makes it the cashier's own.
  nameTyped() {
    delete this.nameTarget.dataset.prefilled
  }

  clearPrefilledName() {
    if (this.nameTarget.dataset.prefilled !== "true") return
    this.nameTarget.value = ""
    delete this.nameTarget.dataset.prefilled
  }
}
