import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "admin-sidebar:scroll-top"

// Keeps the sidebar nav scrolled to where the user left it across page
// visits. Without this, clicking a link that required scrolling down to
// reach (a Settings tab, or a tab inside an expanded module) dumps the user
// back at the top of the sidebar on the next page, hiding the very section
// they were just in and interrupting the flow of browsing one area.
export default class extends Controller {
  connect() {
    const saved = sessionStorage.getItem(STORAGE_KEY)
    if (saved !== null) this.element.scrollTop = parseInt(saved, 10) || 0

    this.boundSave = this.save.bind(this)
    this.element.addEventListener("scroll", this.boundSave, { passive: true })
  }

  disconnect() {
    this.element.removeEventListener("scroll", this.boundSave)
  }

  save() {
    sessionStorage.setItem(STORAGE_KEY, String(this.element.scrollTop))
  }
}
