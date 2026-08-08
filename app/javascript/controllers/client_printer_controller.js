import { Controller } from "@hotwired/stimulus"

const MAX_RETRIES = 3
const RETRY_DELAY_MS = 2000

export default class extends Controller {
  static targets = ["queue", "job"]
  static values = {
    config: Object,
    payloadUrlTemplate: String,
    confirmUrlTemplate: String,
    pendingUrl: String
  }

  connect() {
    this.storageKey = "saqr_register_printer"
    this.boundBannerDismissed = () => this.hideBanner()
    this.bannerElement = () => document.getElementById("print-agent-banner")
    // Serial queue: process one job at a time to avoid concurrent TCP conflicts
    this._queue = Promise.resolve()
    // Track in-flight job IDs to avoid double-processing
    this._inFlight = new Set()

    const banner = this.bannerElement()
    if (banner) {
      banner.addEventListener("banner:dismissed", this.boundBannerDismissed)
    }

    if (this.configValue?.client_routing) {
      this.clearPrintAgentDismissalOnReload()
      this.checkAgentHealth()
      // Re-deliver any pending jobs that were missed while browser was offline
      this.recoverPendingJobs()
    }
  }

  clearPrintAgentDismissalOnReload() {
    const [nav] = performance.getEntriesByType("navigation")
    const reloaded = nav?.type ? nav.type === "reload" : performance.navigation?.type === 1
    if (reloaded) sessionStorage.removeItem("saqr_banner_dismissed_print-agent")
  }

  disconnect() {
    const banner = this.bannerElement()
    if (banner) {
      banner.removeEventListener("banner:dismissed", this.boundBannerDismissed)
    }
  }

  jobTargetConnected(element) {
    if (!this.configValue?.client_routing) return
    this.enqueueJob(element.dataset.printLogId, element)
  }

  // Serial queue: each job waits for the previous to finish
  enqueueJob(printLogId, element) {
    if (!printLogId || this._inFlight.has(printLogId)) return
    this._inFlight.add(printLogId)
    this._queue = this._queue.then(() => this.processJob(printLogId, element))
  }

  async processJob(printLogId, element) {
    let lastError = null
    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
      try {
        const payload = await this.fetchPayload(printLogId)
        await this.sendToAgent(payload)
        await this.confirmPrint(printLogId, "sent")
        element?.remove()
        this._inFlight.delete(printLogId)
        return
      } catch (error) {
        lastError = error
        if (attempt < MAX_RETRIES) {
          await this.sleep(RETRY_DELAY_MS * attempt)
        }
      }
    }
    // All retries exhausted
    await this.confirmPrint(printLogId, "failed", lastError?.message)
    element?.remove()
    this._inFlight.delete(printLogId)
  }

  // Fetch any pending PrintLogs the browser missed while disconnected
  async recoverPendingJobs() {
    if (!this.hasPendingUrlValue) return
    try {
      const response = await fetch(this.pendingUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      if (!response.ok) return
      const jobs = await response.json()
      for (const job of jobs) {
        this.enqueueJob(job.id, null)
      }
    } catch (_e) {
      // Recovery is best-effort; silent fail
    }
  }

  sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms))
  }

  async checkAgentHealth() {
    if (!this.bannerElement()) return
    if (this.isBannerDismissed()) return

    try {
      const ok = await this.agentFetch("/health")
      if (ok) {
        this.hideBanner()
        return
      }
    } catch (_error) {
      // fall through
    }

    this.showBanner()
  }

  showBanner() {
    if (this.isBannerDismissed()) return
    this.dismissibleBanner()?.show() || this.bannerElement()?.classList.remove("hidden")
    this.notifyBannerOffsetChange()
  }

  hideBanner() {
    const banner = this.bannerElement()
    if (!banner) return
    this.dismissibleBanner()?.hide() || banner.classList.add("hidden")
    this.notifyBannerOffsetChange()
  }

  notifyBannerOffsetChange() {
    requestAnimationFrame(() => {
      document.dispatchEvent(new CustomEvent("pos-banners:changed"))
    })
  }

  isBannerDismissed() {
    return sessionStorage.getItem("saqr_banner_dismissed_print-agent") === "1"
  }

  dismissibleBanner() {
    const banner = this.bannerElement()
    if (!banner) return null
    return this.application.getControllerForElementAndIdentifier(banner, "dismissible-banner")
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
    const body = payload.connection === "usb"
      ? {
          connection: "usb",
          device: payload.device || payload.host,
          data_base64: payload.data_base64
        }
      : {
          connection: "network",
          host: payload.host,
          port: payload.port,
          data_base64: payload.data_base64
        }
    const response = await this.agentFetch("/print", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body)
    })
    // agentFetch throws on HTTP error; reaching here means success
    if (response && response.ok === false) {
      throw new Error(response.error || "Print agent failed")
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
