import { Controller } from "@hotwired/stimulus"

// The POS add-item popup, driven from the keyboard so a rush-hour cashier never
// reaches for the cart to fix a count:
//   tap item → count field is focused and selected → type 3 (Arabic or English digits)
//   → Enter: jumps to the first option group when the item has any, else to the note
//   → arrows move between choices inside a group
//   → Enter picks the focused choice and moves to the NEXT group, required or
//     optional, in the order they are shown; after the last group → kitchen note
//   → Enter in the note → the Add button, highlighted (or back to a required
//     group still empty instead of failing validation)
//   → Enter on the Add button adds. Enter never adds from anywhere else.
//   → Tab moves to the next group without picking; Shift+Tab goes back as usual.
//   Esc = Cancel, wherever the focus is (even after a click on blank space in
//   the popup drops it to <body>).
export default class extends Controller {
  static targets = ["quantity", "notes", "submit", "cancel"]

  connect() {
    this.escape = this.escape.bind(this)
    document.addEventListener("keydown", this.escape)
    // A Turbo-frame insert doesn't reliably honour `autofocus`.
    requestAnimationFrame(() => {
      this.quantityTarget.focus()
      this.quantityTarget.select()
    })
  }

  disconnect() {
    document.removeEventListener("keydown", this.escape)
    // Lets the menu search take the focus back (pos_menu_search_controller).
    document.dispatchEvent(new CustomEvent("pos:popup-closed"))
  }

  escape(event) {
    if (event.key !== "Escape" || event.isComposing) return
    event.preventDefault()
    this.cancel(event)
  }

  // Closes the popup in place: no page reload, so the picked category, the
  // scroll position and the basket stay exactly as the cashier left them.
  // Swaps in an empty frame, the same as a successful add does
  // (order_items/create.turbo_stream), so the next item tap loads normally.
  cancel(event) {
    event?.preventDefault()
    document.removeEventListener("keydown", this.escape) // a held key must not cancel twice
    const frame = this.element.closest("turbo-frame")
    if (!frame) return window.location.assign(this.cancelTarget.href)
    const empty = document.createElement("turbo-frame")
    empty.id = frame.id
    frame.replaceWith(empty)
  }

  // Integers only: runs after arabic-numerals#normalize has turned ٣ into 3.
  digitsOnly() {
    const input = this.quantityTarget
    const cleaned = input.value.replace(/\D/g, "")
    if (cleaned !== input.value) input.value = cleaned
  }

  keydown(event) {
    if (event.isComposing) return
    if (event.key === "Enter") this.enter(event)
    else if (event.key === "Tab" && !event.shiftKey) this.tab(event)
  }

  enter(event) {
    const target = event.target
    if (target === this.quantityTarget) {
      event.preventDefault()
      const first = this.groups()[0]
      if (first) this.focusGroup(first)
      else this.notesTarget.focus()
      return
    }
    if (target === this.notesTarget) {
      event.preventDefault()
      const missing = this.unpickedRequired()
      if (missing) this.focusGroup(missing)
      else this.submitTarget.focus()
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

    // Last group: on to the kitchen note.
    this.notesTarget.focus()
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
