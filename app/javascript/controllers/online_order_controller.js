import { Controller } from "@hotwired/stimulus"

// Customer self-ordering on the public menu.
//
// The cart lives in localStorage (per branch) and only holds ids, counts and the
// names to show. Every price the customer sees in the checkout comes from the
// server's quote, and the order itself is priced again on the server when sent.
export default class extends Controller {
  static targets = [
    "itemDialog", "itemName", "itemPrice", "itemGroups", "itemNote", "itemError", "itemQuantity",
    "cartBar", "cartCount",
    "checkoutDialog", "checkoutForm", "lines", "deliveryFields", "feeRow",
    "subtotal", "fee", "total", "checkoutError", "sendButton"
  ]

  static values = {
    quoteUrl: String,
    createUrl: String,
    storageKey: String,
    startedAt: String,
    pickRequired: String,
    requiredLabel: String
  }

  connect() {
    this.cart = this.load()
    this.renderBar()
  }

  // ---- item popup -------------------------------------------------------

  open(event) {
    this.item = JSON.parse(event.currentTarget.dataset.item)
    this.quantity = 1
    this.itemNameTarget.textContent = this.item.name
    this.itemPriceTarget.textContent = this.item.price
    this.itemNoteTarget.value = ""
    this.itemQuantityTarget.textContent = "1"
    this.hideError(this.itemErrorTarget)
    this.itemGroupsTarget.replaceChildren(...this.item.groups.map((group) => this.groupFieldset(group)))
    this.itemDialogTarget.showModal()
  }

  closeItem() {
    this.itemDialogTarget.close()
  }

  increment() {
    this.quantity = Math.min(this.quantity + 1, 99)
    this.itemQuantityTarget.textContent = String(this.quantity)
  }

  decrement() {
    this.quantity = Math.max(this.quantity - 1, 1)
    this.itemQuantityTarget.textContent = String(this.quantity)
  }

  groupFieldset(group) {
    const fieldset = document.createElement("fieldset")
    fieldset.dataset.groupId = group.id
    const legend = document.createElement("legend")
    legend.className = "mb-2 flex items-center gap-2 text-sm font-semibold text-stone-900"
    legend.textContent = group.name
    if (group.required) {
      const badge = document.createElement("span")
      badge.className = "rounded-full bg-amber-100 px-2 py-0.5 text-[11px] font-medium text-amber-900"
      badge.textContent = this.requiredLabelValue
      legend.append(badge)
    }
    fieldset.append(legend)

    const list = document.createElement("div")
    list.className = "space-y-1.5"
    group.modifiers.forEach((mod) => {
      const label = document.createElement("label")
      label.className = "flex cursor-pointer items-center justify-between gap-3 rounded-lg border border-stone-200 px-3 py-2.5 text-sm has-[:checked]:border-amber-600 has-[:checked]:bg-amber-50"
      const left = document.createElement("span")
      left.className = "flex items-center gap-2.5"
      const input = document.createElement("input")
      input.type = group.multi ? "checkbox" : "radio"
      input.name = `group-${group.id}`
      input.value = mod.id
      input.dataset.name = mod.name
      input.className = "text-amber-700 focus:ring-amber-600/30"
      const name = document.createElement("span")
      name.textContent = mod.name
      left.append(input, name)
      label.append(left)
      if (mod.price) {
        const price = document.createElement("span")
        price.className = "tabular-nums text-stone-500"
        price.textContent = mod.price
        label.append(price)
      }
      list.append(label)
    })
    fieldset.append(list)
    return fieldset
  }

  addToCart(event) {
    event.preventDefault()
    const picked = []
    for (const group of this.item.groups) {
      const chosen = [...this.itemGroupsTarget.querySelectorAll(`input[name="group-${group.id}"]:checked`)]
      if (group.required && chosen.length === 0) {
        this.showError(this.itemErrorTarget, this.pickRequiredValue.replace("%{group}", group.name))
        return
      }
      chosen.forEach((input) => picked.push({ id: input.value, name: input.dataset.name }))
    }

    const note = this.itemNoteTarget.value.trim()
    const modifierIds = picked.map((m) => m.id).sort()
    const key = `${this.item.kind}:${this.item.id}:${modifierIds.join(",")}`
    const same = !note && this.cart.find((line) => line.key === key && !line.notes)
    if (same) {
      same.quantity = Math.min(same.quantity + this.quantity, 99)
    } else {
      this.cart.push({
        key,
        kind: this.item.kind,
        id: this.item.id,
        name: this.item.name,
        modifiers: picked,
        quantity: this.quantity,
        notes: note
      })
    }
    this.save()
    this.renderBar()
    this.itemDialogTarget.close()
  }

  // ---- cart -------------------------------------------------------------

  load() {
    try {
      const raw = window.localStorage.getItem(this.storageKeyValue)
      const cart = raw ? JSON.parse(raw) : []
      return Array.isArray(cart) ? cart : []
    } catch (_e) {
      return []
    }
  }

  save() {
    try {
      window.localStorage.setItem(this.storageKeyValue, JSON.stringify(this.cart))
    } catch (_e) {
      // Private mode or full storage: the cart still works for this page view.
    }
  }

  renderBar() {
    const count = this.cart.reduce((sum, line) => sum + line.quantity, 0)
    this.cartBarTarget.classList.toggle("hidden", count === 0)
    this.cartCountTarget.textContent = String(count)
  }

  removeLine(event) {
    this.cart.splice(Number(event.currentTarget.dataset.index), 1)
    this.save()
    this.renderBar()
    this.renderLines()
    if (this.cart.length === 0) this.checkoutDialogTarget.close()
    else this.refreshQuote()
  }

  renderLines(quoteLines = null, errors = {}) {
    if (this.cart.length === 0) {
      const empty = document.createElement("li")
      empty.className = "py-3 text-sm text-stone-500"
      empty.textContent = this.linesTarget.dataset.emptyText
      this.linesTarget.replaceChildren(empty)
      return
    }

    let priced = 0
    const rows = this.cart.map((line, index) => {
      const li = document.createElement("li")
      li.className = "flex items-start justify-between gap-3 py-3"
      const info = document.createElement("div")
      info.className = "min-w-0"
      const title = document.createElement("p")
      title.className = "text-sm font-medium text-stone-900"
      title.textContent = `${line.quantity} × ${line.name}`
      info.append(title)
      const extra = [line.modifiers.map((m) => m.name).join("، "), line.notes].filter(Boolean).join(" — ")
      if (extra) {
        const detail = document.createElement("p")
        detail.className = "text-xs text-stone-500"
        detail.textContent = extra
        info.append(detail)
      }
      if (errors[index]) {
        const err = document.createElement("p")
        err.className = "text-xs font-medium text-rose-700"
        err.textContent = errors[index]
        info.append(err)
      }

      const side = document.createElement("div")
      side.className = "flex shrink-0 flex-col items-end gap-1"
      if (quoteLines && !errors[index] && quoteLines[priced]) {
        const price = document.createElement("span")
        price.className = "text-sm tabular-nums text-stone-900"
        price.textContent = quoteLines[priced].total
        side.append(price)
      }
      if (!errors[index]) priced += 1
      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "text-xs text-rose-700 hover:underline"
      remove.textContent = this.linesTarget.dataset.removeText
      remove.dataset.index = String(index)
      remove.dataset.action = "online-order#removeLine"
      side.append(remove)

      li.append(info, side)
      return li
    })
    this.linesTarget.replaceChildren(...rows)
  }

  // ---- checkout ---------------------------------------------------------

  openCheckout() {
    this.hideError(this.checkoutErrorTarget)
    this.renderLines()
    this.checkoutDialogTarget.showModal()
    this.refreshQuote()
  }

  closeCheckout() {
    this.checkoutDialogTarget.close()
  }

  fulfillmentChanged() {
    const delivery = this.fulfillment() === "delivery"
    this.deliveryFieldsTarget.classList.toggle("hidden", !delivery)
    this.feeRowTarget.classList.toggle("hidden", !delivery)
    this.feeRowTarget.classList.toggle("flex", delivery)
    this.refreshQuote()
  }

  fulfillment() {
    return this.checkoutFormTarget.querySelector("input[name=fulfillment]:checked")?.value || "pickup"
  }

  cartPayload() {
    return this.cart.map((line) => {
      const item = line.kind === "combo" ? { combo_id: line.id } : { menu_item_id: line.id }
      return { ...item, modifier_ids: line.modifiers.map((m) => m.id), quantity: line.quantity, notes: line.notes }
    })
  }

  async refreshQuote() {
    if (this.cart.length === 0) return
    const form = this.checkoutFormTarget
    const body = {
      items: this.cartPayload(),
      fulfillment: this.fulfillment(),
      delivery_area_id: form.elements.delivery_area_id?.value
    }
    const seq = (this.quoteSeq = (this.quoteSeq || 0) + 1)
    try {
      const response = await this.post(this.quoteUrlValue, body)
      if (!response.ok || seq !== this.quoteSeq) return
      const quote = await response.json()
      this.renderLines(quote.lines, quote.errors)
      this.subtotalTarget.textContent = quote.subtotal
      this.feeTarget.textContent = quote.delivery_fee
      this.totalTarget.textContent = quote.total
    } catch (_e) {
      // Offline for a moment: keep what is shown; sending will report the problem.
    }
  }

  async send(event) {
    event.preventDefault()
    const form = this.checkoutFormTarget
    const button = this.sendButtonTarget
    const label = button.textContent
    button.disabled = true
    button.textContent = button.dataset.sendingText
    this.hideError(this.checkoutErrorTarget)

    const body = {
      items: this.cartPayload(),
      fulfillment: this.fulfillment(),
      customer_name: form.elements.customer_name.value,
      phone: form.elements.phone.value,
      delivery_area_id: form.elements.delivery_area_id?.value,
      address: form.elements.address?.value,
      note: form.elements.note.value,
      website: form.elements.website.value,
      started_at: this.startedAtValue
    }

    try {
      const response = await this.post(this.createUrlValue, body)
      const data = await response.json()
      if (response.ok) {
        this.cart = []
        this.save()
        window.Turbo.visit(data.url)
        return
      }
      this.showError(this.checkoutErrorTarget, data.message)
      if (data.error === "bad_items") this.refreshQuote()
    } catch (_e) {
      this.showError(this.checkoutErrorTarget, document.documentElement.lang === "ar"
        ? "تعذر الاتصال. حاول مرة أخرى."
        : "Couldn't connect. Please try again.")
    }
    button.disabled = false
    button.textContent = label
  }

  post(url, body) {
    return fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: JSON.stringify(body)
    })
  }

  showError(target, message) {
    target.textContent = message
    target.classList.remove("hidden")
  }

  hideError(target) {
    target.textContent = ""
    target.classList.add("hidden")
  }
}
