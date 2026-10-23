import { Controller } from "@hotwired/stimulus"

// Ingredient × location grid. "All locations" means every current and future
// location, so those rows show every box ticked. Unchecking one box turns that
// flag off and leaves the other locations checked — the ingredient stays
// available everywhere it was, minus the box you cleared. Column headers do
// the same for every row on the page.
export default class extends Controller {
  static targets = ["row", "column", "allColumn"]

  connect() {
    this.refreshHeaders()
  }

  toggleAll(event) {
    const row = event.target.closest("tr")
    this.applyAll(row, event.target.checked)
    this.mark(row)
    this.refreshHeaders()
  }

  toggleLocation(event) {
    const row = event.target.closest("tr")
    const all = this.allBox(row)
    if (all?.checked && !event.target.checked) {
      all.checked = false
      this.setImplied(row, false)
    }
    this.mark(row)
    this.refreshHeaders()
  }

  toggleAllColumn(event) {
    const on = event.target.checked
    this.rowTargets.forEach((row) => {
      const all = this.allBox(row)
      if (!all || all.checked === on) return

      all.checked = on
      this.applyAll(row, on)
      this.mark(row)
    })
    this.refreshHeaders()
  }

  toggleColumn(event) {
    const id = event.target.dataset.locationId
    const on = event.target.checked
    this.rowTargets.forEach((row) => {
      const all = this.allBox(row)
      const box = this.locationBox(row, id)
      if (!box) return

      let changed = false
      if (!on && all?.checked) {
        all.checked = false
        this.setImplied(row, false)
        changed = true
      }
      if (box.checked !== on) {
        box.checked = on
        changed = true
      }
      if (changed) this.mark(row)
    })
    this.refreshHeaders()
  }

  applyAll(row, on) {
    if (!row) return

    if (on) this.locationBoxes(row).forEach((box) => { box.checked = true })
    this.setImplied(row, on)
  }

  setImplied(row, on) {
    this.locationBoxes(row).forEach((box) => box.classList.toggle("opacity-50", on))
  }

  refreshHeaders() {
    if (this.hasAllColumnTarget) {
      const states = this.rowTargets.map((row) => this.allBox(row)?.checked)
      this.setHeader(this.allColumnTarget, states)
    }
    this.columnTargets.forEach((header) => {
      const states = this.rowTargets.map((row) => {
        if (this.allBox(row)?.checked) return true

        return this.locationBox(row, header.dataset.locationId)?.checked || false
      })
      this.setHeader(header, states)
    })
  }

  setHeader(header, states) {
    if (states.length === 0) return

    const allOn = states.every(Boolean)
    header.checked = allOn
    header.indeterminate = !allOn && states.some(Boolean)
  }

  mark(row) {
    if (!row) return

    row.classList.add("bg-amber-50/70")
    row.querySelector("[data-sticky]")?.classList.replace("bg-white", "bg-amber-50")
  }

  allBox(row) {
    return row?.querySelector("[data-role='all']")
  }

  locationBoxes(row) {
    return [...row.querySelectorAll("[data-role='location']")]
  }

  locationBox(row, id) {
    return this.locationBoxes(row).find((box) => box.value === id)
  }
}
