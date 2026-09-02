import { Controller } from "@hotwired/stimulus"

// Manages the stock take count sheet (in_progress state):
//   - Auto-saves counts 1.5 s after the user stops typing
//   - Group-by toggle buttons flush any pending save before navigating
export default class extends Controller {
  static targets = ["form", "status"]
  static values  = { saveUrl: String }

  connect() {
    this._timer  = null
    this._saving = false
    this._dirty  = false

    if (this.hasFormTarget) {
      this.formTarget.addEventListener("input",  this._onInput.bind(this))
      this.formTarget.addEventListener("change", this._onInput.bind(this))
    }
  }

  disconnect() {
    clearTimeout(this._timer)
  }

  // data-action="click->stock-take-group#switchGroup" on every group-by link
  switchGroup(event) {
    if (!this._dirty && !this._saving) return  // nothing pending — navigate normally

    event.preventDefault()
    const destination = event.currentTarget.href
    clearTimeout(this._timer)
    this._saveNow().then(() => { window.location.href = destination })
  }

  // ── private ────────────────────────────────────────────────────────────────

  _onInput() {
    this._dirty = true
    this._setStatus("unsaved")
    clearTimeout(this._timer)
    this._timer = setTimeout(() => this._saveNow(), 1500)
  }

  async _saveNow() {
    if (!this.hasFormTarget || this._saving) return Promise.resolve()
    this._saving = true
    this._setStatus("saving")

    const form = this.formTarget
    const data = new FormData(form)

    try {
      const resp = await fetch(this.saveUrlValue || form.action, {
        method: "POST",
        headers: {
          "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || "",
          "X-Requested-With": "XMLHttpRequest",
          "Accept": "text/html, application/json"
        },
        body: data,
        redirect: "follow"
      })

      if (resp.ok || resp.redirected) {
        this._dirty = false
        this._setStatus("saved")
        setTimeout(() => this._setStatus("idle"), 2500)
      } else {
        this._setStatus("error")
      }
    } catch {
      this._setStatus("error")
    } finally {
      this._saving = false
    }
  }

  _setStatus(state) {
    if (!this.hasStatusTarget) return
    const map = {
      idle:    ["", ""],
      unsaved: ["Unsaved…",       "text-amber-600"],
      saving:  ["Saving…",        "text-gray-400"],
      saved:   ["✓ Saved",        "text-emerald-600"],
      error:   ["⚠ Save failed",  "text-red-600"]
    }
    const [text, cls] = map[state] || map.idle
    this.statusTarget.textContent = text
    this.statusTarget.className   = `text-xs font-semibold transition-colors ${cls}`
  }
}
