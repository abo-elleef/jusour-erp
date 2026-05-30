import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list", "item"]

  connect() {
    this.items().forEach((item) => {
      item.setAttribute("draggable", "true")
      item.addEventListener("dragstart", this.onDragStart.bind(this))
      item.addEventListener("dragover", this.onDragOver.bind(this))
      item.addEventListener("drop", this.onDrop.bind(this))
      item.addEventListener("dragend", this.onDragEnd.bind(this))
    })
  }

  items() {
    return this.element.querySelectorAll("[data-sortable-categories-target='item']")
  }

  onDragStart(event) {
    this.dragged = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    event.currentTarget.classList.add("opacity-50")
  }

  onDragOver(event) {
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  onDrop(event) {
    event.preventDefault()
    const target = event.currentTarget.closest("[data-sortable-categories-target='item']")
    if (!this.dragged || !target || target === this.dragged) return

    const list = this.element
    if (this.dragged.compareDocumentPosition(target) & Node.DOCUMENT_POSITION_FOLLOWING) {
      list.insertBefore(this.dragged, target.nextSibling)
    } else {
      list.insertBefore(this.dragged, target)
    }
    this.saveOrder()
  }

  onDragEnd(event) {
    event.currentTarget.classList.remove("opacity-50")
    this.dragged = null
  }

  async saveOrder() {
    const positions = {}
    this.items().forEach((item, index) => {
      positions[item.dataset.id] = index
    })

    await fetch("/admin/categories/reorder", {
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
