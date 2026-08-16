import { Controller } from "@hotwired/stimulus"

const BG_KEY = "saqr.sidebar.bg"
const TEXT_KEY = "saqr.sidebar.text"
const DEFAULT_BG = "#111827"
const DEFAULT_TEXT = "#f3f4f6"

// Persists admin sidebar colors in localStorage only (this browser/device).
export default class extends Controller {
  static targets = ["bgInput", "textInput", "panel", "toggle"]

  static values = {
    showLabel: { type: String, default: "Sidebar colors" },
    hideLabel: { type: String, default: "Hide colors" }
  }

  connect() {
    this.apply(this.readBg(), this.readText())
    this.hidePanel()
  }

  togglePanel(event) {
    event.preventDefault()
    if (this.panelTarget.hidden) {
      this.showPanel()
    } else {
      this.hidePanel()
    }
  }

  showPanel() {
    this.panelTarget.hidden = false
    this.panelTarget.classList.remove("hidden")
    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", "true")
      this.toggleTarget.textContent = this.hideLabelValue
    }
  }

  hidePanel(event) {
    event?.preventDefault()
    this.panelTarget.hidden = true
    this.panelTarget.classList.add("hidden")
    if (this.hasToggleTarget) {
      this.toggleTarget.setAttribute("aria-expanded", "false")
      this.toggleTarget.textContent = this.showLabelValue
    }
  }

  changeBg(event) {
    const value = event.target.value
    this.write(BG_KEY, value)
    this.apply(value, this.readText())
  }

  changeText(event) {
    const value = event.target.value
    this.write(TEXT_KEY, value)
    this.apply(this.readBg(), value)
  }

  reset(event) {
    event.preventDefault()
    localStorage.removeItem(BG_KEY)
    localStorage.removeItem(TEXT_KEY)
    this.apply(DEFAULT_BG, DEFAULT_TEXT)
    if (this.hasBgInputTarget) this.bgInputTarget.value = DEFAULT_BG
    if (this.hasTextInputTarget) this.textInputTarget.value = DEFAULT_TEXT
  }

  apply(bg, text) {
    const root = document.documentElement
    root.style.setProperty("--sidebar-bg", bg)
    root.style.setProperty("--sidebar-text", text)
    if (this.hasBgInputTarget) this.bgInputTarget.value = bg
    if (this.hasTextInputTarget) this.textInputTarget.value = text
  }

  readBg() {
    return localStorage.getItem(BG_KEY) || DEFAULT_BG
  }

  readText() {
    return localStorage.getItem(TEXT_KEY) || DEFAULT_TEXT
  }

  write(key, value) {
    try {
      localStorage.setItem(key, value)
    } catch (_error) {
      // Private mode / quota — ignore; colors still apply for this page load.
    }
  }
}
