import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "connectionType",
    "networkFields",
    "discoverButton",
    "discoverSelect",
    "discoverStatus",
    "host",
    "port",
    "name"
  ]
  static values = {
    config: Object,
    testPayloadUrl: String
  }

  connect() {
    this.toggleNetwork()
  }

  toggleNetwork() {
    const isNetwork = this.connectionTypeTarget.value === "network"
    this.networkFieldsTarget.classList.toggle("hidden", !isNetwork)
  }

  async discover() {
    if (!this.hasDiscoverButtonTarget) return
    this.setDiscoverStatus(this.discoverButtonTarget.dataset.scanningText || "Scanning…")
    this.discoverButtonTarget.disabled = true

    try {
      const body = await this.agentFetch("/discover")
      this.populateDiscoverSelect(body.printers || [])
      this.setDiscoverStatus("")
    } catch (error) {
      this.setDiscoverStatus(error.message)
    } finally {
      this.discoverButtonTarget.disabled = false
    }
  }

  populateDiscoverSelect(printers) {
    if (!this.hasDiscoverSelectTarget) return
    const select = this.discoverSelectTarget
    const empty = select.dataset.emptyText || "No printers found"
    select.innerHTML = ""
    select.classList.remove("hidden")

    if (printers.length === 0) {
      const option = document.createElement("option")
      option.textContent = empty
      option.value = ""
      select.appendChild(option)
      return
    }

    const placeholder = document.createElement("option")
    placeholder.textContent = select.dataset.placeholderText || "Select a printer…"
    placeholder.value = ""
    select.appendChild(placeholder)

    printers.forEach((printer) => {
      const option = document.createElement("option")
      option.value = JSON.stringify(printer)
      option.textContent = printer.host
        ? `${printer.name} (${printer.host}:${printer.port || 9100})`
        : `${printer.name} (set IP manually)`
      select.appendChild(option)
    })
  }

  applyDiscovery(event) {
    const raw = event.target.value
    if (!raw) return
    const printer = JSON.parse(raw)
    if (this.hasHostTarget && printer.host) this.hostTarget.value = printer.host
    if (this.hasPortTarget) this.portTarget.value = printer.port || 9100
    if (this.hasNameTarget && !this.nameTarget.value) this.nameTarget.value = printer.name
  }

  async testViaAgent(event) {
    event.preventDefault()
    const button = event.currentTarget
    const original = button.textContent
    button.disabled = true
    button.textContent = button.dataset.printingText || "Printing…"

    try {
      const response = await fetch(this.testPayloadUrlValue, {
        headers: { Accept: "application/json" },
        credentials: "same-origin"
      })
      const payload = await response.json()
      if (!response.ok) throw new Error(payload.error || "Failed to build test page")

      await this.agentFetch("/print", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          host: payload.host,
          port: payload.port,
          data_base64: payload.data_base64
        })
      })
      alert(button.dataset.successText || "Test page sent to printer.")
    } catch (error) {
      alert(error.message)
    } finally {
      button.disabled = false
      button.textContent = original
    }
  }

  setDiscoverStatus(message) {
    if (!this.hasDiscoverStatusTarget) return
    this.discoverStatusTarget.textContent = message
  }

  async agentFetch(path, options = {}) {
    const headers = { ...(options.headers || {}), ...this.agentHeaders() }
    const response = await fetch(`${this.configValue.url}${path}`, { ...options, headers })
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
}
