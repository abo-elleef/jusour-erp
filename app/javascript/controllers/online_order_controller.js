import { Controller } from "@hotwired/stimulus"
import { applySelectionCaps, groupShowsPrices, priceFor, priceWithOption } from "utils/modifier_pricing"
import { formatMoney } from "utils/offline_totals"

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
    "subtotal", "fee", "total", "checkoutError", "sendButton", "limitWarning",
    "proofFields", "payToLabel", "payTo", "proofInput", "proofPreview"
  ]

  static values = {
    quoteUrl: String,
    createUrl: String,
    storageKey: String,
    startedAt: String,
    pickRequired: String,
    requiredLabel: String,
    upTo: String
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
    this.refreshPrices()
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
    if (group.multi && group.max) {
      const cap = document.createElement("span")
      cap.className = "text-xs font-normal text-stone-500"
      cap.textContent = this.upToValue.replace("%{count}", group.max)
      legend.append(cap)
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
      if (this.groupHasPrices(group)) {
        // Filled by refreshPrices: the whole item price with this choice.
        const price = document.createElement("span")
        price.className = "flex items-baseline gap-1.5 tabular-nums"
        price.dataset.modifierPrice = mod.id
        label.append(price)
      }
      list.append(label)
    })
    fieldset.append(list)
    fieldset.addEventListener("change", () => {
      this.applyCaps()
      this.refreshPrices()
    })
    return fieldset
  }

  // ---- prices in the popup (same rule as the POS customize modal) -------
  // Every priced choice shows the whole item price if picked ("110.00", not
  // "+35.00"), and the header follows what is picked. Combos carry no pricing.

  pricingGroup(group) {
    return this.item.pricing.groups.find((row) => row.id === group.id)
  }

  groupHasPrices(group) {
    const pricing = this.item.pricing
    return Boolean(pricing) && groupShowsPrices(this.pricingGroup(group), pricing.promos)
  }

  pickedIds() {
    return [...this.itemGroupsTarget.querySelectorAll("input:checked")].map((input) => input.value)
  }

  refreshPrices() {
    const pricing = this.item.pricing
    if (!pricing) return
    const picked = this.pickedIds()
    for (const group of this.item.groups) {
      const pricingGroup = this.pricingGroup(group)
      for (const mod of group.modifiers) {
        const slot = this.itemGroupsTarget.querySelector(`[data-modifier-price="${mod.id}"]`)
        if (slot) slot.innerHTML = this.priceHtml(priceWithOption(pricing, picked, pricingGroup, mod.id), "text-sm")
      }
    }
    this.itemPriceTarget.innerHTML = this.priceHtml(priceFor(pricing, picked), "text-sm")
  }

  priceHtml({ list, discount, final }, size) {
    const now = `<span class="${size} font-semibold ${discount ? "text-rose-700" : "text-amber-700"}">${formatMoney(final)}</span>`
    if (!discount) return now
    return `<span class="text-xs font-normal text-stone-400 line-through">${formatMoney(list)}</span> ${now}`
  }

  // "Up to N" groups: grey out the rest once N are ticked.
  applyCaps() {
    applySelectionCaps(
      this.item.groups.map((group) => ({ id: group.id, multi_select: group.multi, max_selections: group.max })),
      (groupId) => this.itemGroupsTarget.querySelectorAll(`input[name="group-${groupId}"]`)
    )
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
    this.paymentChanged()
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
    this.showAreaFee()
    this.refreshQuote()
  }

  // The fee shows the moment an area is picked (its price is on the option), and
  // the total waits for the server's quote instead of showing a stale sum.
  areaChanged() {
    this.showAreaFee()
    this.refreshQuote()
  }

  showAreaFee() {
    if (this.fulfillment() !== "delivery") return
    const area = this.checkoutFormTarget.elements.delivery_area_id
    const option = area?.value ? this.areaOptions().find((o) => String(o.value) === String(area.value)) : null
    this.feeTarget.textContent = option ? option.fee : this.feeTarget.dataset.chooseText
    this.totalTarget.textContent = "…"
  }

  // The areas offered in the searchable picker, each with its fee for display.
  areaOptions() {
    const holder = this.checkoutFormTarget.querySelector("[data-searchable-select-options]")
    try {
      return JSON.parse(holder?.dataset.searchableSelectOptions || "[]")
    } catch (_e) {
      return []
    }
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
    if (this.cart.length === 0) return this.showLimit(null)
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
      this.totalTarget.textContent = quote.total
      this.renderPayTo()
      this.showLimit(quote.over_limit)
      const areaPicked = this.checkoutFormTarget.elements.delivery_area_id?.value
      this.feeTarget.textContent = body.fulfillment === "delivery" && !areaPicked
        ? this.feeTarget.dataset.chooseText
        : quote.delivery_fee
    } catch (_e) {
      // Offline for a moment: keep what is shown; sending will report the problem.
    }
  }

  // ---- payment ----------------------------------------------------------

  // The radio the customer picked (a branch offering cash only has a hidden field).
  selectedPayment() {
    return this.checkoutFormTarget.querySelector("input[name=payment_method]:checked") ||
      this.checkoutFormTarget.querySelector("input[name=payment_method][type=hidden]")
  }

  prepaid() {
    return this.selectedPayment()?.dataset.prepaid === "true"
  }

  // A "pay before ordering" method shows where to transfer and asks for the screenshot.
  paymentChanged() {
    if (!this.hasProofFieldsTarget) return
    this.proofFieldsTarget.classList.toggle("hidden", !this.prepaid())
    this.renderPayTo()
  }

  renderPayTo() {
    if (!this.hasPayToTarget) return
    const total = this.totalTarget.textContent
    this.payToLabelTarget.textContent = this.payToLabelTarget.dataset.template.replace("%{total}", total)
    this.renderPayToLines(this.selectedPayment()?.dataset.payTo || "")
  }

  // Each line of the branch's "pay to" text gets a Copy button. Built with
  // textContent: the text is typed by the branch, never treated as HTML.
  renderPayToLines(text) {
    const list = this.payToTarget
    list.replaceChildren()
    const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean)
    if (lines.length === 0) {
      const item = document.createElement("li")
      item.className = "text-sm text-stone-700"
      item.textContent = list.dataset.missingText
      list.append(item)
      return
    }

    lines.forEach((line) => {
      const item = document.createElement("li")
      item.className = "flex items-center justify-between gap-3 rounded-lg border border-amber-200 bg-white px-3 py-2"
      const value = document.createElement("span")
      value.className = "min-w-0 break-all text-base font-bold text-stone-900 select-all"
      value.dir = "auto"
      value.textContent = line
      const button = document.createElement("button")
      button.type = "button"
      button.className = "shrink-0 rounded-full border border-amber-600 px-3 py-1 text-xs font-semibold text-amber-800 hover:bg-amber-50"
      button.dataset.copyValue = copyValueFor(line)
      button.textContent = list.dataset.copyText
      item.append(value, button)
      list.append(item)
    })
  }

  async copyPayTo(event) {
    const button = event.target.closest("button[data-copy-value]")
    if (!button) return

    const copied = await copyToClipboard(button.dataset.copyValue)
    if (!copied) return
    button.textContent = this.payToTarget.dataset.copiedText
    clearTimeout(button.copyTimer)
    button.copyTimer = setTimeout(() => { button.textContent = this.payToTarget.dataset.copyText }, 2000)
  }

  // Checked here only to tell the customer early; the server checks again.
  proofChanged() {
    const input = this.proofInputTarget
    const file = input.files[0]
    this.hideError(this.checkoutErrorTarget)
    if (file && !this.acceptableProof(file)) {
      input.value = ""
      this.showError(this.checkoutErrorTarget, input.dataset.badText)
    }
    this.showProofPreview(input.files[0])
  }

  acceptableProof(file) {
    return ["image/jpeg", "image/png", "image/webp"].includes(file.type) && file.size > 0 && file.size <= 10 * 1024 * 1024
  }

  showProofPreview(file) {
    if (!this.hasProofPreviewTarget) return
    if (this.previewUrl) URL.revokeObjectURL(this.previewUrl)
    this.previewUrl = file ? URL.createObjectURL(file) : null
    this.proofPreviewTarget.src = this.previewUrl || ""
    this.proofPreviewTarget.classList.toggle("hidden", !file)
  }

  async send(event) {
    event.preventDefault()
    const form = this.checkoutFormTarget
    const button = this.sendButtonTarget
    const label = button.textContent
    const proof = this.prepaid() ? this.proofInputTarget.files[0] : null
    if (this.prepaid() && !proof) {
      this.showError(this.checkoutErrorTarget, this.proofInputTarget.dataset.missingText)
      return
    }
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
      payment_method: this.selectedPayment()?.value || "cash",
      website: form.elements.website.value,
      started_at: this.startedAtValue
    }

    try {
      // Multipart, so a prepaid order can carry its screenshot; the order is one JSON field.
      const formData = new FormData()
      formData.append("order", JSON.stringify(body))
      if (proof) formData.append("payment_proof_image", proof)
      const response = await this.postForm(this.createUrlValue, formData)
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
    button.disabled = Boolean(this.overLimit)
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

  postForm(url, formData) {
    return fetch(url, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: formData
    })
  }

  // Over the branch's online maximum: say so up front and hold the Send button.
  // The server refuses it anyway; this only saves the customer typing their details.
  showLimit(message) {
    this.overLimit = Boolean(message)
    if (message) this.showError(this.limitWarningTarget, message)
    else this.hideError(this.limitWarningTarget)
    this.sendButtonTarget.disabled = this.overLimit
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

// A phone or account number is copied as bare digits (Arabic-Indic digits turned
// into 0-9, spaces and dashes dropped) so it pastes cleanly into the wallet app.
// Anything else (an InstaPay address, a name) is copied as typed.
function copyValueFor(line) {
  const western = line.replace(/[\u0660-\u0669]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[\u06F0-\u06F9]/g, (d) => String(d.charCodeAt(0) - 0x06F0))
  return /^[+\d\s-]+$/.test(western) ? western.replace(/[\s-]/g, "") : line
}

async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch {
    // Older phone browsers, or a page not served over https.
    const area = document.createElement("textarea")
    area.value = text
    area.setAttribute("readonly", "")
    area.style.position = "fixed"
    area.style.opacity = "0"
    document.body.append(area)
    area.select()
    const ok = document.execCommand("copy")
    area.remove()
    return ok
  }
}
