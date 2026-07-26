import { Controller } from "@hotwired/stimulus"

// Spreadsheet-style attendance grid: click a cell and type P/O/A/X, arrow-key
// navigate, shift-click a range then type to fill, and autosave in batches.
export default class extends Controller {
  static targets = ["cell", "summary", "status"]
  static values = {
    url: String,
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
    this.buildGrid()

    this.onClick = this.handleClick.bind(this)
    this.onKeydown = this.handleKeydown.bind(this)
    this.element.addEventListener("click", this.onClick)
    this.element.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    this.element.removeEventListener("click", this.onClick)
    this.element.removeEventListener("keydown", this.onKeydown)
    if (this.saveTimer) clearTimeout(this.saveTimer)
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
      this.anchor = cell
      this.selectOnly(cell)
    }
    this.resetBuffer()
    cell.focus()
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
    this.pending.set(`${cell.dataset.userId}|${cell.dataset.date}`, {
      user_id: cell.dataset.userId,
      date: cell.dataset.date,
      symbol: sym || ""
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
  }

  setStatus(text) {
    if (this.hasStatusTarget) this.statusTarget.textContent = text
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
