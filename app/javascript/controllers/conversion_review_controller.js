import { Controller } from "@hotwired/stimulus"

// Unit-conversion review: fill a row's factor with the value the review
// suggests, and mark by hand which rows were touched so a page of 60 inputs
// still shows what is about to be saved.
export default class extends Controller {
  apply(event) {
    const button = event.currentTarget
    const field = document.getElementById(button.dataset.field)
    if (!field) return

    field.value = button.dataset.value
    this.mark(field)
    field.focus()
  }

  touch(event) {
    this.mark(event.target)
  }

  mark(field) {
    const row = field.closest("tr")
    if (row) row.classList.add("ring-2", "ring-amber-300", "ring-inset")
  }
}
