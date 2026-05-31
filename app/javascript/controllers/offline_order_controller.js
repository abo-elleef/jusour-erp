import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { csrfToken: String, savedMessage: String }

  connect() {
    this.element.addEventListener("connectivity:sync-requested", () => this.syncAll())
  }

  async queuePayment(paymentData) {
    const db = await this.openDB()
    const tx = db.transaction("payments", "readwrite")
    await new Promise((resolve, reject) => {
      const req = tx.objectStore("payments").add({
        data: paymentData,
        csrfToken: this.csrfTokenValue,
        savedAt: Date.now()
      })
      req.onsuccess = () => resolve()
      req.onerror = () => reject(req.error)
    })
  }

  async syncAll() {
    const db = await this.openDB()
    const tx = db.transaction("payments", "readonly")
    const payments = await this.getAll(tx.objectStore("payments"))
    let synced = 0

    for (const entry of payments) {
      const ok = await this.postPayment(entry)
      if (ok) {
        const delTx = db.transaction("payments", "readwrite")
        await new Promise((resolve, reject) => {
          const req = delTx.objectStore("payments").delete(entry.id)
          req.onsuccess = () => resolve()
          req.onerror = () => reject(req.error)
        })
        synced++
      }
    }
    return synced
  }

  async postPayment(entry) {
    try {
      const resp = await fetch("/pos/orders/sync", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-CSRF-Token": entry.csrfToken
        },
        body: JSON.stringify({ order: entry.data })
      })
      return resp.ok
    } catch {
      return false
    }
  }

  openDB() {
    return new Promise((resolve, reject) => {
      const req = indexedDB.open("pos-offline", 1)
      req.onupgradeneeded = (e) => {
        if (!e.target.result.objectStoreNames.contains("payments")) {
          e.target.result.createObjectStore("payments", { keyPath: "id", autoIncrement: true })
        }
      }
      req.onsuccess = (e) => resolve(e.target.result)
      req.onerror = (e) => reject(e.target.error)
    })
  }

  getAll(store) {
    return new Promise((resolve, reject) => {
      const req = store.getAll()
      req.onsuccess = () => resolve(req.result)
      req.onerror = () => reject(req.error)
    })
  }
}
