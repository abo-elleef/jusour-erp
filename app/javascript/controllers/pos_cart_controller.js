import { Controller } from "@hotwired/stimulus"
import { posCartHeaders, rememberPosCart } from "utils/pos_cart"

// Tags every Turbo request from the register with the cart it shows, and keeps
// that cart up to date from the responses. Same-origin only: the header is ours.
export default class extends Controller {
  connect() {
    this.beforeRequest = this.beforeRequest.bind(this)
    this.beforeResponse = this.beforeResponse.bind(this)
    document.addEventListener("turbo:before-fetch-request", this.beforeRequest)
    document.addEventListener("turbo:before-fetch-response", this.beforeResponse)
  }

  disconnect() {
    document.removeEventListener("turbo:before-fetch-request", this.beforeRequest)
    document.removeEventListener("turbo:before-fetch-response", this.beforeResponse)
  }

  beforeRequest(event) {
    const { fetchOptions, url } = event.detail
    if (!fetchOptions || (url && new URL(url, window.location.href).origin !== window.location.origin)) return
    fetchOptions.headers = { ...(fetchOptions.headers || {}), ...posCartHeaders() }
  }

  beforeResponse(event) {
    rememberPosCart(event.detail.fetchResponse?.response)
  }
}
