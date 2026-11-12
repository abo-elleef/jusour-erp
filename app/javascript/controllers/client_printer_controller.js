import { Controller } from "@hotwired/stimulus"

const MAX_RETRIES = 3
const RETRY_DELAY_MS = 2000
const POLL_INTERVAL_MS = 10000
const OUTBOX_KEY = "saqr_print_outbox"
// A register whose print agent does not answer leaves shared tickets (kitchen, bar,
// expo) to the registers that can print them. Only once a ticket has waited this
// long with nobody printing it does such a register take it, and fail it, so the
// failure shows up for a cashier instead of the ticket waiting silently.
const SHARED_GRACE_SECONDS = 45
const HEALTH_TTL_MS = 5000
const HEALTH_TIMEOUT_MS = 2000

// Module scope on purpose. Turbo replaces the page body on every navigation, which
// builds a fresh controller; if the queue and the in-flight set lived on the
// instance, the new page could pick up a job the old page is still printing and
// print it a second time.
const inFlight = new Set()
let jobQueue = Promise.resolve()
let agentHealth = null // { ok, at }

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
    ;(this._failedListeners || []).forEach(([el, type, fn]) => el.removeEventListener(type, fn))
    this._failedListeners = []
  }

  async sweep() {
    await this.flushOutbox()
    await this.recoverPendingJobs()
    await this.refreshFailedPill()
  }

  failedPill() {
    return document.getElementById("print-failed-pill")
  }

  failedDialog() {
    return document.getElementById("print-failed-dialog")
  }

  // The pill and the panel live in the layout, outside this controller's element,
  // so their buttons are wired by hand and unwired on disconnect.
  bindFailedPill() {
    this._failedListeners = []
    const on = (el, type, fn) => {
      if (!el) return
      el.addEventListener(type, fn)
      this._failedListeners.push([el, type, fn])
    }
    const pill = this.failedPill()
    const dialog = this.failedDialog()
    pill?.querySelectorAll("[data-retry-all]").forEach(b => on(b, "click", () => this.retryAllFailed(b)))
    pill?.querySelectorAll("[data-open-details]").forEach(b => on(b, "click", () => this.openFailedDialog()))
    dialog?.querySelectorAll("[data-retry-all]").forEach(b => on(b, "click", () => this.retryAllFailed(b)))
    dialog?.querySelectorAll("[data-close-dialog]").forEach(b => on(b, "click", () => dialog.close()))
  }

  async refreshFailedPill() {
    const pill = this.failedPill()
    if (!pill || !this.hasFailedUrlValue) return
    try {
      const response = await fetch(this.failedUrlValue, { headers: { Accept: "application/json" }, credentials: "same-origin" })
      if (!response.ok) return
      const summary = await response.json()
      this._failedSummary = summary
      pill.querySelector("[data-count]").textContent = summary.count
      pill.classList.toggle("hidden", summary.count === 0)
      // A missed kitchen / pickup ticket is food nobody is cooking: make it hard to miss.
      const urgent = summary.production_count > 0
      pill.classList.toggle("animate-pulse", urgent)
      pill.classList.toggle("ring-4", urgent)
      pill.classList.toggle("ring-red-400", urgent)
      if (this.failedDialog()?.open) this.renderFailedDialog()
      this.notifyBannerOffsetChange()
    } catch (_e) {
      // Best-effort; the next sweep tries again.
    }
  }

  failedJobs() {
    return (this._failedSummary?.groups || []).flatMap(g => g.jobs)
  }

  async retryAllFailed(button) {
    await this.retryJobs(this.failedJobs(), button)
  }

  async retryJobs(jobs, button) {
    if (button) button.disabled = true
    try {
      for (const job of jobs) await this.postToJob(this.retryUrlTemplateValue, job.id)
    } finally {
      if (button) button.disabled = false
      this.sweep()
    }
  }

  async handleJobs(jobs, button) {
    const labels = this.failedLabels()
    if (!window.confirm(labels.handled_confirm)) return
    const template = this.failedDialog()?.dataset.handleUrlTemplate
    if (!template) return
    if (button) button.disabled = true
    try {
      for (const job of jobs) await this.postToJob(template, job.id)
    } finally {
      if (button) button.disabled = false
      this.refreshFailedPill()
    }
  }

  postToJob(template, id) {
    return fetch(template.replace(":id", id), {
      method: "POST",
      headers: { Accept: "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content },
      credentials: "same-origin"
    }).catch(() => null)
  }

  failedLabels() {
    try {
      return JSON.parse(this.failedDialog()?.dataset.labels || "{}")
    } catch (_e) {
      return {}
    }
  }

  async openFailedDialog() {
    const dialog = this.failedDialog()
    if (!dialog) return
    this.renderFailedDialog({ force: true })
    if (!dialog.open) dialog.showModal()
    await this.refreshFailedPill()
  }

  // Built with textContent throughout: error messages come from printers and agents.
  renderFailedDialog({ force = false } = {}) {
    const dialog = this.failedDialog()
    if (!dialog) return
    const summary = this._failedSummary || { count: 0, groups: [] }
    // Redraw only when the failed tickets change: a redraw on every poll would pull
    // buttons out from under the cashier's finger.
    const signature = summary.groups.map(g => `${g.key}:${g.jobs.map(j => j.id).join(",")}`).join("|")
    if (!force && dialog.dataset.signature === signature) return
    dialog.dataset.signature = signature
    const labels = this.failedLabels()
    dialog.querySelector("[data-dialog-count]").textContent = summary.count
    dialog.querySelector("[data-empty]").classList.toggle("hidden", summary.count > 0)
    dialog.querySelectorAll("[data-retry-all]").forEach(b => b.classList.toggle("hidden", summary.count === 0))

    const container = dialog.querySelector("[data-groups]")
    const openKeys = new Set([...container.querySelectorAll("details[open]")].map(d => d.dataset.key))
    container.replaceChildren(...summary.groups.map(g => this.buildGroupCard(g, labels, summary.support_url, openKeys)))
  }

  el(tag, className, text) {
    const node = document.createElement(tag)
    if (className) node.className = className
    if (text !== undefined && text !== null) node.textContent = text
    return node
  }

  buildGroupCard(group, labels, supportUrl, openKeys) {
    const tone = group.production
      ? "border-red-400 bg-white ring-2 ring-red-200"
      : "border-amber-300 bg-white"
    const card = this.el("section", `rounded-2xl border ${tone} shadow-sm overflow-hidden`)
    card.dataset.groupKey = group.key

    // Header: printer, where it is, and whether the kitchen is affected.
    const head = this.el("div", `px-4 py-3 flex flex-wrap items-center gap-2 ${group.production ? "bg-red-50" : "bg-amber-50"}`)
    head.append(this.el("span", "text-base", group.production ? "🔴" : "🟠"))
    head.append(this.el("span", "font-bold text-stone-900", group.printer))
    if (group.host) {
      const host = this.el("bdi", "text-xs font-mono text-stone-500", group.host)
      host.dir = "ltr"
      head.append(host)
    }
    head.append(this.el("span",
      `ms-auto text-xs font-semibold rounded-full px-2.5 py-1 ${group.production ? "bg-red-700 text-white" : "bg-amber-200 text-amber-900"}`,
      group.production ? labels.production_badge : labels.receipt_badge))
    card.append(head)

    const body = this.el("div", "px-4 py-3 space-y-3")
    const summary = this.el("p", "text-sm")
    summary.append(this.el("span", "font-bold text-red-800", group.title))
    const orders = [...new Set(group.jobs.map(j => j.order_number).filter(n => n !== null && n !== undefined))]
    if (orders.length) {
      summary.append(this.el("span", "text-stone-600", " — "))
      orders.forEach((n, i) => {
        if (i > 0) summary.append(this.el("span", "text-stone-600", "، "))
        summary.append(this.orderNumber(n, "text-stone-700 font-semibold"))
      })
    }
    body.append(summary)
    body.append(this.el("p", "text-sm font-medium text-stone-800", group.reason))

    if (group.checks?.length) {
      const checks = this.el("div", "rounded-xl bg-stone-50 border border-stone-200 px-3 py-2")
      checks.append(this.el("p", "text-xs font-semibold text-stone-500 mb-1", labels.check_title))
      const list = this.el("ul", "text-sm space-y-1")
      group.checks.forEach(c => list.append(this.el("li", "flex gap-2", `☐ ${c}`)))
      checks.append(list)
      body.append(checks)
    }

    // Actions for the whole problem.
    const actions = this.el("div", "flex flex-wrap gap-2")
    const retry = this.el("button", "rounded-lg bg-red-700 hover:bg-red-800 disabled:opacity-60 text-white text-sm font-semibold px-3 py-2 min-h-10", `${labels.retry_group} (${group.jobs.length})`)
    retry.type = "button"
    retry.addEventListener("click", () => this.retryJobs(group.jobs, retry))
    const handled = this.el("button", "rounded-lg border border-stone-300 bg-white hover:bg-stone-50 disabled:opacity-60 text-sm font-semibold px-3 py-2 min-h-10", labels.handled_group)
    handled.type = "button"
    handled.addEventListener("click", () => this.handleJobs(group.jobs, handled))
    actions.append(retry, handled)
    actions.append(this.buildSupportButton(group, labels, supportUrl))
    body.append(actions)

    // The tickets themselves, folded away until asked for.
    const details = this.el("details", "rounded-xl border border-stone-200 bg-white")
    details.dataset.key = group.key
    if (openKeys.has(group.key)) details.open = true
    details.append(this.el("summary", "cursor-pointer select-none px-3 py-2 text-sm font-semibold text-stone-700", `${labels.show_tickets} (${group.jobs.length})`))
    details.append(this.buildJobsTable(group.jobs, labels))
    body.append(details)

    card.append(body)
    return card
  }

  // "#12" kept left-to-right so it does not turn into "12#" inside Arabic text.
  orderNumber(number, className = "") {
    const bdi = this.el("bdi", className, `#${number}`)
    bdi.dir = "ltr"
    return bdi
  }

  buildJobsTable(jobs, labels) {
    const wrap = this.el("div", "overflow-x-auto")
    const table = this.el("table", "w-full text-sm")
    const thead = this.el("thead", "bg-stone-50 text-stone-500 text-xs")
    const hr = this.el("tr")
    ;[labels.col_order, labels.col_ticket, labels.col_printer, labels.col_ordered_at, labels.col_failed_at, labels.col_error, ""]
      .forEach(h => hr.append(this.el("th", "px-3 py-2 text-start font-semibold whitespace-nowrap", h)))
    thead.append(hr)
    const tbody = this.el("tbody", "divide-y divide-stone-100")
    jobs.forEach(job => {
      const tr = this.el("tr", "align-top")
      const orderCell = this.el("td", "px-3 py-2 font-semibold whitespace-nowrap")
      if (job.order_url) {
        const a = this.el("a", "text-sky-700 hover:underline")
        a.append(this.orderNumber(job.order_number))
        a.href = job.order_url
        a.dataset.turboFrame = "_top"
        orderCell.append(a)
      } else {
        orderCell.textContent = labels.no_order
      }
      tr.append(orderCell)
      tr.append(this.el("td", `px-3 py-2 whitespace-nowrap ${job.production ? "text-red-800 font-semibold" : ""}`, job.ticket))
      tr.append(this.el("td", "px-3 py-2 whitespace-nowrap", job.printer || "—"))
      tr.append(this.el("td", "px-3 py-2 whitespace-nowrap tabular-nums", job.ordered_at || "—"))
      tr.append(this.el("td", "px-3 py-2 whitespace-nowrap tabular-nums", job.failed_at || "—"))
      tr.append(this.el("td", "px-3 py-2 font-mono text-xs text-stone-600 min-w-[14rem] break-words", job.error || "—"))
      const act = this.el("td", "px-3 py-2 whitespace-nowrap text-end")
      const r = this.el("button", "rounded-md bg-red-700 hover:bg-red-800 disabled:opacity-60 text-white text-xs font-semibold px-2.5 py-1.5 me-1", labels.retry)
      r.type = "button"
      r.addEventListener("click", () => this.retryJobs([job], r))
      const h = this.el("button", "rounded-md border border-stone-300 hover:bg-stone-50 disabled:opacity-60 text-xs font-semibold px-2.5 py-1.5", labels.handled)
      h.type = "button"
      h.addEventListener("click", () => this.handleJobs([job], h))
      act.append(r, h)
      tr.append(act)
      tbody.append(tr)
    })
    table.append(thead, tbody)
    wrap.append(table)
    return wrap
  }

  // WhatsApp when the support number is set; otherwise copy the report to paste anywhere.
  buildSupportButton(group, labels, supportUrl) {
    const button = this.el("button", "rounded-lg border border-emerald-600 text-emerald-800 bg-white hover:bg-emerald-50 text-sm font-semibold px-3 py-2 min-h-10",
      supportUrl ? labels.send_support : labels.copy_report)
    button.type = "button"
    button.addEventListener("click", async () => {
      // The latest copy of this group, so the report's time and tickets are current.
      const latest = (this._failedSummary?.groups || []).find(g => g.key === group.key) || group
      const report = await this.reportWithAgentStatus(latest.report, labels)
      if (supportUrl) {
        window.open(`${supportUrl}?text=${encodeURIComponent(report)}`, "_blank", "noopener")
        return
      }
      try {
        await navigator.clipboard.writeText(report)
        button.textContent = labels.copied
        setTimeout(() => { button.textContent = labels.copy_report }, 3000)
      } catch (_e) {
        window.prompt(labels.copy_report, report)
      }
    })
    return button
  }

  // The one fact only this browser knows: is the print agent on this register alive?
  async reportWithAgentStatus(report, labels) {
    let ok = false
    try {
      ok = Boolean(await this.agentFetch("/health"))
    } catch (_e) {
      ok = false
    }
    return `${report}\n${labels.agent}: ${ok ? labels.agent_ok : labels.agent_down}`
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
    // A broadcast job has only just been queued.
    this.enqueueJob(element.dataset.printLogId, element, { shared: element.dataset.shared === "true", age: 0 })
  }

  // Serial queue: each job waits for the previous to finish
  enqueueJob(printLogId, element, meta = {}) {
    if (!printLogId || inFlight.has(printLogId)) return
    inFlight.add(printLogId)
    jobQueue = jobQueue.then(() => this.processJob(printLogId, element, meta))
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
  async processJob(printLogId, element, { shared = false, age = 0 } = {}) {
    const done = () => {
      element?.remove()
      inFlight.delete(printLogId)
    }

    // Without a working agent this register would claim the ticket and then fail
    // it, while a register next to it could have printed it. Stand aside; the
    // job stays pending and the next sweep offers it again.
    if (shared && age < SHARED_GRACE_SECONDS && !(await this.agentHealthy())) return done()

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
        this.enqueueJob(job.id, null, { shared: job.shared === true, age: job.age || 0 })
      }
    } catch (_e) {
      // Recovery is best-effort; silent fail
    }
  }

  // Is the print agent on this machine answering? Cached briefly, and bounded by a
  // timeout so a dead agent cannot stall the print queue.
  async agentHealthy() {
    if (agentHealth && Date.now() - agentHealth.at < HEALTH_TTL_MS) return agentHealth.ok
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), HEALTH_TIMEOUT_MS)
    let ok = false
    try {
      ok = Boolean(await this.agentFetch("/health", { signal: controller.signal }))
    } catch (_e) {
      ok = false
    } finally {
      clearTimeout(timer)
    }
    agentHealth = { ok, at: Date.now() }
    return ok
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
