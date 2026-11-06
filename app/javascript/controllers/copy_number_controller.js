import { Controller } from "@hotwired/stimulus"

// Small copy icon next to a figure on a financial report. Copies the plain
// machine number (e.g. "-1234.50", no separators, no currency) so it pastes
// straight into Google Sheets or a calculator as a real number.
export default class extends Controller {
  static values = { text: String }
  static targets = ["copyIcon", "doneIcon"]

  async copy(event) {
    // The button can sit inside a <summary> or a link; never toggle/navigate.
    event.preventDefault()
    event.stopPropagation()

    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch {
      this.#fallbackCopy(this.textValue)
    }
    this.#flash()
  }

  #fallbackCopy(text) {
    const field = document.createElement("textarea")
    field.value = text
    field.setAttribute("readonly", "")
    field.style.position = "fixed"
    field.style.opacity = "0"
    document.body.appendChild(field)
    field.select()
    document.execCommand("copy")
    field.remove()
  }

  #flash() {
    this.copyIconTarget.classList.add("hidden")
    this.doneIconTarget.classList.remove("hidden")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      this.copyIconTarget.classList.remove("hidden")
      this.doneIconTarget.classList.add("hidden")
    }, 1200)
  }

  disconnect() { clearTimeout(this.timer) }
}
