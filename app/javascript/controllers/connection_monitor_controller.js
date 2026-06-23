import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"
import { showToast } from "../utils/toast"

// Monitors the ActionCable/Turbo Streams WebSocket connection and shows
// user-facing toasts when the socket drops or recovers.
export default class extends Controller {
  static values = {
    disconnectedMessage: {
      type: String,
      default: "Live connection lost. Prints may be delayed. Refresh the page if the issue persists."
    },
    reconnectedMessage: {
      type: String,
      default: "Connection restored."
    },
    pollInterval: { type: Number, default: 5000 }
  }

  connect() {
    this._wasDisconnected = false
    this._pollTimer = null
    this._startPolling()
  }

  disconnect() {
    this._stopPolling()
  }

  _startPolling() {
    this._pollTimer = setInterval(() => this._checkConnection(), this.pollIntervalValue)
  }

  _stopPolling() {
    clearInterval(this._pollTimer)
  }

  _getConsumer() {
    return cable?.consumer || null
  }

  _checkConnection() {
    // Don't report WebSocket issues when the browser is already offline —
    // connectivity_controller handles the internet-down toast
    if (!navigator.onLine) return

    const consumer = this._getConsumer()
    if (!consumer) return

    const connection = consumer.connection
    const isOpen = connection?.isOpen?.() ?? true

    if (!isOpen && !this._wasDisconnected) {
      this._wasDisconnected = true
      showToast(this.disconnectedMessageValue, { type: "warning", dismissAfter: 0 })
    } else if (isOpen && this._wasDisconnected) {
      this._wasDisconnected = false
      showToast(this.reconnectedMessageValue, { type: "notice", dismissAfter: 4000 })
    }
  }
}
