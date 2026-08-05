import { Controller } from "@hotwired/stimulus"

// Spreadsheet-style attendance grid: click a cell and type P/O/A/X, arrow-key
// navigate, shift-click a range then type to fill, and autosave in batches.
export default class extends Controller {
  static targets = ["cell", "summary", "count", "status", "popover", "popoverTitle", "otInput", "penaltyGroup", "table"]
  static values = {
    url: String,
    adjustmentUrl: String,
    symbols: Array,
    colors: Object,
    saving: String,
    saved: String,
    error: String
  }

  connect() {
    this.selected = []
    this.anchor = null
    this.pending = new Map()
    this.buffer = ""
    this.pinnedRow = null
    this.pinnedCol = null
    this.hoverRow = null
    this.hoverCol = null
    this.buildGrid()
    this.cellTargets.forEach((cell) => this.renderDots(cell))

    this.onClick = this.handleClick.bind(this)
    this.onKeydown = this.handleKeydown.bind(this)
    this.onContextMenu = this.handleContextMenu.bind(this)
    this.onDocDown = this.handleDocPointerDown.bind(this)
    this.onMouseOver = this.handleMouseOver.bind(this)
    this.onMouseOut = this.handleMouseOut.bind(this)
    this.element.addEventListener("click", this.onClick)
    this.element.addEventListener("keydown", this.onKeydown)
    this.element.addEventListener("contextmenu", this.onContextMenu)
    this.element.addEventListener("mouseover", this.onMouseOver)
    this.element.addEventListener("mouseout", this.onMouseOut)
    document.addEventListener("pointerdown", this.onDocDown)

    // Long-press for touch devices.
    this.onTouchStart = this.handleTouchStart.bind(this)
    this.onTouchEnd = this.handleTouchEnd.bind(this)
    this.element.addEventListener("touchstart", this.onTouchStart, { passive: true })
    this.element.addEventListener("touchend", this.onTouchEnd)
    this.element.addEventListener("touchmove", this.onTouchEnd)
  }

  disconnect() {
    this.element.removeEventListener("click", this.onClick)
    this.element.removeEventListener("keydown", this.onKeydown)
    this.element.removeEventListener("contextmenu", this.onContextMenu)
    this.element.removeEventListener("mouseover", this.onMouseOver)
    this.element.removeEventListener("mouseout", this.onMouseOut)
    this.element.removeEventListener("touchstart", this.onTouchStart)
    this.element.removeEventListener("touchend", this.onTouchEnd)
    this.element.removeEventListener("touchmove", this.onTouchEnd)
    document.removeEventListener("pointerdown", this.onDocDown)
    if (this.saveTimer) clearTimeout(this.saveTimer)
    if (this.longPressTimer) clearTimeout(this.longPressTimer)
  }

  buildGrid() {
    const rows = new Map()
    this.cellTargets.forEach((cell) => {
      const tr = cell.closest("tr")
      if (!rows.has(tr)) rows.set(tr, [])
      rows.get(tr).push(cell)
    })
    this.grid = [...rows.values()]
    this.pos = new Map()
    this.grid.forEach((row, r) => row.forEach((cell, c) => this.pos.set(cell, [r, c])))
  }

  handleClick(event) {
    const cell = event.target.closest(".attendance-cell")
    if (!cell) return
    if (event.shiftKey && this.anchor) {
      this.selectRange(this.anchor, cell)
    } else {
      // First click just selects; clicking an already-selected cell cycles it.
      const alreadySelected = this.selected.length === 1 && this.selected[0] === cell
      this.anchor = cell
      this.selectOnly(cell)
      if (alreadySelected) this.cycleCell(cell)
    }
    this.resetBuffer()
    cell.focus()
  }

  // Cycle a cell through the status symbols, then blank, and autosave —
  // shift-click still selects a range (for type-to-fill), keyboard is unchanged.
  cycleCell(cell) {
    const sequence = [...this.symbolsValue, ""]
    const current = cell.dataset.symbol || ""
    const index = sequence.indexOf(current)
    const next = sequence[(index + 1) % sequence.length]
    this.setCellSymbol(cell, next)
    this.scheduleSave()
  }

  handleKeydown(event) {
    const cell = event.target.closest(".attendance-cell")
    if (!cell) return

    const moves = { ArrowRight: [0, 1], ArrowLeft: [0, -1], ArrowUp: [-1, 0], ArrowDown: [1, 0] }
    if (moves[event.key]) {
      event.preventDefault()
      this.resetBuffer()
      const next = this.neighbor(cell, ...moves[event.key])
      if (next) {
        this.anchor = next
        this.selectOnly(next)
        next.focus()
      }
      return
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.pinnedRow = null
      this.pinnedCol = null
      this.hoverRow = null
      this.hoverCol = null
      this.clearSelectionRings()
      this.renderCrosshair()
      return
    }

    if (event.key === "Backspace" || event.key === "Delete") {
      event.preventDefault()
      this.resetBuffer()
      this.ensureSelected(cell)
      this.applyToSelection("")
      return
    }

    // Symbols may be multi-character (e.g. "PP"): buffer keystrokes so typing
    // P then P sets PP, while a single P still sets P immediately.
    if (event.key.length === 1 && /[a-z0-9]/i.test(event.key)) {
      const consumed = this.typeSymbol(cell, event.key.toUpperCase())
      if (consumed) event.preventDefault()
    }
  }

  typeSymbol(cell, char) {
    let candidate = this.buffer + char
    let matches = this.symbolsValue.filter((s) => s.startsWith(candidate))
    if (matches.length === 0) {
      candidate = char
      matches = this.symbolsValue.filter((s) => s.startsWith(candidate))
      if (matches.length === 0) return false
    }

    if (this.symbolsValue.includes(candidate)) {
      this.ensureSelected(cell)
      this.applyToSelection(candidate)
    }

    // Keep the buffer only if a longer symbol could still be completed (P → PP).
    const extendable = matches.some((s) => s.length > candidate.length)
    this.buffer = extendable ? candidate : ""
    this.armBufferReset()
    return true
  }

  resetBuffer() {
    this.buffer = ""
    if (this.bufferTimer) clearTimeout(this.bufferTimer)
  }

  armBufferReset() {
    if (this.bufferTimer) clearTimeout(this.bufferTimer)
    this.bufferTimer = setTimeout(() => { this.buffer = "" }, 900)
  }

  fillRowPresent(event) {
    const userId = event.currentTarget.dataset.userId
    const present = this.symbolsValue.includes("P") ? "P" : this.symbolsValue[0]
    if (!present) return
    const cells = this.cellTargets.filter((c) => c.dataset.userId === userId)
    cells.forEach((c) => this.setCellSymbol(c, present))
    this.scheduleSave()
  }

  // ── selection ──────────────────────────────────────────────
  ensureSelected(cell) {
    if (!this.selected.includes(cell)) this.selectOnly(cell)
  }

  selectOnly(cell) {
    this.setSelection([cell])
  }

  selectRange(anchor, target) {
    const [r1, c1] = this.pos.get(anchor)
    const [r2, c2] = this.pos.get(target)
    const cells = []
    for (let r = Math.min(r1, r2); r <= Math.max(r1, r2); r++) {
      for (let c = Math.min(c1, c2); c <= Math.max(c1, c2); c++) {
        const cell = this.grid[r] && this.grid[r][c]
        if (cell) cells.push(cell)
      }
    }
    this.setSelection(cells)
  }

  setSelection(cells) {
    this.selected.forEach((c) => c.classList.remove("ring-2", "ring-amber-400", "ring-inset"))
    this.selected = cells
    cells.forEach((c) => c.classList.add("ring-2", "ring-amber-400", "ring-inset"))
    if (cells.length === 1) {
      this.pinnedRow = cells[0].closest("tr")
      this.pinnedCol = cells[0].dataset.date
    }
    this.renderCrosshair()
  }

  pinColumn(event) {
    const date = event.currentTarget.dataset.date
    this.pinnedCol = this.pinnedCol === date ? null : date
    this.pinnedRow = null
    this.clearSelectionRings()
    this.renderCrosshair()
  }

  pinRow(event) {
    if (event.target.closest("a, button")) return
    const tr = event.currentTarget.closest("tr")
    this.pinnedRow = this.pinnedRow === tr ? null : tr
    this.pinnedCol = null
    this.clearSelectionRings()
    this.renderCrosshair()
  }

  clearSelectionRings() {
    this.selected.forEach((c) => c.classList.remove("ring-2", "ring-amber-400", "ring-inset"))
    this.selected = []
    this.anchor = null
  }

  handleMouseOver(event) {
    const dayHeader = event.target.closest("[data-attendance-day]")
    if (dayHeader) {
      this.hoverCol = dayHeader.dataset.date
      this.hoverRow = null
      this.renderCrosshair()
      return
    }

    const rowLabel = event.target.closest("[data-attendance-row-label]")
    if (rowLabel) {
      this.hoverRow = rowLabel.closest("tr")
      this.hoverCol = null
      this.renderCrosshair()
      return
    }

    const cell = event.target.closest(".attendance-cell")
    if (cell) {
      this.hoverRow = cell.closest("tr")
      this.hoverCol = cell.dataset.date
      this.renderCrosshair()
    }
  }

  handleMouseOut(event) {
    const next = event.relatedTarget
    const table = this.hasTableTarget ? this.tableTarget : this.element.querySelector(".attendance-grid-table")
    if (next && table?.contains(next)) return

    this.hoverRow = null
    this.hoverCol = null
    this.renderCrosshair()
  }

  renderCrosshair() {
    const table = this.hasTableTarget ? this.tableTarget : this.element.querySelector(".attendance-grid-table")
    if (!table) return

    table.querySelectorAll(".att-row-hl").forEach((el) => el.classList.remove("att-row-hl"))
    table.querySelectorAll(".att-col-hl").forEach((el) => el.classList.remove("att-col-hl"))

    const row = this.hoverRow || this.pinnedRow
    const col = this.hoverCol || this.pinnedCol
    if (!row && !col) return

    if (row) row.classList.add("att-row-hl")
    if (col) {
      table.querySelectorAll(`[data-attendance-col="${col}"]`).forEach((el) => el.classList.add("att-col-hl"))
    }
  }

  neighbor(cell, dr, dc) {
    const [r, c] = this.pos.get(cell)
    const row = this.grid[r + dr]
    return (row && row[c + dc]) || null
  }

  // ── mutation ───────────────────────────────────────────────
  applyToSelection(sym) {
    this.selected.forEach((cell) => this.setCellSymbol(cell, sym))
    this.scheduleSave()
  }

  setCellSymbol(cell, sym) {
    const old = cell.dataset.symbol
    if (old && this.colorsValue[old]) cell.classList.remove(...this.colorsValue[old].split(" "))
    if (sym && this.colorsValue[sym]) cell.classList.add(...this.colorsValue[sym].split(" "))
    cell.textContent = sym || ""
    cell.dataset.symbol = sym || ""
    this.renderDots(cell) // textContent wiped the dot spans — restore them
    this.pending.set(`${cell.dataset.userId}|${cell.dataset.date}`, {
      user_id: cell.dataset.userId,
      date: cell.dataset.date,
      symbol: sym || ""
    })
    this.updateCounts(cell.dataset.userId)
  }

  updateCounts(userId) {
    if (!this.hasCountTarget) return

    const counts = Object.fromEntries(this.symbolsValue.map((s) => [s, 0]))
    this.cellTargets.forEach((cell) => {
      if (cell.dataset.userId !== userId) return
      const sym = cell.dataset.symbol
      if (sym && counts[sym] !== undefined) counts[sym] += 1
    })
    this.countTargets.forEach((el) => {
      if (el.dataset.userId !== userId) return
      el.textContent = counts[el.dataset.symbol] || 0
    })
  }

  // ── save ───────────────────────────────────────────────────
  scheduleSave() {
    if (this.saveTimer) clearTimeout(this.saveTimer)
    this.saveTimer = setTimeout(() => this.save(), 400)
  }

  save() {
    if (this.pending.size === 0) return
    const cells = [...this.pending.values()]
    this.pending.clear()
    this.setStatus(this.savingValue)

    fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({ cells })
    })
      .then((r) => r.json())
      .then((data) => {
        if (data.ok) {
          this.applySummaries(data.summaries || {})
          this.setStatus(this.savedValue)
        } else {
          this.setStatus(this.errorValue)
        }
      })
      .catch(() => this.setStatus(this.errorValue))
  }

  applySummaries(summaries) {
    this.summaryTargets.forEach((el) => {
      const summary = summaries[el.dataset.userId]
      if (summary && summary[el.dataset.field] !== undefined) {
        el.textContent = summary[el.dataset.field]
      }
    })

    if (!this.hasCountTarget) return
    this.countTargets.forEach((el) => {
      const summary = summaries[el.dataset.userId]
      const counts = summary?.counts
      if (counts && counts[el.dataset.symbol] !== undefined) {
        el.textContent = counts[el.dataset.symbol]
      }
    })
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  // ── per-day adjustments popover (right-click / long-press) ─────
  handleContextMenu(event) {
    const cell = event.target.closest(".attendance-cell")
    if (!cell) return
    event.preventDefault()
    this.openPopover(cell)
  }

  handleTouchStart(event) {
    const cell = event.target.closest(".attendance-cell")
    if (!cell) return
    this.longPressTimer = setTimeout(() => this.openPopover(cell), 500)
  }

  handleTouchEnd() {
    if (this.longPressTimer) clearTimeout(this.longPressTimer)
  }

  handleDocPointerDown(event) {
    if (!this.hasPopoverTarget || this.popoverTarget.classList.contains("hidden")) return
    if (this.popoverTarget.contains(event.target)) return
    if (event.target.closest(".attendance-cell")) return
    this.closePopover()
  }

  openPopover(cell) {
    this.activeCell = cell
    const pop = this.popoverTarget

    const name = cell.closest("tr")?.querySelector("[data-staff-name]")?.textContent.trim() || ""
    if (this.hasPopoverTitleTarget) this.popoverTitleTarget.textContent = `${name} · ${cell.dataset.date}`
    if (this.hasOtInputTarget) this.otInputTarget.value = cell.dataset.otHours || ""
    this.activePenalty = cell.dataset.penaltyUnit || ""
    this.highlightPenalty(this.activePenalty)

    pop.classList.remove("hidden")
    const rect = cell.getBoundingClientRect()
    let left = rect.left
    let top = rect.bottom + 6
    if (left + pop.offsetWidth > window.innerWidth - 8) left = window.innerWidth - pop.offsetWidth - 8
    if (top + pop.offsetHeight > window.innerHeight - 8) top = rect.top - pop.offsetHeight - 6
    pop.style.left = `${Math.max(8, left)}px`
    pop.style.top = `${Math.max(8, top)}px`
    if (this.hasOtInputTarget) this.otInputTarget.focus()
  }

  closePopover() {
    if (this.hasPopoverTarget) this.popoverTarget.classList.add("hidden")
    this.activeCell = null
  }

  selectPenalty(event) {
    // Selection only — nothing is persisted until the Save button is clicked.
    this.activePenalty = event.currentTarget.dataset.penalty || ""
    this.highlightPenalty(this.activePenalty)
  }

  highlightPenalty(value) {
    if (!this.hasPenaltyGroupTarget) return
    this.penaltyGroupTarget.querySelectorAll(".attendance-penalty-btn").forEach((btn) => {
      const on = (btn.dataset.penalty || "") === (value || "")
      btn.classList.toggle("bg-gray-900", on)
      btn.classList.toggle("text-white", on)
      btn.classList.toggle("border-gray-900", on)
      // Keep the selected button dark on hover (the base hover:bg-gray-50 would
      // otherwise lighten the background under white text).
      btn.classList.toggle("hover:bg-gray-50", !on)
      btn.classList.toggle("hover:bg-gray-800", on)
    })
  }

  saveAdjustment() {
    const cell = this.activeCell
    if (!cell) return
    const overtime = this.hasOtInputTarget ? this.otInputTarget.value : ""
    this.setStatus(this.savingValue)

    fetch(this.adjustmentUrlValue, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": this.csrfToken()
      },
      body: JSON.stringify({
        user_id: cell.dataset.userId,
        date: cell.dataset.date,
        overtime_hours: overtime,
        penalty: this.activePenalty || ""
      })
    })
      .then((r) => r.json())
      .then((data) => {
        if (!data.ok) return this.setStatus(this.errorValue)
        cell.dataset.otHours = data.overtime_hours != null ? data.overtime_hours : ""
        cell.dataset.penaltyUnit = data.penalty_unit || ""
        if (this.hasOtInputTarget) this.otInputTarget.value = cell.dataset.otHours
        this.activePenalty = cell.dataset.penaltyUnit
        this.highlightPenalty(this.activePenalty)
        this.renderDots(cell)
        this.setStatus(this.savedValue)
        this.closePopover()
      })
      .catch(() => this.setStatus(this.errorValue))
  }

  renderDots(cell) {
    cell.querySelectorAll(".adj-dot").forEach((d) => d.remove())
    const mk = (color, pos) => {
      const s = document.createElement("span")
      s.className = "adj-dot"
      s.style.cssText = `position:absolute;width:6px;height:6px;border-radius:9999px;background:${color};${pos}`
      cell.appendChild(s)
    }
    const ot = cell.dataset.otHours
    if (ot && ot !== "" && parseFloat(ot) > 0) mk("#f59e0b", "top:2px;inset-inline-end:2px;")
    if (cell.dataset.penaltyUnit && cell.dataset.penaltyUnit !== "") mk("#f43f5e", "bottom:2px;inset-inline-end:2px;")
  }
}
