import { Controller } from "@hotwired/stimulus"

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
    this.showBanner(this.bannerOnlineMessage(), "success")
    setTimeout(() => this.hideBanner(), 4000)
  }

  handleOffline() {
    this.onlineValue = false
    this.updateUI()
    this.showBanner(this.bannerOfflineMessage(), "warning")
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
    this.bannerTarget.textContent = message
    this.bannerTarget.className = `fixed top-0 left-0 right-0 z-[60] px-4 py-3 text-sm font-medium text-center ${
      type === "warning" ? "bg-yellow-500 text-yellow-900" : "bg-green-600 text-white"
    }`
    this.bannerTarget.classList.remove("hidden")
  }

  hideBanner() {
    if (this.hasBannerTarget) this.bannerTarget.classList.add("hidden")
  }
}
