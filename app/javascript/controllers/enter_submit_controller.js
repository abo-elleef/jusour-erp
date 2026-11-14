import { Controller } from "@hotwired/stimulus"

// On a multi-line note box: Enter saves (submits this field's own form), so the
// cashier never reaches for the mouse; Shift+Enter still adds a new line.
// Only the form the textarea lives in is submitted — never the surrounding order.
export default class extends Controller {
  submit(event) {
    if (event.key !== "Enter" || event.shiftKey || event.isComposing) return

    event.preventDefault()
    this.element.form?.requestSubmit()
  }
}
