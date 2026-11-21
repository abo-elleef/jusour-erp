import { Controller } from "@hotwired/stimulus"

// Brings this element into view when the URL asks for it (?at=<element id>).
// Turbo drops a #anchor when it follows a redirect, so a redirect back to a
// section of a long page carries ?at= instead. Waits for turbo:load, because
// Turbo resets the scroll position after it renders the page.
export default class extends Controller {
  connect() {
    if (new URLSearchParams(window.location.search).get("at") !== this.element.id) return

    this.scroll = () => this.element.scrollIntoView({ block: "start" })
    document.addEventListener("turbo:load", this.scroll, { once: true })
    setTimeout(this.scroll, 0)
  }

  disconnect() {
    if (this.scroll) document.removeEventListener("turbo:load", this.scroll)
  }
}
