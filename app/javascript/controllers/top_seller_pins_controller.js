import { Controller } from "@hotwired/stimulus"

// Branch form → "Most sold row": the ordered list of pinned menu items. Each row
// carries a hidden location[top_seller_pinned_item_ids][] input, so the order on
// screen is the order saved. Items are added from a searchable select; the list
// holds at most `max` items (the size of the row).
export default class extends Controller {
  static targets = ["list", "row", "empty", "picker", "full"]
  static values = { max: Number, fieldName: String, labels: Object, buttonLabels: Object }

  connect() {
    this.refresh()
  }

  add(event) {
    const id = event.detail?.value
    const select = event.currentTarget
    if (id && !this.pinnedIds().includes(id) && this.rowTargets.length < this.maxValue) {
      this.listTarget.appendChild(this.buildRow(id))
    }
    this.clearPicker(select)
    this.refresh()
  }

  remove(event) {
    event.currentTarget.closest("[data-top-seller-pins-target='row']").remove()
    this.refresh()
  }

  up(event) {
    const row = event.currentTarget.closest("[data-top-seller-pins-target='row']")
    const previous = row.previousElementSibling
    if (previous) this.listTarget.insertBefore(row, previous)
    this.refresh()
  }

  down(event) {
    const row = event.currentTarget.closest("[data-top-seller-pins-target='row']")
    const next = row.nextElementSibling
    if (next) this.listTarget.insertBefore(next, row)
    this.refresh()
  }

  pinnedIds() {
    return this.rowTargets.map((row) => row.querySelector("input[type='hidden']").value)
  }

  buildRow(id) {
    const row = document.createElement("li")
    row.className = "flex items-center gap-2 rounded-lg border border-stone-200 bg-white px-3 py-2 text-sm"
    row.dataset.topSellerPinsTarget = "row"

    const input = document.createElement("input")
    input.type = "hidden"
    input.name = this.fieldNameValue
    input.value = id

    const position = document.createElement("span")
    position.className = "w-6 shrink-0 text-xs font-semibold text-gray-400 tabular-nums"
    position.dataset.position = ""

    const label = document.createElement("span")
    label.className = "flex-1 min-w-0 truncate text-gray-900"
    label.textContent = this.labelsValue[id] || id

    row.append(input, position, label, ...this.buttons())
    return row
  }

  // Up / down / remove, labelled from the translated buttonLabels value.
  buttons() {
    return [["up", "↑", "text-gray-500 hover:bg-stone-100"], ["down", "↓", "text-gray-500 hover:bg-stone-100"], ["remove", "✕", "text-red-600 hover:bg-red-50"]]
      .map(([action, text, classes]) => {
        const button = document.createElement("button")
        button.type = "button"
        button.className = `shrink-0 rounded px-1.5 ${classes}`
        button.dataset.action = `top-seller-pins#${action}`
        button.setAttribute("aria-label", this.buttonLabelsValue[action] || action)
        button.textContent = text
        return button
      })
  }

  clearPicker(select) {
    if (!select) return
    const hidden = select.querySelector("[data-searchable-select-target='hidden']")
    const input = select.querySelector("[data-searchable-select-target='input']")
    if (hidden) hidden.value = ""
    if (input) {
      input.value = ""
      input.blur()
    }
  }

  refresh() {
    this.rowTargets.forEach((row, index) => {
      const position = row.querySelector("[data-position]")
      if (position) position.textContent = `${index + 1}`
    })
    const count = this.rowTargets.length
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", count > 0)
    const full = count >= this.maxValue
    if (this.hasPickerTarget) this.pickerTarget.classList.toggle("hidden", full)
    if (this.hasFullTarget) this.fullTarget.classList.toggle("hidden", !full)
  }
}
