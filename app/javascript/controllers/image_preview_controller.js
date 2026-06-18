import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "preview"]

  connect() {
    this.objectUrl = null
    if (this.hasPreviewTarget && this.previewTarget.dataset.existingSrc) {
      this.existingSrc = this.previewTarget.dataset.existingSrc
    }
  }

  disconnect() {
    this.revokeObjectUrl()
  }

  preview() {
    const file = this.inputTarget.files?.[0]
    this.revokeObjectUrl()

    if (!file || !file.type.startsWith("image/")) {
      this.restoreExistingPreview()
      return
    }

    this.objectUrl = URL.createObjectURL(file)
    this.previewTarget.src = this.objectUrl
    this.previewTarget.classList.remove("hidden")
  }

  restoreExistingPreview() {
    if (this.existingSrc) {
      this.previewTarget.src = this.existingSrc
      this.previewTarget.classList.remove("hidden")
      return
    }

    this.previewTarget.classList.add("hidden")
    this.previewTarget.removeAttribute("src")
  }

  revokeObjectUrl() {
    if (this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
    }
  }
}
