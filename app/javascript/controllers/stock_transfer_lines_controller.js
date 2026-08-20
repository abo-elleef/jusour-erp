import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "list", "template", "row", "destroy", "unitSelect", "groupToggle",
    "orderLimit", "countedQuantity", "requestedQuantity", "lineCount"
  ]
  static values = {
    availableUnits: Object,
    ingredientCategories: Object,
    uncategorized: { type: String, default: "Uncategorized" },
    grouped: { type: Boolean, default: false },
    duplicateLabel: { type: String, default: "Repeated" },
    lineCountOne: { type: String, default: "%{count} line" },
    lineCountOther: { type: String, default: "%{count} lines" }
  }

  connect() {
    this.nextEntryIndex = 0
    this.captureEntryOrder()
    this.boundOnReordered = this.onLinesReordered.bind(this)
    this.element.addEventListener("nested-line-sortable:reordered", this.boundOnReordered)
    this.refreshRowIndices()
    this.refreshLineCount()
    this.refreshDuplicateHighlights()
  }

  disconnect() {
    this.element.removeEventListener("nested-line-sortable:reordered", this.boundOnReordered)
  }

  onLinesReordered() {
    this.captureEntryOrder()
    this.refreshRowIndices()
    this.refreshLineCount()
  }

  groupedValueChanged() {
    this.applyGrouping()
    this.updateToggleButtons()
  }

  toggleGrouping(event) {
    event.preventDefault()
    if (!this.groupedValue) this.captureEntryOrder()
    this.groupedValue = !this.groupedValue
  }

  applyGrouping() {
    if (!this.hasListTarget) return

    if (this.groupedValue) {
      this.groupRowsByCategory()
    } else {
      this.restoreEntryOrder()
    }

    this.listTarget.querySelectorAll("[data-transfer-category-header]").forEach((header) => {
      header.classList.toggle("hidden", !this.groupedValue)
    })
    this.refreshCategoryCounts()
    this.refreshRowIndices()
    this.refreshLineCount()
    this.refreshDuplicateHighlights()
    queueMicrotask(() => this.preserveListPositions())
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
    const row = this.rowTargets[this.rowTargets.length - 1]
    if (row) row.dataset.entryIndex = String(this.nextEntryIndex++)
    this.refreshRowIndices()
    this.refreshLineCount()
    this.refreshDuplicateHighlights()
  }

  recommendRequested(event) {
    const row = event.target.closest("[data-stock-transfer-lines-target='row']")
    if (!row) return

    const limitEl = row.querySelector("[data-stock-transfer-lines-target='orderLimit']")
    const countedEl = row.querySelector("[data-stock-transfer-lines-target='countedQuantity']")
    const requestedEl = row.querySelector("[data-stock-transfer-lines-target='requestedQuantity']")
    if (!limitEl || !countedEl || !requestedEl) return
    if (countedEl.value.trim() === "" || limitEl.value.trim() === "") return

    const limit = Number.parseFloat(limitEl.value)
    const counted = Number.parseFloat(countedEl.value)
    if (!Number.isFinite(limit) || !Number.isFinite(counted)) return

    const recommended = Math.max(0, limit - counted)
    requestedEl.value = String(Number(recommended.toFixed(3)))
  }

  // Repopulate a row's unit dropdown with the selected ingredient's units.
  // Rows stay in the order the user entered them; grouping is only a view toggle.
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

    this.refreshDuplicateHighlights()
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

    if (this.groupedValue) this.refreshCategoryCounts()
    this.refreshRowIndices()
    this.refreshLineCount()
    this.refreshDuplicateHighlights()
  }

  refreshRowIndices() {
    const duplicateCounts = new Map()
    this.visibleRows().forEach((row) => {
      const ingredientId = row.querySelector("input[name*='[ingredient_id]']")?.value
      if (ingredientId) {
        duplicateCounts.set(ingredientId, (duplicateCounts.get(ingredientId) || 0) + 1)
      }
    })

    this.visibleRows().forEach((row, index) => {
      const indexEl = row.querySelector("[data-stock-transfer-lines-row-index]")
      if (indexEl) indexEl.textContent = String(index + 1)

      const ingredientId = row.querySelector("input[name*='[ingredient_id]']")?.value
      const repeated = ingredientId && (duplicateCounts.get(ingredientId) || 0) > 1
      row.classList.toggle("table-zebra-alt", !repeated && index % 2 === 1)
    })
  }

  refreshLineCount() {
    if (!this.hasLineCountTarget) return

    const count = this.visibleRows().length
    const template = count === 1 ? this.lineCountOneValue : this.lineCountOtherValue
    this.lineCountTarget.textContent = template.replace("%{count}", String(count))
    this.lineCountTarget.classList.toggle("hidden", count === 0)
  }

  captureEntryOrder() {
    this.visibleRows().forEach((row, index) => {
      row.dataset.entryIndex = String(index)
    })
    this.nextEntryIndex = this.visibleRows().length
  }

  restoreEntryOrder() {
    this.visibleRows()
      .sort((a, b) => Number(a.dataset.entryIndex || 0) - Number(b.dataset.entryIndex || 0))
      .forEach((row) => this.listTarget.append(row))

    this.hiddenRows().forEach((row) => this.listTarget.append(row))
    this.listTarget.querySelectorAll("[data-transfer-category-header]").forEach((header) => header.remove())
  }

  groupRowsByCategory() {
    const groups = new Map()

    this.visibleRows().forEach((row) => {
      const ingredientId = row.querySelector("input[name*='[ingredient_id]']")?.value
      const meta = this.categoryMetaFor(ingredientId)
      const key = meta.id != null ? String(meta.id) : "uncategorized"
      if (!groups.has(key)) groups.set(key, { meta, key, rows: [] })
      groups.get(key).rows.push(row)
    })

    const ordered = [...groups.values()].sort((a, b) => {
      if (a.meta.position !== b.meta.position) return a.meta.position - b.meta.position
      return a.meta.name.localeCompare(b.meta.name)
    })

    this.listTarget.querySelectorAll("[data-transfer-category-header]").forEach((header) => header.remove())

    ordered.forEach((group) => {
      const header = this.buildCategoryHeader(group.key, group.meta.name, group.meta.position)
      this.listTarget.append(header)
      group.rows
        .sort((a, b) => Number(a.dataset.entryIndex || 0) - Number(b.dataset.entryIndex || 0))
        .forEach((row) => this.listTarget.append(row))
    })

    this.hiddenRows().forEach((row) => this.listTarget.append(row))
  }

  visibleRows() {
    return this.rowTargets.filter((row) => !row.classList.contains("hidden"))
  }

  hiddenRows() {
    return this.rowTargets.filter((row) => row.classList.contains("hidden"))
  }

  // Keep saved line positions as the user's entry/list order, even while grouped.
  preserveListPositions() {
    const ordered = [...this.visibleRows()].sort(
      (a, b) => Number(a.dataset.entryIndex || 0) - Number(b.dataset.entryIndex || 0)
    )
    ordered.forEach((row, index) => {
      const input = row.querySelector("input[name*='[position]']")
      if (input) input.value = index
    })
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
      "px-5 py-2.5 bg-gray-100/95 backdrop-blur-sm border-y border-gray-200 text-xs font-semibold text-gray-600 uppercase tracking-wide sticky top-[2.75rem] z-10"
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

  refreshDuplicateHighlights() {
    const counts = new Map()

    this.visibleRows().forEach((row) => {
      const ingredientId = row.querySelector("input[name*='[ingredient_id]']")?.value
      if (!ingredientId) return

      counts.set(ingredientId, (counts.get(ingredientId) || 0) + 1)
    })

    this.visibleRows().forEach((row) => {
      const ingredientId = row.querySelector("input[name*='[ingredient_id]']")?.value
      const repeated = ingredientId && (counts.get(ingredientId) || 0) > 1

      row.classList.toggle("bg-amber-50", repeated)
      row.classList.toggle("ring-1", repeated)
      row.classList.toggle("ring-amber-200", repeated)
      row.classList.toggle("ring-inset", repeated)

      const ingredientCell = row.querySelector("input[name*='[ingredient_id]']")?.closest("div")
      if (!ingredientCell) return

      let badge = ingredientCell.querySelector("[data-duplicate-ingredient-badge]")
      if (repeated) {
        if (!badge) {
          badge = document.createElement("span")
          badge.dataset.duplicateIngredientBadge = ""
          badge.className =
            "inline-flex mt-1.5 text-[10px] font-semibold uppercase tracking-wide text-amber-900 bg-amber-100 border border-amber-300 rounded px-1.5 py-0.5"
          badge.textContent = this.duplicateLabelValue
          ingredientCell.appendChild(badge)
        }
      } else {
        badge?.remove()
      }
    })
  }
}
