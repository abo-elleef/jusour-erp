import { Controller } from "@hotwired/stimulus"

// Copies a URL/text to the clipboard. Prefer data-clipboard-text-value; falls
// back to a [data-clipboard-target="source"] input/textarea value.
export default class extends Controller {
  static values = {
    text: String,
    copiedLabel: { type: String, default: "Copied!" }
  }
  static targets = ["source", "button", "feedback"]

  async copy(event) {
    event?.preventDefault()

    const text = this.#textToCopy()
    if (!text) return

    try {
      await navigator.clipboard.writeText(text)
    } catch {
      this.#fallbackCopy(text)
    }

    this.#flashCopied()
  }

  #textToCopy() {
    if (this.hasTextValue && this.textValue) return this.textValue
    if (this.hasSourceTarget) return this.sourceTarget.value || this.sourceTarget.textContent
    return ""
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

  #flashCopied() {
    if (this.hasButtonTarget) {
      const original = this.buttonTarget.textContent
      this.buttonTarget.textContent = this.copiedLabelValue
      this.buttonTarget.disabled = true
      window.setTimeout(() => {
        this.buttonTarget.textContent = original
        this.buttonTarget.disabled = false
      }, 1500)
      return
    }

    if (this.hasFeedbackTarget) {
      this.feedbackTarget.textContent = this.copiedLabelValue
      this.feedbackTarget.classList.remove("hidden")
      window.setTimeout(() => this.feedbackTarget.classList.add("hidden"), 1500)
    }
  }
}
