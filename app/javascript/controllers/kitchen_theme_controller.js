import { Controller } from "@hotwired/stimulus"

// Light/dark for the kitchen-layout screens.
//
// Deliberately client-side (localStorage + a `.dark` class on <html>) rather
// than a server-side preference: the production sheet is a long grid of typed
// quantities, and reloading the page to re-theme would discard whatever is
// half-entered.
//
// `themeable` is false for the KDS — that's a wall-mounted display where dark is
// always right — so it stays pinned dark and renders no toggle. connect() runs on
// every Turbo navigation, which is what keeps the two screens from inheriting
// each other's theme (Turbo does not touch the <html> element's class).
export default class extends Controller {
  static values = {
    themeable: { type: Boolean, default: false },
    storageKey: { type: String, default: "kitchenTheme" }
  }

  connect() {
    this.apply(this.themeableValue && this.stored === "light" ? "light" : "dark")
  }

  toggle() {
    if (!this.themeableValue) return

    const next = document.documentElement.classList.contains("dark") ? "light" : "dark"
    this.apply(next)
    try {
      localStorage.setItem(this.storageKeyValue, next)
    } catch (e) {
      // Storage blocked (private mode). The toggle still holds for this page view.
    }
  }

  apply(theme) {
    document.documentElement.classList.toggle("dark", theme === "dark")
  }

  get stored() {
    try {
      return localStorage.getItem(this.storageKeyValue)
    } catch (e) {
      return null
    }
  }
}
