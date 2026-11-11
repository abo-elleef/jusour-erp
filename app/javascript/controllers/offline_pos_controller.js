import { Controller } from "@hotwired/stimulus"
import { allOrders, getMeta, getOrder, nextCounter, putOrder } from "utils/offline_db"
import { computeTotals, formatMoney, lineTotal, parseAmountToCents } from "utils/offline_totals"
import { groupShowsPrices } from "utils/modifier_pricing"
import { buildProductionTicket, buildReceipt, toBase64, widthCharsFor } from "utils/escpos_canvas"
import { isReachable, syncQueuedOrders } from "utils/offline_sync"

// The register that works with no internet.
//
// Everything on screen is drawn here from the snapshot the online POS stored in
// IndexedDB: the menu, the prices, the tax rates and where each printer is. Taking
// an order never touches the server. The order is written to IndexedDB, the receipt
// and kitchen tickets are built in the browser and sent to the print agent on this
// computer (which only needs the LAN), and the order waits in the queue until the
// internet is back and utils/offline_sync pushes it to Rails.

const HEARTBEAT_MS = 6000
const AGENT_CHECK_MS = 15000
const PRINT_ATTEMPTS = 3

const esc = (value) =>
  String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])

const uuid = () =>
  crypto.randomUUID
    ? crypto.randomUUID()
    : "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0
        return (c === "x" ? r : (r & 0x3) | 0x8).toString(16)
      })

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms))

const BTN = "min-h-11 px-4 rounded-xl text-sm font-semibold transition-colors"
const BTN_ACCENT = `${BTN} bg-amber-600 hover:bg-amber-700 text-white`
const BTN_PLAIN = `${BTN} border border-gray-200 bg-white hover:bg-gray-50 text-gray-700`
const BTN_DARK = `${BTN} bg-stone-900 hover:bg-stone-800 text-white disabled:opacity-40 disabled:pointer-events-none`
const INPUT = "w-full rounded-xl border border-gray-200 bg-white px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-amber-500/30"

export default class extends Controller {
  static targets = ["root"]
  static values = { labels: Object, posUrl: String }

  async connect() {
    this.cart = this.emptyCart()
    this.category = "all"
    this.modal = null
    this.online = false
    this.upStreak = 0
    this.syncing = false
    this.syncNote = null
    this.agentOk = null
    this.orders = []
    this.printChain = Promise.resolve()

    this.onClick = (event) => this.handleClick(event)
    this.onInput = (event) => this.handleInput(event)
    this.element.addEventListener("click", this.onClick)
    this.element.addEventListener("input", this.onInput)

    this.snapshot = await getMeta("snapshot")
    this.orders = await allOrders()
    this.renderShell()
    if (!this.snapshot) return

    this.heartbeatTimer = setInterval(() => this.heartbeat(), HEARTBEAT_MS)
    this.agentTimer = setInterval(() => this.checkAgent(), AGENT_CHECK_MS)
    this.heartbeat()
    this.checkAgent()
  }

  disconnect() {
    this.element.removeEventListener("click", this.onClick)
    this.element.removeEventListener("input", this.onInput)
    clearInterval(this.heartbeatTimer)
    clearInterval(this.agentTimer)
  }

  // ── Labels ────────────────────────────────────────────────────────────────

  t(key, vars = {}) {
    return String(this.labelsValue[key] ?? key).replace(/%\{(\w+)\}/g, (_, name) => vars[name] ?? "")
  }

  // ── Rendering ─────────────────────────────────────────────────────────────

  region(name) {
    return this.rootTarget.querySelector(`[data-region='${name}']`)
  }

  draw(name) {
    const el = this.region(name)
    if (el) el.innerHTML = this[`${name}Html`]()
  }

  renderShell() {
    if (!this.snapshot) {
      this.rootTarget.innerHTML = `
        <div class="m-auto max-w-md text-center p-6">
          <p class="text-sm text-gray-700 mb-4">${esc(this.t("no_snapshot"))}</p>
          <a href="${esc(this.posUrlValue)}" data-turbo="false" class="${BTN_ACCENT} inline-flex items-center">${esc(this.t("back_to_pos"))}</a>
        </div>`
      return
    }

    this.rootTarget.innerHTML = `
      <div data-region="header" class="shrink-0"></div>
      <div data-region="banner" class="shrink-0"></div>
      <div class="flex flex-col lg:flex-row flex-1 min-h-0 overflow-hidden">
        <section class="flex flex-col min-h-0 flex-1 lg:flex-none lg:w-3/4 bg-gray-50 min-w-0" data-region="menu"></section>
        <aside class="flex flex-col min-h-0 shrink-0 h-[52vh] lg:h-full lg:flex-none lg:w-1/4 bg-stone-50 border-t lg:border-t-0 lg:border-s border-stone-200/80 shadow-[0_0_24px_rgba(0,0,0,0.06)]" data-region="cart"></aside>
      </div>
      <div data-region="modal"></div>
      <div data-region="toasts" class="fixed bottom-4 left-1/2 -translate-x-1/2 z-[100] flex flex-col items-center gap-2 w-[min(100vw-2rem,24rem)] pointer-events-none"></div>`
    ;["header", "banner", "menu", "cart", "modal"].forEach((name) => this.draw(name))
  }

  headerHtml() {
    const { location, workstation, user } = this.snapshot
    const where = [location?.name, workstation?.name, user?.name].filter(Boolean).join(" · ")
    const queued = this.orders.length
    const agentDot =
      this.agentOk === null ? "bg-gray-300" : this.agentOk ? "bg-emerald-500" : "bg-red-500"
    const agentTitle = this.agentOk === false ? this.t("agent_down") : ""

    return `
      <header class="flex items-center justify-between gap-3 px-4 py-2.5 border-b border-gray-200 bg-white">
        <div class="flex items-center gap-3 min-w-0">
          <span class="text-lg font-bold tracking-tight text-gray-900 whitespace-nowrap">${esc(this.t("title"))}</span>
          <span class="text-xs text-gray-500 truncate">${esc(where)}</span>
        </div>
        <div class="flex items-center gap-2 shrink-0">
          <span class="inline-block w-2.5 h-2.5 rounded-full ${agentDot}" title="${esc(agentTitle)}"></span>
          <button type="button" data-act="open-orders" class="${BTN_PLAIN}">
            ${esc(this.t("orders_title"))}
            ${queued ? `<span class="ms-1 text-xs font-bold bg-amber-500 text-white rounded-full px-2 py-0.5 tabular-nums">${queued}</span>` : ""}
          </button>
          ${this.online ? `<a href="${esc(this.posUrlValue)}" data-turbo="false" class="${BTN_ACCENT} inline-flex items-center">${esc(this.t("back_to_pos"))}</a>` : ""}
        </div>
      </header>`
  }

  bannerHtml() {
    const rows = []

    if (this.online) {
      rows.push(this.bannerRow("bg-green-600 text-white", this.t("back_online"), { note: this.syncNote, sync: true }))
    } else {
      rows.push(this.bannerRow("bg-yellow-500 text-yellow-900", this.t("banner")))
    }

    if (!this.snapshot.location) rows.push(this.bannerRow("bg-red-100 text-red-900", this.t("select_branch")))
    if (!this.snapshot.drawer_session_id) rows.push(this.bannerRow("bg-amber-50 text-amber-800", this.t("no_drawer")))

    const saved = this.snapshot.saved_at ? new Date(this.snapshot.saved_at).toLocaleString() : null
    if (saved) rows.push(`<p class="px-4 py-1 text-[11px] text-gray-500 bg-white border-b border-gray-100">${esc(this.t("stale_menu", { time: saved }))}</p>`)

    return rows.join("")
  }

  bannerRow(classes, message, { note = null, sync = false } = {}) {
    return `
      <div class="px-4 py-2 text-sm font-medium flex flex-wrap items-center gap-x-4 gap-y-1 ${classes}" role="alert">
        <span class="flex-1 min-w-0">${esc(message)}</span>
        ${note ? `<span class="text-xs opacity-90">${esc(note)}</span>` : ""}
        ${sync && this.orders.length ? `<button type="button" data-act="sync-now" class="text-xs font-semibold underline">${esc(this.t("sync_now"))}</button>` : ""}
      </div>`
  }

  menuHtml() {
    const { menu, location } = this.snapshot
    if (!location) return ""
    if (menu.items.length === 0 && menu.combos.length === 0) {
      return `<p class="text-center text-gray-500 py-16 text-sm">${esc(this.t("menu_empty"))}</p>`
    }

    const pill = (value, label) => {
      const active = this.category === value
      const classes = active
        ? "bg-gray-900 text-white border-gray-900"
        : "bg-white text-gray-700 border-gray-200 hover:bg-stone-100"
      return `<button type="button" data-act="category" data-value="${esc(value)}" class="shrink-0 min-h-10 px-4 rounded-full border text-sm font-medium transition-colors ${classes}">${esc(label)}</button>`
    }

    const pills = [pill("all", this.t("all"))]
    menu.categories.forEach((category) => pills.push(pill(category.id, category.name)))
    if (menu.combos.length) pills.push(pill("combos", this.t("combos")))

    const items = menu.items.filter((item) => this.category === "all" || this.category === item.category_id)
    const combos = menu.combos.filter(() => this.category === "all" || this.category === "combos")

    return `
      <div class="flex gap-2 px-4 py-3 border-b border-gray-200 bg-white overflow-x-auto shrink-0">${pills.join("")}</div>
      <div class="overflow-y-auto flex-1 touch-manipulation p-4">
        <div class="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-6 gap-3">
          ${items.map((item) => this.itemCardHtml(item)).join("")}
          ${combos.map((combo) => this.comboCardHtml(combo)).join("")}
        </div>
      </div>`
  }

  itemCardHtml(item) {
    const promo = item.promo
    const price = promo
      ? `<p class="mt-1 flex items-baseline gap-1.5 tabular-nums"><span class="text-xs text-gray-400 line-through">${formatMoney(promo.list_price_cents ?? item.price_cents)}</span><span class="text-rose-700 font-bold">${formatMoney(promo.promo_price_cents ?? item.price_cents - promo.discount_cents)}</span>${promo.modifier_name ? `<span class="text-[11px] font-semibold text-rose-700">${esc(this.t("only_choice", { choice: promo.modifier_name }))}</span>` : ""}</p>`
      : `<p class="text-amber-700 font-bold mt-1 tabular-nums">${formatMoney(item.price_cents)}</p>`
    const label = item.modifier_groups.length ? this.t("customize") : this.t("add")

    return `
      <div class="rounded-2xl border ${promo ? "border-rose-300 bg-rose-50/40" : "border-gray-200 bg-white"} p-3 flex flex-col">
        <p class="font-semibold text-sm leading-tight flex-1 text-gray-900">${esc(item.name)}</p>
        ${price}
        <button type="button" data-act="add-item" data-id="${esc(item.id)}" class="mt-2 w-full ${BTN_ACCENT}">${esc(label)}</button>
      </div>`
  }

  comboCardHtml(combo) {
    return `
      <div class="rounded-2xl border border-amber-200 bg-amber-50/50 p-3 flex flex-col">
        <p class="font-semibold text-sm flex-1 text-gray-900">${esc(combo.name)}</p>
        <p class="text-amber-700 font-bold mt-1 tabular-nums">${formatMoney(combo.price_cents)}</p>
        <button type="button" data-act="add-combo" data-id="${esc(combo.id)}" class="mt-2 w-full ${BTN_ACCENT}">${esc(this.t("add"))}</button>
      </div>`
  }

  cartHtml() {
    const lines = this.cart.lines
    const totals = this.cartTotals()
    const empty = lines.length === 0
    const isTable = this.cart.order_type === "table"
    const isDelivery = this.cart.order_type === "delivery"
    const toggle = (type, label) => {
      const active = this.cart.order_type === type
      const classes = active ? "bg-gray-900 text-white border-gray-900" : "bg-white text-gray-700 border-gray-200"
      return `<button type="button" data-act="order-type" data-type="${type}" class="flex-1 min-h-10 rounded-xl border text-sm font-semibold ${classes}">${esc(label)}</button>`
    }

    return `
      <div class="px-4 py-3 flex justify-between items-center gap-3 shrink-0 bg-white border-b border-stone-200/80">
        <h2 class="font-semibold text-gray-900">${esc(this.t("cart_title"))}</h2>
        <button type="button" data-act="clear-cart" class="text-xs font-semibold text-gray-600 hover:text-gray-900 ${empty ? "invisible" : ""}">${esc(this.t("clear"))}</button>
      </div>
      <div class="flex-1 min-h-0 overflow-y-auto">
        ${empty ? `<p class="text-center text-sm text-gray-500 py-10 px-4">${esc(this.t("cart_empty"))}</p>` : lines.map((line) => this.lineHtml(line)).join("")}
      </div>
      <div class="px-3 py-3 space-y-2.5 shrink-0 bg-white border-t border-stone-200/80">
        <div class="flex gap-2">${toggle("pickup", this.t("order_type_pickup"))}${toggle("table", this.t("order_type_table"))}${toggle("delivery", this.t("order_type_delivery"))}</div>
        ${isDelivery ? this.deliveryFieldsHtml() : ""}
        ${isTable ? this.tableFieldHtml() : ""}
        <input type="text" data-field="notes" value="${esc(this.cart.notes)}" placeholder="${esc(this.t("order_notes"))}" class="${INPUT}">
        <dl class="text-sm space-y-1 tabular-nums">
          <div class="flex justify-between text-gray-600"><dt>${esc(this.t("subtotal"))}</dt><dd>${formatMoney(totals.subtotal_cents)}</dd></div>
          ${totals.discount_cents > 0 ? `<div class="flex justify-between text-rose-700"><dt>${esc(this.t("discount"))}</dt><dd>-${formatMoney(totals.discount_cents)}</dd></div>` : ""}
          ${totals.tax_cents > 0 ? `<div class="flex justify-between text-gray-600"><dt>${esc(this.t("tax"))}</dt><dd>${formatMoney(totals.tax_cents)}</dd></div>` : ""}
          <div class="flex justify-between font-bold text-gray-900 text-base"><dt>${esc(this.t("total"))}</dt><dd>${formatMoney(totals.total_cents)}</dd></div>
        </dl>
        <button type="button" data-act="open-payment" class="w-full ${BTN_DARK} !rounded-full !py-3" ${empty ? "disabled" : ""}>${esc(this.t("charge", { amount: formatMoney(totals.total_cents) }))}</button>
      </div>`
  }

  // Numbered buttons when the branch has a table count (one tap, no typing in a
  // rush); the old free-text box when it does not.
  tableFieldHtml() {
    const count = parseInt(this.snapshot.location?.table_count, 10)
    if (count > 0) {
      const buttons = Array.from({ length: count }, (_, i) => {
        const n = String(i + 1)
        const on = String(this.cart.table_number) === n
        return `<button type="button" data-act="pick-table" data-value="${n}" class="min-h-10 rounded-xl border text-sm font-semibold tabular-nums transition-colors ${on ? "bg-stone-900 text-white border-stone-900" : "bg-white text-stone-700 border-stone-200 hover:bg-stone-100"}">${n}</button>`
      }).join("")
      return `<div class="grid grid-cols-5 gap-1.5 max-h-40 overflow-y-auto">${buttons}</div>`
    }
    return `<input type="text" inputmode="numeric" data-field="table_number" value="${esc(this.cart.table_number)}" placeholder="${esc(this.t("table_number"))}" class="${INPUT}" data-controller="arabic-numerals" data-action="input->arabic-numerals#normalize">`
  }

  deliveryFieldsHtml() {
    const { customer_name: name, customer_phone: phone, delivery_address: address } = this.cart
    return `
      <input type="text" data-field="customer_name" value="${esc(name)}" placeholder="${esc(this.t("customer_name"))}" class="${INPUT}">
      <input type="text" inputmode="tel" data-field="customer_phone" value="${esc(phone)}" placeholder="${esc(this.t("customer_phone"))}" class="${INPUT}" data-controller="arabic-numerals" data-action="input->arabic-numerals#normalize">
      <input type="text" data-field="delivery_address" value="${esc(address)}" placeholder="${esc(this.t("delivery_address"))}" class="${INPUT}">`
  }

  lineHtml(line) {
    const mods = (line.modifiers || []).map((m) => `<p class="text-xs text-gray-500">+ ${esc(m.name)}</p>`).join("")
    const note = line.notes ? `<p class="text-xs text-gray-500 italic">${esc(line.notes)}</p>` : ""
    const promo = line.promo_discount_cents ? `<p class="text-xs text-rose-700">${esc(line.promo_label || "")}</p>` : ""
    const round = "w-9 h-9 rounded-full border border-gray-200 bg-white text-lg leading-none hover:bg-gray-50"

    return `
      <div class="px-3 py-2.5 border-b border-stone-200/80 bg-white/60">
        <div class="flex justify-between gap-2">
          <p class="font-semibold text-sm text-gray-900">${esc(line.name)}</p>
          <p class="text-sm tabular-nums text-gray-900">${formatMoney(lineTotal(line))}</p>
        </div>
        ${mods}${note}${promo}
        <div class="flex items-center gap-2 mt-1.5">
          <button type="button" data-act="qty" data-uid="${esc(line.uid)}" data-delta="-1" class="${round}" aria-label="-">−</button>
          <span class="w-6 text-center text-sm font-semibold tabular-nums">${line.quantity}</span>
          <button type="button" data-act="qty" data-uid="${esc(line.uid)}" data-delta="1" class="${round}" aria-label="+">+</button>
          <button type="button" data-act="remove" data-uid="${esc(line.uid)}" class="ms-auto text-xs font-semibold text-red-600 hover:text-red-800">${esc(this.t("remove"))}</button>
        </div>
      </div>`
  }

  modalHtml() {
    if (!this.modal) return ""
    const frame = (inner) => `
      <div class="fixed inset-0 bg-gray-900/40 backdrop-blur-sm flex items-center justify-center z-50 p-4">
        <div class="bg-white rounded-2xl border border-gray-200 p-6 max-w-md w-full text-gray-900 max-h-[90vh] overflow-y-auto">${inner}</div>
      </div>`

    if (this.modal.kind === "modifiers") return frame(this.modifierModalHtml(this.modal.item))
    if (this.modal.kind === "payment") return frame(this.paymentModalHtml())
    if (this.modal.kind === "orders") return frame(this.ordersModalHtml())
    return ""
  }

  // Same layout and live prices as the online modal (pos/_modifier_modal):
  // every choice shows the full item price, via modifier-pricing.
  modifierModalHtml(item) {
    const config = {
      base_cents: item.price_cents,
      groups: item.modifier_groups.map((group) => ({
        id: group.id,
        multi_select: group.multi_select,
        modifiers: group.modifiers.map((m) => ({ id: m.id, price_adjustment_cents: m.price_adjustment_cents }))
      })),
      promos: (item.promos || (item.promo ? [item.promo] : [])).map((promo) => ({
        modifier_id: promo.modifier_id || null,
        discount_cents: promo.discount_cents
      }))
    }

    const groups = item.modifier_groups
      .map((group) => {
        const showsPrices = groupShowsPrices(group, config.promos)
        const options = group.modifiers
          .map((m) => {
            const input = group.multi_select
              ? `<input type="checkbox" data-modifier-option data-group="${esc(group.id)}" value="${esc(m.id)}" class="rounded border-gray-300 text-amber-600">`
              : `<input type="radio" data-modifier-option name="group-${esc(group.id)}" data-group="${esc(group.id)}" value="${esc(m.id)}" class="border-gray-300 text-amber-600">`
            const price = showsPrices ? `<span class="flex items-baseline gap-1.5 tabular-nums" data-modifier-price="${esc(m.id)}"></span>` : ""
            return `<label class="flex items-center gap-3 min-h-12 px-3 text-sm cursor-pointer rounded-xl border border-transparent hover:bg-white has-[:checked]:bg-amber-50 has-[:checked]:border-amber-400">${input}<span class="flex-1 font-medium">${esc(m.name)}</span>${price}</label>`
          })
          .join("")
        return `
          <fieldset class="mb-4 rounded-2xl border border-gray-200 bg-gray-50/80 p-3 space-y-1.5">
            <legend class="text-sm font-semibold px-1">${esc(group.name)}${group.required ? ' <span class="text-red-600">*</span>' : ""}</legend>
            ${options}
          </fieldset>`
      })
      .join("")

    return `
      <div data-controller="modifier-pricing" data-modifier-pricing-config-value="${esc(JSON.stringify(config))}" data-action="change->modifier-pricing#refresh">
        <h3 class="text-xl font-bold tracking-tight">${esc(item.name)}</h3>
        <p class="mt-1 mb-4 flex items-baseline gap-2 tabular-nums" data-modifier-pricing-target="total"></p>
        ${groups}
        <input type="text" data-modal-notes placeholder="${esc(this.t("kitchen_notes"))}" class="${INPUT} mb-2">
        <p data-modal-error class="text-sm text-red-600 mb-2 hidden"></p>
        <div class="flex gap-2">
          <button type="button" data-act="confirm-modifiers" class="flex-1 ${BTN_ACCENT}">${esc(this.t("add_to_order"))} · <span class="tabular-nums" data-modifier-pricing-target="buttonTotal"></span></button>
          <button type="button" data-act="close-modal" class="flex-1 ${BTN_PLAIN}">${esc(this.t("cancel"))}</button>
        </div>
      </div>`
  }

  paymentModalHtml() {
    const total = this.cartTotals().total_cents
    const rounded = [10, 50, 100, 200]
      .map((step) => Math.ceil(total / (step * 100)) * step * 100)
      .filter((value, index, all) => value > total && all.indexOf(value) === index)
    const quick = [total, ...rounded]
      .map((value) => `<button type="button" data-act="quick-cash" data-cents="${value}" class="${BTN_PLAIN} flex-1 tabular-nums">${formatMoney(value)}</button>`)
      .join("")

    return `
      <div class="flex justify-between items-center mb-4">
        <h3 class="text-xl font-bold tracking-tight">${esc(this.t("pay_cash"))}</h3>
        <button type="button" data-act="close-modal" class="text-gray-500 hover:text-gray-900 text-2xl leading-none w-10 h-10 rounded-xl hover:bg-gray-100" aria-label="${esc(this.t("close"))}">×</button>
      </div>
      <p class="text-2xl font-bold text-green-700 mb-4 tabular-nums">${esc(this.t("total"))}: ${formatMoney(total)}</p>
      <label class="block text-xs font-semibold text-gray-600 mb-1.5">${esc(this.t("cash_tendered"))}</label>
      <input type="text" inputmode="decimal" data-field="tendered" value="${(total / 100).toFixed(2)}" class="${INPUT} text-2xl text-center min-h-14" data-controller="arabic-numerals" data-action="input->arabic-numerals#normalize">
      <div class="flex flex-wrap gap-2 mt-3">${quick}</div>
      <p class="mt-3 text-sm text-gray-700">${esc(this.t("change_due"))}: <strong data-change-due class="tabular-nums">0.00</strong></p>
      <p data-modal-error class="text-sm text-red-600 mt-2 hidden"></p>
      <button type="button" data-act="confirm-payment" class="w-full mt-4 ${BTN_ACCENT} !bg-green-700 hover:!bg-green-800">${esc(this.t("confirm_payment"))}</button>`
  }

  ordersModalHtml() {
    const rows = [...this.orders].reverse().map((order) => this.orderRowHtml(order)).join("")
    return `
      <div class="flex justify-between items-center mb-4">
        <h3 class="text-xl font-bold tracking-tight">${esc(this.t("orders_title"))}</h3>
        <button type="button" data-act="close-modal" class="text-gray-500 hover:text-gray-900 text-2xl leading-none w-10 h-10 rounded-xl hover:bg-gray-100" aria-label="${esc(this.t("close"))}">×</button>
      </div>
      ${rows || `<p class="text-sm text-gray-500">${esc(this.t("no_orders"))}</p>`}
      ${this.online && this.orders.length ? `<button type="button" data-act="sync-now" data-retry="1" class="w-full mt-3 ${BTN_PLAIN}">${esc(this.t("sync_now"))}</button>` : ""}`
  }

  orderRowHtml(order) {
    const time = new Date(order.created_at).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })
    const rejected = order.sync?.status === "rejected"
    const status = (kind, label) => {
      const jobs = (order.jobs || []).filter((job) => job.kind === kind)
      if (jobs.length === 0) return ""
      const failed = jobs.some((job) => job.status === "failed")
      const done = jobs.every((job) => job.status === "sent")
      const text = failed ? this.t("print_failed") : done ? this.t("printed") : this.t("printing")
      const color = failed ? "text-red-600" : done ? "text-emerald-700" : "text-gray-500"
      return `<span class="text-xs ${color}">${esc(label)}: ${esc(text)}</span>`
    }

    return `
      <div class="border border-gray-200 rounded-xl p-3 mb-2">
        <div class="flex justify-between gap-2">
          <p class="font-semibold text-sm">${esc(order.offline_number)} <span class="text-gray-500 font-normal">${esc(time)}</span></p>
          <p class="text-sm tabular-nums">${formatMoney(order.totals.total_cents)}</p>
        </div>
        ${rejected ? `<p class="text-xs text-red-600 mt-1">${esc(order.sync.error)}</p>` : ""}
        <div class="flex flex-wrap gap-x-3 mt-1">${status("receipt", this.t("reprint_receipt"))}${status("tickets", this.t("reprint_tickets"))}</div>
        <div class="flex gap-2 mt-2">
          <button type="button" data-act="reprint" data-uuid="${esc(order.client_uuid)}" data-kind="receipt" class="${BTN_PLAIN} !min-h-9 !px-3">${esc(this.t("reprint"))} · ${esc(this.t("reprint_receipt"))}</button>
          <button type="button" data-act="reprint" data-uuid="${esc(order.client_uuid)}" data-kind="tickets" class="${BTN_PLAIN} !min-h-9 !px-3">${esc(this.t("reprint"))} · ${esc(this.t("reprint_tickets"))}</button>
        </div>
      </div>`
  }

  toast(message, type = "notice") {
    const holder = this.region("toasts")
    if (!holder) return
    const classes = type === "alert" ? "bg-red-50 border-red-200 text-red-900" : "bg-emerald-50 border-emerald-200 text-emerald-900"
    const el = document.createElement("div")
    el.className = `pointer-events-auto rounded-2xl border px-4 py-3 text-sm font-medium shadow-lg ${classes}`
    el.textContent = message
    holder.appendChild(el)
    setTimeout(() => el.remove(), 4500)
  }

  // ── Events ────────────────────────────────────────────────────────────────

  handleClick(event) {
    const target = event.target.closest("[data-act]")
    if (!target || !this.element.contains(target)) return

    const { act, id, uid, value, type, delta, cents, uuid: orderUuid, kind } = target.dataset
    switch (act) {
      case "category": this.category = value; this.draw("menu"); break
      case "add-item": this.addItem(id); break
      case "add-combo": this.addCombo(id); break
      case "qty": this.changeQuantity(uid, parseInt(delta, 10)); break
      case "remove": this.removeLine(uid); break
      case "pick-table": this.cart.table_number = value; this.draw("cart"); break
      case "order-type": this.cart.order_type = type; this.draw("cart"); break
      case "clear-cart": this.cart = this.emptyCart(); this.draw("cart"); break
      case "open-payment": this.openPayment(); break
      case "quick-cash": this.setTendered(parseInt(cents, 10)); break
      case "confirm-payment": this.confirmPayment(); break
      case "confirm-modifiers": this.confirmModifiers(); break
      case "close-modal": this.closeModal(); break
      case "open-orders": this.modal = { kind: "orders" }; this.draw("modal"); break
      case "reprint": this.reprint(orderUuid, kind); break
      case "sync-now": this.runSync(target.dataset.retry === "1"); break
    }
  }

  handleInput(event) {
    const field = event.target.dataset.field
    if (field === "table_number") this.cart.table_number = event.target.value
    if (field === "notes") this.cart.notes = event.target.value
    if (field === "customer_name") this.cart.customer_name = event.target.value
    if (field === "customer_phone") this.cart.customer_phone = event.target.value
    if (field === "delivery_address") this.cart.delivery_address = event.target.value
    if (field === "tendered") this.updateChangeDue()
  }

  // ── Cart ──────────────────────────────────────────────────────────────────

  emptyCart() {
    return { lines: [], order_type: "pickup", table_number: "", notes: "", customer_name: "", customer_phone: "", delivery_address: "" }
  }

  cartTotals() {
    return computeTotals(this.cart.lines, this.snapshot.tax_rates)
  }

  addItem(id) {
    const item = this.snapshot.menu.items.find((candidate) => candidate.id === id)
    if (!item) return
    if (item.modifier_groups.length) {
      this.modal = { kind: "modifiers", item }
      this.draw("modal")
      return
    }
    this.addLine(item, [], null)
  }

  // Same rule as Menus::ActivePromo: `promos` arrives in priority order, the
  // first that covers the whole item or a choice on this line wins. Older
  // snapshots only carry `promo` (whole-item).
  promoFor(item, modifiers) {
    if (!item.promos) return item.promo || null
    const chosen = new Set(modifiers.map((modifier) => modifier.id))
    return item.promos.find((promo) => !promo.modifier_id || chosen.has(promo.modifier_id)) || null
  }

  addLine(item, modifiers, notes) {
    const promo = this.promoFor(item, modifiers)
    const plain = modifiers.length === 0 && !notes
    const existing = plain && this.cart.lines.find((line) => line.menu_item_id === item.id && !line.notes && (line.modifiers || []).length === 0)
    if (existing) {
      existing.quantity += 1
    } else {
      this.cart.lines.push({
        uid: uuid(),
        menu_item_id: item.id,
        combo_id: null,
        name: item.name,
        quantity: 1,
        unit_price_cents: item.price_cents,
        tax_category: item.tax_category,
        notes,
        modifiers,
        promo_id: promo?.id || null,
        promo_label: promo?.label || null,
        promo_discount_cents: promo?.discount_cents || 0,
        routing_ids: [item.id]
      })
    }
    this.draw("cart")
  }

  addCombo(id) {
    const combo = this.snapshot.menu.combos.find((candidate) => candidate.id === id)
    if (!combo) return
    const existing = this.cart.lines.find((line) => line.combo_id === combo.id)
    if (existing) {
      existing.quantity += 1
    } else {
      this.cart.lines.push({
        uid: uuid(),
        menu_item_id: null,
        combo_id: combo.id,
        name: combo.name,
        quantity: 1,
        unit_price_cents: combo.price_cents,
        tax_category: "food",
        notes: null,
        modifiers: [],
        promo_id: null,
        promo_label: null,
        promo_discount_cents: 0,
        routing_ids: combo.menu_item_ids
      })
    }
    this.draw("cart")
  }

  changeQuantity(uid, delta) {
    const line = this.cart.lines.find((candidate) => candidate.uid === uid)
    if (!line) return
    line.quantity = Math.max(1, line.quantity + delta)
    this.draw("cart")
  }

  removeLine(uid) {
    this.cart.lines = this.cart.lines.filter((line) => line.uid !== uid)
    this.draw("cart")
  }

  confirmModifiers() {
    const item = this.modal?.item
    if (!item) return
    const modal = this.region("modal")
    const error = modal.querySelector("[data-modal-error]")
    const picked = []

    for (const group of item.modifier_groups) {
      const checked = [...modal.querySelectorAll(`[data-group='${group.id}']:checked`)]
      if (group.required && checked.length === 0) {
        error.textContent = this.t("choose_required", { group: group.name })
        error.classList.remove("hidden")
        return
      }
      checked.forEach((input) => {
        const modifier = group.modifiers.find((candidate) => candidate.id === input.value)
        if (modifier) picked.push({ id: modifier.id, name: modifier.name, price_adjustment_cents: modifier.price_adjustment_cents })
      })
    }

    const notes = modal.querySelector("[data-modal-notes]").value.trim() || null
    this.closeModal()
    this.addLine(item, picked, notes)
  }

  closeModal() {
    this.modal = null
    this.draw("modal")
  }

  // ── Payment ───────────────────────────────────────────────────────────────

  openPayment() {
    if (this.cart.lines.length === 0) return
    if (this.cart.order_type === "table" && !this.cart.table_number.trim()) {
      this.toast(this.t("table_required"), "alert")
      return
    }
    if (this.cart.order_type === "delivery" && (!this.cleanPhone() || !this.cart.delivery_address.trim())) {
      this.toast(this.t("delivery_required"), "alert")
      return
    }
    this.modal = { kind: "payment" }
    this.draw("modal")
    this.updateChangeDue()
  }

  // Digits are already ASCII (the arabic-numerals controller sees to that while
  // typing); spaces and dashes in a phone number would stop it matching the customer
  // the system already has.
  cleanPhone() {
    return this.cart.customer_phone.replace(/[\s-]+/g, "")
  }

  tenderedInput() {
    return this.region("modal").querySelector("[data-field='tendered']")
  }

  setTendered(cents) {
    const input = this.tenderedInput()
    if (!input) return
    input.value = (cents / 100).toFixed(2)
    this.updateChangeDue()
  }

  updateChangeDue() {
    const input = this.tenderedInput()
    const out = this.region("modal").querySelector("[data-change-due]")
    if (!input || !out) return
    const tendered = parseAmountToCents(input.value)
    const change = tendered === null ? 0 : Math.max(0, tendered - this.cartTotals().total_cents)
    out.textContent = formatMoney(change)
  }

  async confirmPayment() {
    const total = this.cartTotals().total_cents
    const tendered = parseAmountToCents(this.tenderedInput().value)
    const error = this.region("modal").querySelector("[data-modal-error]")

    if (tendered === null || tendered < total) {
      error.textContent = this.t("not_enough")
      error.classList.remove("hidden")
      return
    }

    const order = await this.saveOrder(tendered)
    this.cart = this.emptyCart()
    this.modal = null
    ;["cart", "modal", "header"].forEach((name) => this.draw(name))
    this.toast(this.t("saved", { number: order.offline_number }))
    this.enqueuePrint(order.client_uuid, "all")
  }

  async saveOrder(tenderedCents) {
    const now = new Date()
    const dayKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`
    const number = await nextCounter(dayKey)
    const { snapshot, cart } = this

    const order = {
      client_uuid: uuid(),
      offline_number: `OFF-${number}`,
      created_at: now.toISOString(),
      user_id: snapshot.user.id,
      location_id: snapshot.location?.id || null,
      workstation_id: snapshot.workstation?.id || null,
      drawer_session_id: snapshot.drawer_session_id || null,
      order_type: cart.order_type,
      table_number: cart.order_type === "table" ? cart.table_number.trim() : null,
      customer_name: cart.order_type === "delivery" ? cart.customer_name.trim() || null : null,
      customer_phone: cart.order_type === "delivery" ? this.cleanPhone() : null,
      delivery_address: cart.order_type === "delivery" ? cart.delivery_address.trim() : null,
      notes: cart.notes.trim() || null,
      items: cart.lines.map(({ uid: _uid, ...line }) => line),
      totals: this.cartTotals(),
      tendered_cents: tenderedCents,
      jobs: [],
      sync: { status: "queued" }
    }
    // The tickets carry the order number, so they are built from the numbered record.
    order.jobs = this.buildJobs(order)

    await putOrder(order)
    this.orders = await allOrders()
    return order
  }

  // ── Printing ──────────────────────────────────────────────────────────────

  buildJobs(order) {
    const { printers, print, company } = this.snapshot
    const labels = this.labelsValue
    const base = { labels, rtl: print.rtl }
    const jobs = []
    const target = (printer) => ({ name: printer.name, connection: printer.connection, host: printer.host, port: printer.port })

    if (printers.receipt) {
      const bytes = buildReceipt(order, {
        ...base,
        restaurant: company.receipt_name,
        footer: print.footer,
        widthChars: widthCharsFor(printers.receipt.paper_width)
      })
      jobs.push({ key: "receipt", kind: "receipt", printer: target(printers.receipt), data: toBase64(bytes), status: "pending", attempts: 0 })
    }

    printers.stations.forEach((printer) => {
      const items = order.items.filter((line) => (line.routing_ids || []).some((id) => printer.menu_item_ids.includes(id)))
      if (items.length === 0) return
      const bytes = buildProductionTicket(order, items, printer.station, { ...base, widthChars: widthCharsFor(printer.paper_width) })
      jobs.push({ key: `station:${printer.id}`, kind: "tickets", printer: target(printer), data: toBase64(bytes), status: "pending", attempts: 0 })
    })

    if (printers.expo) {
      const bytes = buildProductionTicket(order, order.items, labels.pick_title, { ...base, widthChars: widthCharsFor(printers.expo.paper_width) })
      jobs.push({ key: "expo", kind: "tickets", printer: target(printers.expo), data: toBase64(bytes), status: "pending", attempts: 0 })
    }

    return jobs
  }

  // One job at a time, across orders, so two tickets never fight for a printer's
  // TCP connection.
  enqueuePrint(clientUuid, scope) {
    this.printChain = this.printChain.then(() => this.runJobs(clientUuid, scope)).catch(() => {})
  }

  async runJobs(clientUuid, scope) {
    const order = await getOrder(clientUuid)
    if (!order) return
    if ((order.jobs || []).length === 0) {
      this.toast(this.t("no_printer"), "alert")
      return
    }

    for (const job of order.jobs) {
      if (job.status === "sent") continue
      if (scope !== "all" && job.kind !== scope) continue

      job.status = "printing"
      await putOrder(order)
      this.refreshOrders(order)

      const outcome = await this.sendJob(job)
      job.status = outcome.ok ? "sent" : "failed"
      job.error = outcome.error || null
      await putOrder(order)
      this.refreshOrders(order)
      if (!outcome.ok) this.toast(`${job.printer.name}: ${this.t("print_failed")}`, "alert")
    }
  }

  async reprint(clientUuid, kind) {
    const order = await getOrder(clientUuid)
    if (!order) return
    order.jobs.filter((job) => job.kind === kind).forEach((job) => { job.status = "pending" })
    await putOrder(order)
    this.refreshOrders(order)
    this.enqueuePrint(clientUuid, kind)
  }

  refreshOrders(updated) {
    const index = this.orders.findIndex((order) => order.client_uuid === updated.client_uuid)
    if (index >= 0) this.orders[index] = updated
    if (this.modal?.kind === "orders") this.draw("modal")
  }

  async sendJob(job) {
    let lastError = null
    for (let attempt = 1; attempt <= PRINT_ATTEMPTS; attempt++) {
      try {
        await this.postToAgent(job)
        return { ok: true }
      } catch (error) {
        lastError = error
        if (attempt < PRINT_ATTEMPTS) await sleep(1000 * attempt)
      }
    }
    return { ok: false, error: lastError?.message || "Print failed" }
  }

  async postToAgent(job) {
    const { agent } = this.snapshot
    const { printer } = job
    const body = printer.connection === "usb"
      ? { connection: "usb", device: printer.host, data_base64: job.data }
      : { connection: "network", host: printer.host, port: printer.port, data_base64: job.data }

    const response = await this.agentFetch("/print", {
      method: "POST",
      headers: { "Content-Type": "application/json", ...(agent.token ? { "X-Print-Agent-Token": agent.token } : {}) },
      body: JSON.stringify(body)
    }, 15000)
    if (!response.ok) {
      const payload = await response.json().catch(() => ({}))
      throw new Error(payload.error || response.statusText)
    }
  }

  agentFetch(path, options = {}, timeoutMs = 3000) {
    const controller = new AbortController()
    const timer = setTimeout(() => controller.abort(), timeoutMs)
    return fetch(`${this.snapshot.agent.url}${path}`, { ...options, signal: controller.signal }).finally(() => clearTimeout(timer))
  }

  async checkAgent() {
    const { agent } = this.snapshot
    let ok = false
    try {
      const headers = agent.token ? { "X-Print-Agent-Token": agent.token } : {}
      const response = await this.agentFetch("/health", { headers })
      ok = response.ok
    } catch {
      ok = false
    }
    if (ok !== this.agentOk) {
      this.agentOk = ok
      this.draw("header")
    }
  }

  // ── Connection and sync ───────────────────────────────────────────────────

  async heartbeat() {
    const reachable = await isReachable()
    this.upStreak = reachable ? this.upStreak + 1 : 0

    if (reachable && !this.online && this.upStreak >= 2) {
      this.online = true
      ;["header", "banner"].forEach((name) => this.draw(name))
      await this.runSync(false)
    } else if (!reachable && this.online) {
      this.online = false
      ;["header", "banner"].forEach((name) => this.draw(name))
    }
  }

  async runSync(retryRejected) {
    if (this.syncing) return
    this.syncing = true
    this.syncNote = this.t("syncing")
    this.draw("banner")

    let result
    try {
      result = await syncQueuedOrders({ retryRejected })
    } catch {
      result = { synced: 0, rejected: 0, remaining: this.orders.length, authRequired: false }
    }

    this.orders = await allOrders()
    this.syncing = false

    const notes = []
    if (result.synced) notes.push(this.t("synced", { count: result.synced }))
    if (result.authRequired) notes.push(this.t("other_cashier_login"))
    const stuck = this.orders.filter((order) => order.sync?.status === "rejected").length
    if (stuck) notes.push(this.t("sync_failed", { count: stuck }))
    this.syncNote = notes.join(" ") || null

    ;["header", "banner"].forEach((name) => this.draw(name))
    if (this.modal?.kind === "orders") this.draw("modal")

    // Nothing left to deliver and nobody mid-order: hand the screen back to the
    // normal POS.
    if (this.online && this.orders.length === 0 && !result.authRequired && this.cart.lines.length === 0 && !this.modal) {
      setTimeout(() => {
        if (this.cart.lines.length === 0 && !this.modal) window.location.assign(this.posUrlValue)
      }, 1500)
    }
  }
}
