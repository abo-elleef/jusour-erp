import { Controller } from "@hotwired/stimulus"

// Drag-and-drop reordering for nested attribute line rows on forms.
// Updates each row's hidden [position] field so order is saved with the form.
//
// Expected markup (per row):
//   data-nested-line-sortable-target="row"
//   a handle: data-nested-line-sortable-target="handle" draggable="true"
//   hidden input name="...[position]" (optional data-nested-line-sortable-target="position")
export default class extends Controller {
  static targets = ["row", "handle", "position"]

  connect() {
    this.reindex()
    this.bindHandles()
    this.observer = new MutationObserver(() => {
      this.bindHandles()
      this.reindex()
    })
    this.observer.observe(this.element, { childList: true, subtree: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  bindHandles() {
    this.handleTargets.forEach((handle) => {
      if (handle.dataset.nestedSortableBound === "true") return

      handle.setAttribute("draggable", "true")
      handle.addEventListener("dragstart", this.onDragStart)
      handle.addEventListener("dragend", this.onDragEnd)
      handle.dataset.nestedSortableBound = "true"
    })

    this.rowTargets.forEach((row) => {
      if (row.dataset.nestedSortableRowBound === "true") return

      row.addEventListener("dragover", this.onDragOver)
      row.addEventListener("drop", this.onDrop)
      row.dataset.nestedSortableRowBound = "true"
    })
  }

  onDragStart = (event) => {
    const row = event.currentTarget.closest("[data-nested-line-sortable-target='row']")
    if (!row || row.classList.contains("hidden")) {
      event.preventDefault()
      return
    }

    this.dragged = row
    event.dataTransfer.effectAllowed = "move"
    event.dataTransfer.setData("text/plain", "row")
    row.classList.add("opacity-50")
  }

  onDragOver = (event) => {
    if (!this.dragged) return
    event.preventDefault()
    event.dataTransfer.dropEffect = "move"
  }

  onDrop = (event) => {
    event.preventDefault()
    const target = event.currentTarget.closest("[data-nested-line-sortable-target='row']")
    if (!this.dragged || !target || target === this.dragged) return
    if (target.classList.contains("hidden")) return

    if (this.dragged.compareDocumentPosition(target) & Node.DOCUMENT_POSITION_FOLLOWING) {
      target.after(this.dragged)
    } else {
      target.before(this.dragged)
    }
    this.reindex()
  }

  onDragEnd = () => {
    this.dragged?.classList.remove("opacity-50")
    this.dragged = null
    this.reindex()
  }

  reindex() {
    let index = 0
    this.rowTargets.forEach((row) => {
      if (row.classList.contains("hidden")) return

      const input =
        row.querySelector("[data-nested-line-sortable-target='position']") ||
        row.querySelector("input[name*='[position]']")
      if (input) input.value = index
      index += 1
    })
  }
}
