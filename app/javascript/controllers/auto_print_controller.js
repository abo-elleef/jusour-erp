import { Controller } from "@hotwired/stimulus"

// Opens the print dialog as soon as a print view has rendered (the reports'
// "Print" button opens ?print=1 in a new tab, unpaginated).
export default class extends Controller {
  connect() {
    requestAnimationFrame(() => window.print())
  }
}
