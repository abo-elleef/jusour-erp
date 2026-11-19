import { Controller } from "@hotwired/stimulus"

// Live notifications in the admin layout. Cards arrive over the user's own
// Turbo stream (Notifications::Broadcast) and are prepended into the container;
// each one slides in, rings once, and stays until the user opens or closes it.
//
// When the live connection drops and comes back (bad Wi-Fi, laptop sleep), the
// bell count is fetched again, since pushes sent meanwhile were lost.
const MAX_VISIBLE = 4

export default class extends Controller {
  static targets = ["container", "item"]
  static values = { badgeUrl: String }

  connect() {
    this.source = this.element.querySelector("turbo-cable-stream-source")
    if (!this.source) return

    this.wasConnected = this.source.hasAttribute("connected")
    this.lostConnection = false
    this.observer = new MutationObserver(() => this.connectionChanged())
    this.observer.observe(this.source, { attributes: true, attributeFilter: ["connected"] })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  itemTargetConnected(item) {
    // The same notification can't show twice (e.g. a duplicate delivery).
    const id = item.dataset.notificationId
    const twins = this.itemTargets.filter((other) => other !== item && other.dataset.notificationId === id)
    if (twins.length > 0) { item.remove(); return }

    this.animateIn(item)
    this.ring()
    // Newest first; drop the oldest beyond the cap — they stay in the bell list.
    this.itemTargets.slice(MAX_VISIBLE).forEach((old) => old.remove())
  }

  dismiss(event) {
    const item = event.currentTarget.closest("[data-notification-popups-target='item']")
    if (!item) return

    item.style.transition = "opacity 0.2s ease, transform 0.2s ease"
    item.style.opacity = "0"
    item.style.transform = "translateY(-0.5rem)"
    window.setTimeout(() => item.remove(), 200)
  }

  connectionChanged() {
    const connected = this.source.hasAttribute("connected")
    if (!connected && this.wasConnected) this.lostConnection = true
    if (connected && this.lostConnection) {
      this.lostConnection = false
      this.refreshBadge()
    }
    this.wasConnected = connected
  }

  async refreshBadge() {
    if (!this.hasBadgeUrlValue) return
    try {
      const resp = await fetch(this.badgeUrlValue, {
        headers: { Accept: "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
      if (resp.ok) window.Turbo.renderStreamMessage(await resp.text())
    } catch (_e) {
      // Still offline; the next reconnect tries again.
    }
  }

  animateIn(item) {
    item.style.opacity = "0"
    item.style.transform = "translateY(-0.5rem) scale(0.98)"
    window.requestAnimationFrame(() => {
      item.style.transition = "opacity 0.3s ease, transform 0.3s ease"
      item.style.opacity = "1"
      item.style.transform = "translateY(0) scale(1)"
    })
  }

  // Two short tones; several cards arriving together ring once.
  ring() {
    const now = Date.now()
    if (this.lastRing && now - this.lastRing < 1500) return
    this.lastRing = now
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext
      if (!AudioCtx) return
      const ctx = new AudioCtx()
      ;[[0, 660], [0.18, 880]].forEach(([at, freq]) => {
        const osc = ctx.createOscillator()
        const gain = ctx.createGain()
        osc.frequency.value = freq
        gain.gain.setValueAtTime(0.2, ctx.currentTime + at)
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + at + 0.18)
        osc.connect(gain).connect(ctx.destination)
        osc.start(ctx.currentTime + at)
        osc.stop(ctx.currentTime + at + 0.18)
      })
    } catch (_e) {
      // Autoplay blocked until the user has touched the page; the card still shows.
    }
  }
}
