import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["searchInput", "resultsPanel", "resultsFrame", "createForm", "createToggle"]
  static values = { searchUrl: String }

  connect() {
    this.debounceTimer = null
    this.hideResults = this.hideResults.bind(this)
    document.addEventListener("click", this.hideResults)

    if (this.element.dataset.posCustomerOpenCreateValue === "true" && this.hasCreateFormTarget) {
      this.createFormTarget.classList.remove("hidden")
      if (this.hasCreateToggleTarget) {
        this.createToggleTarget.textContent = this.createToggleTarget.dataset.closeLabel
      }
    }
  }

  disconnect() {
    document.removeEventListener("click", this.hideResults)
  }

  search() {
    clearTimeout(this.debounceTimer)
    const query = this.searchInputTarget.value.trim()

    if (query.length < 2) {
      this.clearResults()
      return
    }

    this.debounceTimer = setTimeout(() => this.fetchResults(query), 250)
  }

  showResults() {
    if (this.searchInputTarget.value.trim().length >= 2) {
      this.resultsPanelTarget.classList.remove("hidden")
    }
  }

  async fetchResults(query) {
    const url = new URL(this.searchUrlValue, window.location.origin)
    url.searchParams.set("q", query)

    const response = await fetch(url, {
      headers: { Accept: "text/html", "Turbo-Frame": "customer_search_results" }
    })

    if (!response.ok) return

    const html = await response.text()
    const doc = new DOMParser().parseFromString(html, "text/html")
    const frame = doc.querySelector("turbo-frame#customer_search_results")

    if (frame && this.hasResultsFrameTarget) {
      this.resultsFrameTarget.innerHTML = frame.innerHTML
      this.resultsPanelTarget.classList.remove("hidden")
    }
  }

  clearResults() {
    if (this.hasResultsFrameTarget) this.resultsFrameTarget.innerHTML = ""
    if (this.hasResultsPanelTarget) this.resultsPanelTarget.classList.add("hidden")
  }

  hideResults(event) {
    if (!this.hasResultsPanelTarget) return
    if (!this.element.contains(event.target)) {
      this.resultsPanelTarget.classList.add("hidden")
    }
  }

  toggleCreateForm() {
    this.createFormTarget.classList.toggle("hidden")
    const open = !this.createFormTarget.classList.contains("hidden")
    this.createToggleTarget.textContent = open
      ? this.createToggleTarget.dataset.closeLabel
      : this.createToggleTarget.dataset.openLabel
  }
}
