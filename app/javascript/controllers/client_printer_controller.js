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
    this.agentHealthy = true
    this.boundBannerDismissed = () => this.hideBanner()
    this.bannerElement = () => document.getElementById("print-agent-banner")

    const banner = this.bannerElement()
    if (banner) {
      banner.addEventListener("banner:dismissed", this.boundBannerDismissed)
    }
    this.boundTurboRender = () => this.updateCheckoutUI(this.agentHealthy)
    document.addEventListener("turbo:render", this.boundTurboRender)

    if (this.configValue?.client_routing) {
      this.updateCheckoutUI(false)
      this.checkAgentHealth()
      this.healthCheckInterval = setInterval(() => this.checkAgentHealth(), 30000)
    }
  }

  disconnect() {
    const banner = this.bannerElement()
    if (banner) {
      banner.removeEventListener("banner:dismissed", this.boundBannerDismissed)
    }
    document.removeEventListener("turbo:render", this.boundTurboRender)
    clearInterval(this.healthCheckInterval)
  }

  jobTargetConnected(element) {
    if (!this.configValue?.client_routing) return
    this.processJob(element)
  }

  async checkAgentHealth() {
    if (!this.configValue?.client_routing) return

    let healthy = false
    try {
      const response = await this.agentFetch("/health")
      healthy = !!response?.ok
    } catch (_error) {
      healthy = false
    }

    this.agentHealthy = healthy
    this.updateCheckoutUI(healthy)
    this.setHealthCookie(healthy)

    if (healthy) {
      this.hideBanner()
    } else {
      this.showBanner()
    }
  }

  showBanner() {
    if (this.isBannerDismissed()) return
    this.dismissibleBanner()?.show() || this.bannerElement()?.classList.remove("hidden")
  }

  hideBanner() {
    const banner = this.bannerElement()
    if (!banner) return
    this.dismissibleBanner()?.hide() || banner.classList.add("hidden")
  }

  isBannerDismissed() {
    return sessionStorage.getItem("saqr_banner_dismissed_print-agent") === "1"
  }

  dismissibleBanner() {
    const banner = this.bannerElement()
    if (!banner) return null
    return this.application.getControllerForElementAndIdentifier(banner, "dismissible-banner")
  }

  updateCheckoutUI(healthy) {
    document.body.dataset.printAgentHealthy = healthy ? "true" : "false"

    if (!healthy) {
      document.getElementById("payment-modal")?.classList.add("hidden")
    }

    document.querySelectorAll("[data-requires-print-agent]").forEach((element) => {
      element.classList.toggle("hidden", !healthy)
      element.querySelectorAll("button, input[type='submit']").forEach((control) => {
        control.disabled = !healthy
      })
    })

    document.querySelectorAll("[data-print-agent-checkout-blocked]").forEach((element) => {
      element.classList.toggle("hidden", healthy)
    })
  }

  setHealthCookie(healthy) {
    const value = healthy ? "1" : "0"
    document.cookie = `print_agent_healthy=${value}; path=/; max-age=60; SameSite=Lax`
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
