import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["banner", "queue", "job"]
  static values = {
    config: Object,
    payloadUrlTemplate: String,
    confirmUrlTemplate: String
  }

  connect() {
    this.storageKey = "saqr_register_printer"
    this.boundBannerDismissed = () => this.hideBanner()
    if (this.hasBannerTarget) {
      this.bannerTarget.addEventListener("banner:dismissed", this.boundBannerDismissed)
    }
    if (this.configValue?.client_routing) {
      this.checkAgentHealth()
    }
  }

  disconnect() {
    if (this.hasBannerTarget) {
      this.bannerTarget.removeEventListener("banner:dismissed", this.boundBannerDismissed)
    }
  }

  jobTargetConnected(element) {
    if (!this.configValue?.client_routing) return
    this.processJob(element)
  }

  async checkAgentHealth() {
    if (!this.hasBannerTarget) return
    if (this.isBannerDismissed()) return

    try {
      const ok = await this.agentFetch("/health")
      if (ok) {
        this.hideBanner()
        return
      }
    } catch (_e) {
      // fall through
    }

    this.showBanner()
  }

  showBanner() {
    if (this.isBannerDismissed()) return
    this.dismissibleBanner()?.show() || this.bannerTarget.classList.remove("hidden")
  }

  hideBanner() {
    if (!this.hasBannerTarget) return
    this.dismissibleBanner()?.hide() || this.bannerTarget.classList.add("hidden")
  }

  isBannerDismissed() {
    return sessionStorage.getItem("saqr_banner_dismissed_print-agent") === "1"
  }

  dismissibleBanner() {
    if (!this.hasBannerTarget) return null
    return this.application.getControllerForElementAndIdentifier(
      this.bannerTarget,
      "dismissible-banner"
    )
  }

  async processJob(element) {
    const printLogId = element.dataset.printLogId
    if (!printLogId) return

    try {
      const payload = await this.fetchPayload(printLogId)
      await this.sendToAgent(payload)
      await this.confirmPrint(printLogId, "sent")
    } catch (error) {
      await this.confirmPrint(printLogId, "failed", error.message)
    } finally {
      element.remove()
    }
  }

  async fetchPayload(printLogId) {
    const register = this.loadRegisterPrinter()
    const url = this.payloadUrl(printLogId, register)
    const response = await fetch(url, {
      headers: { Accept: "application/json" },
      credentials: "same-origin"
    })
    if (!response.ok) {
      const body = await response.json().catch(() => ({}))
      throw new Error(body.error || "Failed to load print payload")
    }
    return response.json()
  }

  payloadUrl(printLogId, register) {
    let url = this.payloadUrlTemplateValue.replace(":id", printLogId)
    if (register?.host) {
      const params = new URLSearchParams({ host: register.host, port: register.port || "9100" })
      url += `?${params}`
    }
    return url
  }

  confirmUrl(printLogId) {
    return this.confirmUrlTemplateValue.replace(":id", printLogId)
  }

  async sendToAgent(payload) {
    const host = payload.host
    const port = payload.port
    const body = {
      host,
      port,
      data_base64: payload.data_base64
    }
    const response = await this.agentFetch("/print", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    })
    if (!response?.ok) {
      throw new Error(response?.error || "Print agent failed")
    }
  }

  async confirmPrint(printLogId, status, errorMessage = null) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    await fetch(this.confirmUrl(printLogId), {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": csrf
      },
      credentials: "same-origin",
      body: JSON.stringify({ status, error_message: errorMessage })
    })
  }

  async agentFetch(path, options = {}) {
    const headers = { ...(options.headers || {}), ...this.agentHeaders() }
    const response = await fetch(`${this.configValue.url}${path}`, { ...options, headers })
    if (path === "/health") {
      return response.ok ? response.json() : null
    }
    const body = await response.json().catch(() => ({}))
    if (!response.ok) {
      throw new Error(body.error || response.statusText)
    }
    return body
  }

  agentHeaders() {
    const headers = {}
    if (this.configValue?.token) {
      headers["X-Print-Agent-Token"] = this.configValue.token
    }
    return headers
  }

  loadRegisterPrinter() {
    try {
      return JSON.parse(localStorage.getItem(this.storageKey) || "null")
    } catch {
      return null
    }
  }
}
