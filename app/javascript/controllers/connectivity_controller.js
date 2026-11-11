import { Controller } from "@hotwired/stimulus"
import { showToast } from "utils/toast"
import { isOfflineReady, isReachable, saveHandoff } from "utils/offline_sync"

const HEARTBEAT_MS = 8000
const FAILURES_BEFORE_OFFLINE = 2

// Decides whether the internet is really there.
//
// The browser's own online/offline events are not enough: a router with a dead
// uplink still reads as "online", which is exactly the restaurant's situation. So
// this asks our own server every few seconds. After two misses in a row the POS
// hands over to the offline register (which only needs this computer and the LAN)
// and hands back when the server answers again.
export default class extends Controller {
  static targets = ["banner", "cardPaymentBtn"]
  static values = { online: Boolean, offlineUrl: String }

  connect() {
    this.failures = 0
    this.onlineValue = true
    this.boundCheck = () => this.check()
    window.addEventListener("online", this.boundCheck)
    window.addEventListener("offline", this.boundCheck)
    this.timer = setInterval(this.boundCheck, HEARTBEAT_MS)
    this.updateUI()
  }

  disconnect() {
    window.removeEventListener("online", this.boundCheck)
    window.removeEventListener("offline", this.boundCheck)
    clearInterval(this.timer)
  }

  async check() {
    if (await isReachable()) {
      this.failures = 0
      if (!this.onlineValue) this.handleOnline()
    } else {
      this.failures += 1
      if (this.failures >= FAILURES_BEFORE_OFFLINE && this.onlineValue) this.handleOffline()
    }
  }

  handleOnline() {
    this.onlineValue = true
    this.updateUI()
    this.clearOfflineDismissal()
    this.showBanner(this.bannerOnlineMessage(), "success")
    setTimeout(() => this.hideBanner(), 4000)
    showToast(this.bannerOnlineMessage(), { type: "notice", dismissAfter: 5000 })
    window.dispatchEvent(new CustomEvent("pos:online"))
  }

  handleOffline() {
    this.onlineValue = false
    this.updateUI()
    this.showBanner(this.bannerOfflineMessage(), "offline")
    showToast(this.bannerOfflineMessage(), { type: "alert", dismissAfter: 0 })
    this.enterOfflineMode()
  }

  // Switch to the cached offline register, if this computer has been prepared for
  // it (it is, after any POS page has loaded online once). The order on screen goes
  // with it, so the cashier carries on instead of ringing it up again.
  async enterOfflineMode() {
    if (!this.hasOfflineUrlValue || !this.offlineUrlValue) return
    if (!(await isOfflineReady())) return

    await saveHandoff()
    window.location.assign(this.offlineUrlValue)
  }

  bannerOfflineMessage() {
    return this.element.dataset.offlineMessage || "You are offline. Cash payments only."
  }

  bannerOnlineMessage() {
    return this.element.dataset.onlineMessage || "Back online — syncing queued payments..."
  }

  updateUI() {
    if (this.hasCardPaymentBtnTarget) {
      this.cardPaymentBtnTargets.forEach((btn) => {
        btn.disabled = !this.onlineValue
        btn.title = this.onlineValue ? "" : "Card payments require internet"
        btn.classList.toggle("opacity-50", !this.onlineValue)
        btn.classList.toggle("cursor-not-allowed", !this.onlineValue)
      })
    }
  }

  showBanner(message, type) {
    if (!this.hasBannerTarget) return

    const banner = this.bannerTarget
    const messageEl = banner.querySelector("[data-connectivity-banner-message]")
    if (messageEl) messageEl.textContent = message

    const offlineClasses = ["bg-yellow-500", "text-yellow-900", "border-yellow-600"]
    const successClasses = ["bg-green-600", "text-white", "border-green-700"]
    banner.classList.remove(...offlineClasses, ...successClasses)
    ;(type === "offline" ? offlineClasses : successClasses).forEach((klass) => banner.classList.add(klass))

    if (type === "success") {
      banner.classList.remove("hidden")
      this.notifyBannerOffsetChange()
      return
    }

    this.dismissibleBanner(banner)?.show() || banner.classList.remove("hidden")
    this.notifyBannerOffsetChange()
  }

  hideBanner() {
    this.dismissibleBanner(this.bannerTarget)?.hide() || this.bannerTarget?.classList.add("hidden")
    this.notifyBannerOffsetChange()
  }

  notifyBannerOffsetChange() {
    requestAnimationFrame(() => {
      document.dispatchEvent(new CustomEvent("pos-banners:changed"))
    })
  }

  clearOfflineDismissal() {
    sessionStorage.removeItem("saqr_banner_dismissed_connectivity-offline")
  }

  dismissibleBanner(element) {
    if (!element) return null
    return this.application.getControllerForElementAndIdentifier(element, "dismissible-banner")
  }
}
