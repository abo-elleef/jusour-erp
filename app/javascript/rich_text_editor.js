import "trix"
import "@rails/actiontext"

// Storefront pages accept photos only (JPEG, PNG, WebP up to 10 MB) — no PDFs
// or other files that would render as download links on the public site.
const ACCEPTED = ["image/jpeg", "image/png", "image/webp"]
const MAX_BYTES = 10 * 1024 * 1024

document.addEventListener("trix-file-accept", (event) => {
  const file = event.file
  if (!ACCEPTED.includes(file.type) || file.size > MAX_BYTES) {
    event.preventDefault()
    const message = event.target.dataset.rejectedFileMessage
    if (message) window.alert(message)
  }
})
