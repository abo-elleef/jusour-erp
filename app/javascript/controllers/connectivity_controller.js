import { Controller } from "@hotwired/stimulus"
import { showToast } from "utils/toast"

export default class extends Controller {
  static targets = ["banner", "cardPaymentBtn", "syncStatus"]
  static values = { online: Boolean }

  connect() {
    this.boundOnline = () => this.handleOnline()
    this.boundOffline = () => this.handleOffline()
    this.onlineValue = navigator.onLine
    window.addEventListener("online", this.boundOnline)
    window.addEventListener("offline", this.boundOffline)
    this.updateUI()
  }

  disconnect() {
    window.removeEventListener("online", this.boundOnline)
    window.removeEventListener("offline", this.boundOffline)
  }

  handleOnline() {
    this.onlineValue = true
    this.updateUI()
    this.triggerSync()
    this.clearOfflineDismissal()
    this.showBanner(this.bannerOnlineMessage(), "success")
    setTimeout(() => this.hideBanner(), 4000)
    showToast(this.bannerOnlineMessage(), { type: "notice", dismissAfter: 5000 })
  }

  handleOffline() {
    this.onlineValue = false
    this.updateUI()
    this.showBanner(this.bannerOfflineMessage(), "offline")
    showToast(this.bannerOfflineMessage(), { type: "alert", dismissAfter: 0 })
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

  triggerSync() {
    if ("serviceWorker" in navigator && "SyncManager" in window) {
      navigator.serviceWorker.ready.then((sw) => sw.sync.register("sync-offline-payments"))
    } else {
      this.dispatch("sync-requested", { bubbles: true })
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
