import { Controller } from "@hotwired/stimulus"

// The POS add-item popup, driven from the keyboard so a rush-hour cashier never
// reaches for the cart to fix a count:
//   tap item → count field is focused and selected → type 3 (Arabic or English digits)
//   → Enter: jumps to the first choice when the item has modifiers, else adds
//   → arrows move between choices; Enter picks the focused one and goes to the next
//     required group still empty, or adds when none is left. Esc closes.
export default class extends Controller {
  static targets = ["quantity", "cancel"]

  connect() {
    // A Turbo-frame insert doesn't reliably honour `autofocus`.
    requestAnimationFrame(() => {
      this.quantityTarget.focus()
      this.quantityTarget.select()
    })
  }

  // Integers only: runs after arabic-numerals#normalize has turned ٣ into 3.
  digitsOnly() {
    const input = this.quantityTarget
    const cleaned = input.value.replace(/\D/g, "")
    if (cleaned !== input.value) input.value = cleaned
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.cancelTarget.click()
      return
    }
    if (event.key !== "Enter" || event.isComposing) return

    const target = event.target
    if (target === this.quantityTarget) {
      const choice = this.firstChoice()
      if (choice) {
        event.preventDefault()
        choice.focus()
      }
      // No modifiers: the form's own implicit submit adds the item.
      return
    }
    if (target.matches("input[data-modifier-option]")) {
      // Browsers don't reliably submit a form on Enter from a radio or checkbox.
      event.preventDefault()
      // Enter on a focused choice picks it, like a tap.
      if (target.type === "radio" && !target.checked) {
        target.checked = true
        target.dispatchEvent(new Event("change", { bubbles: true }))
      }
      // Another required group still empty: go there instead of failing validation.
      const next = this.unpickedRequired()
      if (next) next.focus()
      else this.element.requestSubmit()
    }
  }

  // The first required group with nothing picked yet, else the very first choice.
  firstChoice() {
    return this.unpickedRequired() || this.element.querySelector("input[data-modifier-option]")
  }

  unpickedRequired() {
    for (const fieldset of this.element.querySelectorAll("fieldset")) {
      const options = [...fieldset.querySelectorAll("input[data-modifier-option]")]
      if (options.some((o) => o.required) && !options.some((o) => o.checked)) return options[0]
    }
    return null
  }
}
