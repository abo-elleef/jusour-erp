import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "template", "row", "destroy", "unitSelect", "groupToggle"]
  static values = {
    availableUnits: Object,
    ingredientCategories: Object,
    uncategorized: { type: String, default: "Uncategorized" },
    grouped: { type: Boolean, default: false }
  }

  groupedValueChanged() {
    this.applyGrouping()
    this.updateToggleButtons()
  }

  toggleGrouping(event) {
    event.preventDefault()
    this.groupedValue = !this.groupedValue
  }

  applyGrouping() {
    if (!this.hasListTarget) return
    const grouped = this.groupedValue
    this.listTarget.querySelectorAll("[data-transfer-category-header]").forEach((h) => {
      h.classList.toggle("hidden", !grouped)
    })
  }

  updateToggleButtons() {
    if (!this.hasGroupToggleTarget) return
    const grouped = this.groupedValue
    this.groupToggleTargets.forEach((btn) => {
      const isGrouped = btn.dataset.groupedMode === "true"
      btn.classList.toggle("border-amber-500", isGrouped === grouped)
      btn.classList.toggle("bg-amber-50", isGrouped === grouped)
      btn.classList.toggle("text-amber-800", isGrouped === grouped)
      btn.classList.toggle("border-gray-200", isGrouped !== grouped)
      btn.classList.toggle("text-gray-600", isGrouped !== grouped)
    })
  }

  add(event) {
    event.preventDefault()
    const content = this.templateTarget.innerHTML.replace(/NEW_RECORD/g, Date.now())
    this.listTarget.insertAdjacentHTML("beforeend", content)
  }

  // Repopulate a row's unit dropdown with the selected ingredient's units,
  // then move the row under the matching category header.
  ingredientChanged(event) {
    const row = event.target.closest("[data-stock-transfer-lines-target='row']")
    if (!row) return

    const select = row.querySelector("[data-stock-transfer-lines-target='unitSelect']")
    const hidden = row.querySelector("input[name*='[ingredient_id]']")
    if (select) {
      const options = this.availableUnitsValue[hidden?.value] || []
      select.innerHTML = ""
      options.forEach(([label, value]) => {
        const opt = document.createElement("option")
        opt.value = value
        opt.textContent = label
        select.appendChild(opt)
      })
    }

    this.placeRowInCategory(row)
    this.refreshCategoryCounts()
  }

  remove(event) {
    event.preventDefault()
    const row = event.target.closest("[data-stock-transfer-lines-target='row']")
    const destroy = row.querySelector("[data-stock-transfer-lines-target='destroy']")
    const idField = row.querySelector("input[name*='[id]']")

    if (idField?.value) {
      destroy.value = "1"
      row.classList.add("hidden")
    } else {
      row.remove()
    }

    this.removeEmptyCategoryHeaders()
    this.refreshCategoryCounts()
  }

  placeRowInCategory(row) {
    if (!this.hasListTarget) return

    const ingredientId = row.querySelector("input[name*='[ingredient_id]']")?.value
    const meta = this.categoryMetaFor(ingredientId)
    const categoryKey = meta.id != null ? String(meta.id) : "uncategorized"

    let header = this.listTarget.querySelector(
      `[data-transfer-category-header][data-category-id="${CSS.escape(categoryKey)}"]`
    )
    if (!header) {
      header = this.buildCategoryHeader(categoryKey, meta.name, meta.position)
      this.insertCategoryHeader(header, meta.position, categoryKey)
      if (!this.groupedValue) header.classList.add("hidden")
    }

    if (this.rowBelongsToHeader(row, header)) return

    const anchor = this.lastVisibleRowInCategory(header) || header
    anchor.after(row)
    this.removeEmptyCategoryHeaders()
  }

  categoryMetaFor(ingredientId) {
    const meta = ingredientId ? this.ingredientCategoriesValue[ingredientId] : null
    if (meta) {
      return {
        id: meta.id ?? null,
        name: meta.name || this.uncategorizedValue,
        position: Number.isFinite(Number(meta.position)) ? Number(meta.position) : 999_999
      }
    }

    return { id: null, name: this.uncategorizedValue, position: 999_999 }
  }

  buildCategoryHeader(id, name, position) {
    const header = document.createElement("div")
    header.className =
      "px-5 py-2.5 bg-gray-100/90 border-y border-gray-200 text-xs font-semibold text-gray-600 uppercase tracking-wide sticky top-0 z-[1]"
    header.dataset.transferCategoryHeader = ""
    header.dataset.categoryId = id
    header.dataset.categoryPosition = String(position)

    header.append(document.createTextNode(`${name} `))

    const count = document.createElement("span")
    count.className = "font-normal text-gray-400 normal-case tracking-normal ms-1"
    count.dataset.transferCategoryCount = ""
    header.append(count)

    return header
  }

  insertCategoryHeader(header, position, categoryKey) {
    const headers = [...this.listTarget.querySelectorAll("[data-transfer-category-header]")]
    const next = headers.find((existing) => {
      const existingPos = Number(existing.dataset.categoryPosition)
      if (existingPos > position) return true
      if (existingPos === position && existing.dataset.categoryId.localeCompare(categoryKey) > 0) {
        return true
      }
      return false
    })

    if (next) {
      next.before(header)
    } else {
      this.listTarget.append(header)
    }
  }

  lastVisibleRowInCategory(header) {
    let el = header.nextElementSibling
    let last = null
    while (el && !el.hasAttribute("data-transfer-category-header")) {
      if (el.matches("[data-stock-transfer-lines-target='row']") && !el.classList.contains("hidden")) {
        last = el
      }
      el = el.nextElementSibling
    }
    return last
  }

  rowBelongsToHeader(row, header) {
    let el = header.nextElementSibling
    while (el && !el.hasAttribute("data-transfer-category-header")) {
      if (el === row) return true
      el = el.nextElementSibling
    }
    return false
  }

  removeEmptyCategoryHeaders() {
    this.listTarget.querySelectorAll("[data-transfer-category-header]").forEach((header) => {
      if (!this.lastVisibleRowInCategory(header)) header.remove()
    })
  }

  refreshCategoryCounts() {
    this.listTarget.querySelectorAll("[data-transfer-category-header]").forEach((header) => {
      let count = 0
      let el = header.nextElementSibling
      while (el && !el.hasAttribute("data-transfer-category-header")) {
        if (el.matches("[data-stock-transfer-lines-target='row']") && !el.classList.contains("hidden")) {
          count += 1
        }
        el = el.nextElementSibling
      }

      const span = header.querySelector("[data-transfer-category-count]")
      if (span) span.textContent = count > 0 ? `(${count})` : ""
    })
  }
}
