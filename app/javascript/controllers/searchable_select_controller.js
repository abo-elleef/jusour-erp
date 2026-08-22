import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hidden"]
  static values = { placeholder: String, clearOnEmpty: { type: Boolean, default: false } }

  connect() {
    // The <ul> menu ships inside the element but is moved to <body> so it isn't
    // clipped by overflow:hidden ancestors. That move mutates the DOM, which can
    // make a parent controller's MutationObserver (stock-transfer-lines,
    // nested-line-sortable) trigger a disconnect/connect cycle on this element —
    // and disconnect() destroys the menu.
    //
    // So connect() has to cope with the menu being absent and build a fresh one.
    // Previously it bailed out in that case, leaving a control with no menu and no
    // listeners: permanently unsearchable. It bit whichever row connected while the
    // parent was still initialising, i.e. the first line, which is why adding a row
    // and deleting the first one "fixed" it.
    if (this._connected && this.menu && document.body.contains(this.menu)) {
      // Genuine double-connect on a healthy instance — nothing to rebuild.
      this.syncInputFromSelected()
      return
    }

    this.highlightIndex = -1
    this.teardownListeners()
    this.menu = this.adoptMenu() || this.buildMenu()

    this.boundCloseOnOutside = this.closeOnOutsideClick.bind(this)
    this.boundRepositionMenu = this.repositionMenu.bind(this)
    this.boundHandleMenuMouseDown = this.handleMenuMouseDown.bind(this)

    this.menu.addEventListener("mousedown", this.boundHandleMenuMouseDown)
    document.addEventListener("click", this.boundCloseOnOutside)
    window.addEventListener("resize", this.boundRepositionMenu)
    window.addEventListener("scroll", this.boundRepositionMenu, true)

    this._connected = true
    this.syncInputFromSelected()
  }

  // Take the server-rendered <ul> out to <body>, if it is still there.
  adoptMenu() {
    const inElement = this.element.querySelector("[data-searchable-select-target='menu']")
    if (!inElement) return null

    document.body.appendChild(inElement)
    return inElement
  }

  // Recreate it when a previous disconnect already destroyed it. Mirrors the markup
  // in shared/_searchable_select.html.erb.
  buildMenu() {
    const menu = document.createElement("ul")
    menu.setAttribute("data-searchable-select-target", "menu")
    menu.setAttribute("role", "listbox")
    menu.className = "hidden overflow-auto rounded-xl border border-gray-200 bg-white shadow-lg py-1"
    document.body.appendChild(menu)
    return menu
  }

  teardownListeners() {
    if (this.boundHandleMenuMouseDown && this.menu) {
      this.menu.removeEventListener("mousedown", this.boundHandleMenuMouseDown)
    }
    if (this.boundCloseOnOutside) document.removeEventListener("click", this.boundCloseOnOutside)
    if (this.boundRepositionMenu) {
      window.removeEventListener("resize", this.boundRepositionMenu)
      window.removeEventListener("scroll", this.boundRepositionMenu, true)
    }
  }

  disconnect() {
    this.teardownListeners()
    if (this.menu) this.menu.remove()
    this.menu = null
    this._connected = false
  }

  get options() {
    const parent = this.element.closest("[data-searchable-select-options]")
    if (!parent) return []

    try {
      return JSON.parse(parent.dataset.searchableSelectOptions || "[]")
    } catch {
      return []
    }
  }

  syncInputFromSelected() {
    const selected = this.hiddenTarget.value
    const match = this.options.find((option) => String(option.value) === String(selected))
    this.inputTarget.value = match ? match.label : ""
  }

  filter() {
    if (this.clearOnEmptyValue && this.inputTarget.value.trim() === "") {
      this.hiddenTarget.value = ""
      this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    }
    this.open()
    this.renderOptions(this.inputTarget.value)
  }

  open() {
    this.menu.classList.remove("hidden")
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.renderOptions(this.inputTarget.value)
    this.repositionMenu()
  }

  close() {
    this.menu.classList.add("hidden")
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.highlightIndex = -1
    this.syncInputFromSelected()
  }

  closeOnOutsideClick(event) {
    if (this.element.contains(event.target) || this.menu.contains(event.target)) return

    this.close()
  }

  repositionMenu() {
    if (this.menu.classList.contains("hidden")) return

    const rect = this.inputTarget.getBoundingClientRect()
    const maxHeight = 224
    const gap = 4
    const spaceBelow = window.innerHeight - rect.bottom - gap
    const spaceAbove = rect.top - gap
    const openAbove = spaceBelow < 160 && spaceAbove > spaceBelow
    const availableHeight = Math.max(120, openAbove ? spaceAbove : spaceBelow)

    this.menu.style.position = "fixed"
    this.menu.style.left = `${rect.left}px`
    this.menu.style.width = `${rect.width}px`
    this.menu.style.maxHeight = `${Math.min(maxHeight, availableHeight)}px`
    this.menu.style.zIndex = "60"

    if (openAbove) {
      this.menu.style.top = "auto"
      this.menu.style.bottom = `${window.innerHeight - rect.top + gap}px`
    } else {
      this.menu.style.top = `${rect.bottom + gap}px`
      this.menu.style.bottom = "auto"
    }
  }

  renderOptions(query = "") {
    const normalized = query.trim().toLowerCase()
    const filtered = this.options
      .filter((option) => {
        const haystack = `${option.label} ${option.keywords || ""}`.toLowerCase()
        return haystack.includes(normalized)
      })

    if (filtered.length === 0) {
      this.menu.innerHTML = `<li class="px-3 py-2 text-sm text-gray-500">${this.noResultsText}</li>`
      this.repositionMenu()
      return
    }

    const selected = this.hiddenTarget.value
    this.menu.innerHTML = filtered.map((option, index) => {
      const active = String(option.value) === String(selected)
      const aliasLine = option.aliases && option.aliases.length
        ? `<span class="block text-xs text-gray-400 truncate">${this.escapeHtml(option.aliases.join(" · "))}</span>`
        : ""
      return `<li role="option" data-value="${option.value}" data-index="${index}"
        class="cursor-pointer px-3 py-2 text-sm text-gray-900 hover:bg-amber-50 ${active ? "bg-amber-50/80 font-medium" : ""}">
        <span class="block truncate">${this.escapeHtml(option.label)}</span>${aliasLine}</li>`
    }).join("")

    this.repositionMenu()
  }

  handleMenuMouseDown(event) {
    const item = event.target.closest("[data-value]")
    if (!item) return

    event.preventDefault()
    this.setValue(item.dataset.value)
    this.close()
  }

  setValue(value) {
    const match = this.options.find((option) => String(option.value) === String(value))
    this.hiddenTarget.value = value
    this.inputTarget.value = match ? match.label : ""
    this.hiddenTarget.dispatchEvent(new Event("change", { bubbles: true }))
    this.element.dispatchEvent(new CustomEvent("searchable-select:change", { bubbles: true, detail: { value } }))
  }

  keydown(event) {
    if (!this.menu) return

    const items = this.menu.querySelectorAll("[data-value]")
    if (event.key === "ArrowDown") {
      event.preventDefault()
      if (this.menu.classList.contains("hidden")) this.open()
      this.highlightIndex = Math.min(this.highlightIndex + 1, items.length - 1)
      this.updateHighlight(items)
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.highlightIndex = Math.max(this.highlightIndex - 1, 0)
      this.updateHighlight(items)
    } else if (event.key === "Enter") {
      if (this.menu.classList.contains("hidden")) return

      event.preventDefault()
      const item = items[this.highlightIndex] || items[0]
      if (item) {
        this.setValue(item.dataset.value)
        this.close()
      }
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  updateHighlight(items) {
    items.forEach((item, index) => {
      item.classList.toggle("bg-amber-50", index === this.highlightIndex)
      item.classList.toggle("font-medium", index === this.highlightIndex)
    })
  }

  escapeHtml(text) {
    return text
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/"/g, "&quot;")
  }

  get noResultsText() {
    return this.element.dataset.searchableSelectNoResults || "No matches"
  }
}
