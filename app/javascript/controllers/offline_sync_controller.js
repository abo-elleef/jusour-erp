import { Controller } from "@hotwired/stimulus"
import { showToast } from "utils/toast"
import { prepareOffline, queuedCount, isReachable, syncQueuedOrders } from "utils/offline_sync"
import { deleteMeta } from "utils/offline_db"

const REFRESH_MS = 5 * 60 * 1000

// Lives on every online POS page. It keeps this computer ready for an outage —
// a fresh menu snapshot in IndexedDB and the offline register page in the service
// worker's cache — and delivers any orders rung up offline since the last time.
export default class extends Controller {
  static targets = ["banner", "message"]
  static values = { queuedMessage: String, syncedMessage: String }

  connect() {
    // Back on the online register, the order it shows is the live one again. A
    // handoff saved for the offline register is stale from here on (it may get
    // paid online), so it must not reappear the next time the offline page opens.
    deleteMeta("handoff").catch(() => {})
    this.onOnline = () => this.run()
    window.addEventListener("pos:online", this.onOnline)
    this.timer = setInterval(() => this.run(), REFRESH_MS)
    this.run()
  }

  disconnect() {
    window.removeEventListener("pos:online", this.onOnline)
    clearInterval(this.timer)
  }

  async run() {
    if (this.running || !(await isReachable())) return
    this.running = true

    try {
      const result = await syncQueuedOrders()
      if (result.synced) showToast(this.fill(this.syncedMessageValue, result.synced), { type: "notice", dismissAfter: 6000 })
      await prepareOffline()
    } catch {
      // Preparing for an outage must never get in the way of taking orders.
    } finally {
      this.running = false
      this.showPending(await queuedCount())
    }
  }

  fill(template, count) {
    return template.replace("%{count}", count)
  }

  showPending(count) {
    if (!this.hasBannerTarget) return
    if (this.hasMessageTarget) this.messageTarget.textContent = this.fill(this.queuedMessageValue, count)
    this.bannerTarget.classList.toggle("hidden", count === 0)
    requestAnimationFrame(() => document.dispatchEvent(new CustomEvent("pos-banners:changed")))
  }
}
