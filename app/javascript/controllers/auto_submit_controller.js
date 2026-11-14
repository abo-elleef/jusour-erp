import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }

  // For a search box with no button: once it's emptied (text deleted or the
  // box's own × pressed), reload so the full list comes back.
  submitIfCleared(event) {
    if (event.target.value === "") this.submit()
  }
}
