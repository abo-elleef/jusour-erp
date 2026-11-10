import { Controller } from "@hotwired/stimulus"

const MAX_RETRIES = 3
const RETRY_DELAY_MS = 2000
const POLL_INTERVAL_MS = 10000
const OUTBOX_KEY = "saqr_print_outbox"

// Module scope on purpose. Turbo replaces the page body on every navigation, which
// builds a fresh controller; if the queue and the in-flight set lived on the
// instance, the new page could pick up a job the old page is still printing and
// print it a second time.
const inFlight = new Set()
let jobQueue = Promise.resolve()

export default class extends Controller {
  static targets = ["queue", "job"]
  static values = {
    config: Object,
    payloadUrlTemplate: String,
    confirmUrlTemplate: String,
    pendingUrl: String,
    failedUrl: String,
    retryUrlTemplate: String
  }

  connect() {
    this.storageKey = "saqr_register_printer"
    this.boundBannerDismissed = () => this.hideBanner()
    this.bannerElement = () => document.getElementById("print-agent-banner")

    const banner = this.bannerElement()
    if (banner) {
      banner.addEventListener("banner:dismissed", this.boundBannerDismissed)
    }

    if (this.configValue?.client_routing) {
      this.clearPrintAgentDismissalOnReload()
      this.checkAgentHealth()
      this.startSafetyNet()
    }
  }

  // The Turbo broadcast is the fast path; this is the guarantee. A broadcast that
  // lands while the page is changing, or before the stream has subscribed, is simply
  // gone, so the register also asks the server for outstanding jobs: right away,
  // shortly after, then every few seconds, and whenever it wakes or reconnects.
  startSafetyNet() {
    this.boundWake = () => { if (!document.hidden) this.sweep() }
    document.addEventListener("visibilitychange", this.boundWake)
    window.addEventListener("online", this.boundWake)
    this.bindFailedPill()
    this.sweep()
    this._earlySweeps = [1000, 4000].map(ms => setTimeout(() => this.sweep(), ms))
    this._poll = setInterval(() => this.sweep(), POLL_INTERVAL_MS)
  }

  stopSafetyNet() {
    clearInterval(this._poll)
    ;(this._earlySweeps || []).forEach(clearTimeout)
    if (this.boundWake) {
      document.removeEventListener("visibilitychange", this.boundWake)
      window.removeEventListener("online", this.boundWake)
    }
    const pill = this.failedPill()
    if (pill && this.boundRetryAll) pill.querySelector("[data-retry-all]")?.removeEventListener("click", this.boundRetryAll)
  }

  async sweep() {
    await this.flushOutbox()
    await this.recoverPendingJobs()
    await this.refreshFailedPill()
  }

  failedPill() {
    return document.getElementById("print-failed-pill")
  }

  bindFailedPill() {
    const button = this.failedPill()?.querySelector("[data-retry-all]")
    if (!button) return
    this.boundRetryAll = () => this.retryAllFailed(button)
    button.addEventListener("click", this.boundRetryAll)
  }

  async refreshFailedPill() {
    const pill = this.failedPill()
    if (!pill || !this.hasFailedUrlValue) return
    try {
      const response = await fetch(this.failedUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) return
      const { count, jobs } = await response.json()
      this._failedJobs = jobs
      pill.querySelector("[data-count]").textContent = count
      pill.classList.toggle("hidden", count === 0)
      this.notifyBannerOffsetChange()
    } catch (_e) {
      // Best-effort; the next sweep tries again.
    }
  }

  async retryAllFailed(button) {
    button.disabled = true
    try {
      for (const job of this._failedJobs || []) {
        await fetch(this.retryUrlTemplateValue.replace(":id", job.id), {
          method: "POST",
          headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content },
          credentials: "same-origin"
        })
      }
    } finally {
      button.disabled = false
      this.sweep()
    }
  }

  clearPrintAgentDismissalOnReload() {
    const [nav] = performance.getEntriesByType("navigation")
    const reloaded = nav?.type ? nav.type === "reload" : performance.navigation?.type === 1
    if (reloaded) sessionStorage.removeItem("saqr_banner_dismissed_print-agent")
  }

  disconnect() {
    this.stopSafetyNet()
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
    if (!printLogId || inFlight.has(printLogId)) return
    inFlight.add(printLogId)
    jobQueue = jobQueue.then(() => this.processJob(printLogId, element))
  }

  // Stable for this browser tab, so a retry (or a page change mid-print) is recognised
  // by the server as the same register that already holds the job.
  get clientId() {
    try {
      let id = sessionStorage.getItem("saqr_print_client")
      if (!id) {
        id = (crypto.randomUUID && crypto.randomUUID()) || `${Date.now()}-${Math.random()}`
        sessionStorage.setItem("saqr_print_client", id)
      }
      return id
    } catch (_e) {
      return this._fallbackClientId ||= `${Date.now()}-${Math.random()}`
    }
  }

  // Every register at the branch hears about a shared job, but only one may print it.
  // Fetching the payload is what claims it; losing the claim means another register
  // is printing it, so stand down quietly — no retry, no "failed" report.
  async processJob(printLogId, element) {
    const done = () => {
      element?.remove()
      inFlight.delete(printLogId)
    }

    let payload
    for (let attempt = 1; ; attempt++) {
      try {
        payload = await this.fetchPayload(printLogId)
        break
      } catch (error) {
        if (error.claimedElsewhere) return done()
        if (error instanceof TypeError) {
          // The server could not be reached: nothing printed. Retry, and if it stays
          // down leave the job pending so a later page load recovers it.
          if (attempt >= MAX_RETRIES) return done()
          await this.sleep(RETRY_DELAY_MS * attempt)
          continue
        }
        await this.confirmReliably(printLogId, "failed", error?.message)
        this.refreshFailedPill()
        return done()
      }
    }

    // Retry only when the agent could not be reached at all (fetch itself failed):
    // then nothing was printed. Once the agent has answered — even with an error —
    // another attempt could print a second copy, so report it and stop.
    let lastError = null
    for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
      try {
        await this.sendToAgent(payload)
      } catch (error) {
        lastError = error
        const unreachable = error instanceof TypeError
        if (!unreachable || attempt === MAX_RETRIES) break
        await this.sleep(RETRY_DELAY_MS * attempt)
        continue
      }
      // The agent has the job. From here on it is never sent again, whatever happens
      // to the confirmation: a lost "sent" must not turn into a second ticket.
      await this.confirmReliably(printLogId, "sent")
      return done()
    }
    await this.confirmReliably(printLogId, "failed", lastError?.message)
    this.refreshFailedPill()
    done()
  }

  // Fetch any pending PrintLogs the browser missed while disconnected
  async recoverPendingJobs() {
    if (!this.hasPendingUrlValue) return
    try {
      const url = `${this.pendingUrlValue}?${new URLSearchParams({ client_id: this.clientId })}`
      const response = await fetch(url, {
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
    if (response.status === 409) {
      const claimed = new Error("already_claimed")
      claimed.claimedElsewhere = true
      throw claimed
    }
    if (!response.ok) {
      const body = await response.json().catch(() => ({}))
      throw new Error(body.error || "Failed to load print payload")
    }
    return response.json()
  }

  payloadUrl(printLogId, register) {
    let url = this.payloadUrlTemplateValue.replace(":id", printLogId)
    const params = new URLSearchParams({ client_id: this.clientId })
    if (register?.host) {
      params.set("host", register.host)
      params.set("port", register.port || "9100")
    }
    return `${url}?${params}`
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

  // Tell the server how the job ended, and keep trying: a job left "pending" gets
  // printed again by the next register that recovers it. If the server stays out of
  // reach, park the answer in localStorage and deliver it on a later sweep.
  async confirmReliably(printLogId, status, errorMessage = null) {
    for (let attempt = 1; attempt <= 4; attempt++) {
      try {
        const response = await this.confirmPrint(printLogId, status, errorMessage)
        // 2xx: recorded. 4xx: the server will never accept it, retrying is pointless.
        if (response.ok || (response.status >= 400 && response.status < 500)) return
      } catch (_e) {
        // network error: fall through to retry
      }
      await this.sleep(500 * attempt)
    }
    this.saveToOutbox({ printLogId, status, errorMessage })
  }

  async confirmPrint(printLogId, status, errorMessage = null) {
    const csrf = document.querySelector('meta[name="csrf-token"]')?.content
    return fetch(this.confirmUrl(printLogId), {
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

  readOutbox() {
    try {
      return JSON.parse(localStorage.getItem(OUTBOX_KEY) || "[]")
    } catch {
      return []
    }
  }

  writeOutbox(entries) {
    try {
      localStorage.setItem(OUTBOX_KEY, JSON.stringify(entries))
    } catch (_e) {
      // storage unavailable: nothing more we can do
    }
  }

  saveToOutbox(entry) {
    const entries = this.readOutbox().filter(e => e.printLogId !== entry.printLogId)
    this.writeOutbox([...entries, entry])
  }

  async flushOutbox() {
    const entries = this.readOutbox()
    if (entries.length === 0) return
    const remaining = []
    for (const entry of entries) {
      try {
        const response = await this.confirmPrint(entry.printLogId, entry.status, entry.errorMessage)
        if (!(response.ok || (response.status >= 400 && response.status < 500))) remaining.push(entry)
      } catch (_e) {
        remaining.push(entry)
      }
    }
    this.writeOutbox(remaining)
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
