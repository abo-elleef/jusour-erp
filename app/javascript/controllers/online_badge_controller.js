import { Controller } from "@hotwired/stimulus"

// Beeps on the register when a new self-order arrives (the badge count went up),
// and again on each nudge for a call-center order still waiting (a fresh nudge id
// from OnlineOrders::EscalateJob). What was last seen is kept per branch for this
// tab, so a page change doesn't beep again for the same orders or nudge.
export default class extends Controller {
  static values = { count: Number, key: String, nudge: String, late: Number }

  connect() {
    const storageKey = `online-orders-seen:${this.keyValue}`
    const nudgeKey = `online-orders-nudge:${this.keyValue}`
    let seen = 0
    let seenNudge = ""
    try {
      seen = Number(window.sessionStorage.getItem(storageKey) || 0)
      seenNudge = window.sessionStorage.getItem(nudgeKey) || ""
    } catch (_e) { /* no storage */ }
    const nudged = this.nudgeValue && this.nudgeValue !== seenNudge && this.lateValue > 0
    if (this.countValue > seen || nudged) this.beep()
    try {
      window.sessionStorage.setItem(storageKey, String(this.countValue))
      if (this.nudgeValue) window.sessionStorage.setItem(nudgeKey, this.nudgeValue)
    } catch (_e) { /* no storage */ }
  }

  beep() {
    try {
      const AudioCtx = window.AudioContext || window.webkitAudioContext
      if (!AudioCtx) return
      const ctx = new AudioCtx()
      ;[0, 0.25, 0.5].forEach((at) => {
        const osc = ctx.createOscillator()
        const gain = ctx.createGain()
        osc.frequency.value = 880
        gain.gain.setValueAtTime(0.25, ctx.currentTime + at)
        gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + at + 0.2)
        osc.connect(gain).connect(ctx.destination)
        osc.start(ctx.currentTime + at)
        osc.stop(ctx.currentTime + at + 0.2)
      })
    } catch (_e) {
      // Autoplay blocked until the cashier touches the page; the badge still shows.
    }
  }
}
