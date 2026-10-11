import { Controller } from "@hotwired/stimulus"

// Global Cmd/Ctrl+K search over every page the current user can reach,
// flattened from the sidebar's module/group/tab hierarchy server-side (see
// ApplicationHelper#command_palette_items) so a known page is one search away
// regardless of how many accordion levels it sits behind.
export default class extends Controller {
  static targets = ["backdrop", "input", "list"]
  static values = { items: Array, noResults: String }

  connect() {
    this.highlightIndex = 0
    this.boundGlobalKeydown = this.handleGlobalKeydown.bind(this)
    document.addEventListener("keydown", this.boundGlobalKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.boundGlobalKeydown)
  }

  handleGlobalKeydown(event) {
    const key = event.key.toLowerCase()
    if ((event.metaKey || event.ctrlKey) && key === "k") {
      event.preventDefault()
      this.isOpen ? this.close() : this.open()
    } else if (event.key === "Escape" && this.isOpen) {
      this.close()
    }
  }

  open() {
    this.isOpen = true
    this.backdropTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
    this.inputTarget.value = ""
    this.highlightIndex = 0
    this.renderList("")
    requestAnimationFrame(() => this.inputTarget.focus())
  }

  close() {
    this.isOpen = false
    this.backdropTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  closeOnBackdrop(event) {
    if (event.target === event.currentTarget) this.close()
  }

  filter() {
    this.highlightIndex = 0
    this.renderList(this.inputTarget.value)
  }

  keydown(event) {
    const rows = Array.from(this.listTarget.querySelectorAll("[data-index]"))
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.highlightIndex = Math.min(this.highlightIndex + 1, rows.length - 1)
      this.updateHighlight(rows)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.highlightIndex = Math.max(this.highlightIndex - 1, 0)
      this.updateHighlight(rows)
    } else if (event.key === "Enter") {
      event.preventDefault()
      const row = rows[this.highlightIndex]
      if (row) this.visit(row.dataset.path)
    }
  }

  click(event) {
    const row = event.target.closest("[data-path]")
    if (row) this.visit(row.dataset.path)
  }

  visit(path) {
    this.close()
    if (window.Turbo) {
      window.Turbo.visit(path)
    } else {
      window.location.href = path
    }
  }

  renderList(query) {
    const normalized = query.trim().toLowerCase()
    const matches = this.itemsValue
      .filter((item) => `${item.label} ${item.group || ""}`.toLowerCase().includes(normalized))
      .slice(0, 50)

    if (matches.length === 0) {
      this.listTarget.innerHTML = `<li class="px-4 py-8 text-sm text-gray-500 text-center">${this.escapeHtml(this.noResultsValue)}</li>`
      return
    }

    this.listTarget.innerHTML = matches.map((item, index) => `
      <li role="option" data-index="${index}" data-path="${this.escapeHtml(item.path)}"
          class="flex items-center justify-between gap-3 px-3 py-2.5 rounded-lg cursor-pointer ${index === this.highlightIndex ? "bg-amber-50" : "hover:bg-gray-50"}">
        <span class="text-sm text-gray-900 truncate">${this.escapeHtml(item.label)}</span>
        ${item.group ? `<span class="text-xs text-gray-400 shrink-0 truncate max-w-[45%]">${this.escapeHtml(item.group)}</span>` : ""}
      </li>
    `).join("")
  }

  updateHighlight(rows) {
    rows.forEach((row, index) => {
      row.classList.toggle("bg-amber-50", index === this.highlightIndex)
      row.classList.toggle("hover:bg-gray-50", index !== this.highlightIndex)
    })
  }

  escapeHtml(text) {
    return String(text)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/"/g, "&quot;")
  }
}
