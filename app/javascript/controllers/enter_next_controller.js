import { Controller } from "@hotwired/stimulus"

// POS keyboard rule: Enter is always "next step", never an early submit.
// Put on a <form>: Enter in a field moves the focus to the next field; after
// the last field it lands on the form's submit button, which is highlighted
// (see .enter-next styles in tailwind/application.css), and only Enter ON that
// button submits — the browser's own button activation does it.
// Textareas keep Enter as a new line (addresses, notes); Tab still works as usual.
export default class extends Controller {
  connect() {
    this.element.classList.add("enter-next")
    this.keydown = this.keydown.bind(this)
    this.element.addEventListener("keydown", this.keydown)
  }

  disconnect() {
    this.element.removeEventListener("keydown", this.keydown)
  }

  keydown(event) {
    if (event.key !== "Enter" || event.isComposing || event.defaultPrevented) return
    const target = event.target
    if (!target.matches("input, select")) return
    if (target.matches("[type=submit], [type=button], [type=image]")) return

    event.preventDefault()
    const next = this.fieldAfter(target)
    ;(next || this.submitButton())?.focus()
  }

  fields() {
    return [...this.element.querySelectorAll("input, select, textarea")].filter((el) =>
      !el.disabled && !el.readOnly && el.type !== "hidden" &&
      !el.matches("[type=submit], [type=button], [type=image]") &&
      el.getClientRects().length > 0
    )
  }

  // A radio group counts as one field: skip to the first field after it.
  fieldAfter(field) {
    const fields = this.fields()
    let index = fields.indexOf(field)
    if (index < 0) return null
    if (field.type === "radio") {
      while (fields[index + 1]?.type === "radio" && fields[index + 1].name === field.name) index++
    }
    return fields[index + 1] || null
  }

  submitButton() {
    return this.element.querySelector("button[type=submit]:not([disabled]), button:not([type]):not([disabled]), input[type=submit]:not([disabled])")
  }
}
