import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item", "position"]
  static values = { url: String }

  connect() {
    this.bindItems()
  }

  bindItems() {
    this.itemTargets.forEach((item) => {
      if (item.dataset.sortableBound === "true") return

      item.setAttribute("draggable", "true")
      item.addEventListener("dragstart", this.onDragStart)
      item.addEventListener("dragover", this.onDragOver)
      item.addEventListener("drop", this.onDrop)
      item.addEventListener("dragend", this.onDragEnd)
      item.dataset.sortableBound = "true"
    })
  }

  onDragStart = (event) => {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.currentTarget.classList.add("opacity-50")
  }

  onDragOver = (event) => {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  onDrop = (event) => {
    event.preventDefault()
    const target = event.currentTarget.closest("[data-sortable-list-target='item']")
    if (!this.dragged || !target || target === this.dragged) return

    const list = this.element
    if (this.dragged.compareDocumentPosition(target) & Node.DOCUMENT_POSITION_FOLLOWING) {
      list.insertBefore(this.dragged, target.nextSibling)
    } else {
      list.insertBefore(this.dragged, target)
    }
    this.updatePositionLabels()
    this.saveOrder()
  }

  onDragEnd = (event) => {
    event.currentTarget.classList.remove("opacity-50")
    this.dragged = null
  }

  updatePositionLabels() {
    this.itemTargets.forEach((item, index) => {
      const label = item.querySelector("[data-sortable-list-target='position']")
      if (label) label.textContent = index
    })
  }

  async saveOrder() {
    const positions = {}
    this.itemTargets.forEach((item, index) => {
      positions[item.dataset.id] = index
    })

    await fetch(this.urlValue, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("[name='csrf-token']").content,
        "Content-Type": "application/json",
        Accept: "application/json"
      },
      body: JSON.stringify({ positions })
    })
  }
}
