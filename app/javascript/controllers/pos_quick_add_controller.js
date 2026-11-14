import { Controller } from "@hotwired/stimulus"

// The POS add-item popup, driven from the keyboard so a rush-hour cashier never
// reaches for the cart to fix a count:
//   tap item → count field is focused and selected → type 3 (Arabic or English digits)
//   → Enter: jumps to the first option group when the item has any, else adds
//   → arrows move between choices inside a group
//   → Enter picks the focused choice and moves to the NEXT group, required or
//     optional, in the order they are shown; after the last group it adds (or
//     goes back to a required group still empty instead of failing validation)
//   → Tab moves to the next group without picking; Shift+Tab goes back as usual.
//   Esc closes.
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
    if (event.isComposing) return
    if (event.key === "Enter") this.enter(event)
    else if (event.key === "Tab" && !event.shiftKey) this.tab(event)
  }

  enter(event) {
    const target = event.target
    if (target === this.quantityTarget) {
      const first = this.groups()[0]
      if (first) {
        event.preventDefault()
        this.focusGroup(first)
      }
      // No option groups: the form's own implicit submit adds the item.
      return
    }
    if (!target.matches("input[data-modifier-option]")) return

    // Browsers don't reliably submit a form on Enter from a radio or checkbox.
    event.preventDefault()
    // Enter on a focused choice picks it, like a tap. A checkbox is only ever
    // ticked here, never unticked (Space still toggles it).
    if (!target.checked) {
      target.checked = true
      target.dispatchEvent(new Event("change", { bubbles: true }))
    }

    const next = this.groupAfter(target)
    if (next) return this.focusGroup(next)

    // Last group: a required one still empty gets the focus instead of a failed submit.
    const missing = this.unpickedRequired()
    if (missing) this.focusGroup(missing)
    else this.element.requestSubmit()
  }

  // Tab from an option skips the rest of its group (checkboxes would otherwise
  // take one Tab each) and lands on the next group. From the last group it
  // falls through to the browser, which moves on to the kitchen note.
  tab(event) {
    const target = event.target
    if (!target.matches("input[data-modifier-option]")) return

    const next = this.groupAfter(target)
    if (!next) return
    event.preventDefault()
    this.focusGroup(next)
  }

  groups() {
    return [...this.element.querySelectorAll("fieldset")].filter((f) => f.querySelector("input[data-modifier-option]"))
  }

  groupAfter(option) {
    const groups = this.groups()
    const index = groups.indexOf(option.closest("fieldset"))
    return index >= 0 ? groups[index + 1] : null
  }

  // Lands on the group's picked choice if there is one, else its first choice.
  focusGroup(fieldset) {
    const options = [...fieldset.querySelectorAll("input[data-modifier-option]")]
    const option = options.find((o) => o.checked) || options[0]
    option?.focus()
  }

  unpickedRequired() {
    return this.groups().find((fieldset) => {
      const options = [...fieldset.querySelectorAll("input[data-modifier-option]")]
      return options.some((o) => o.required) && !options.some((o) => o.checked)
    })
  }
}
