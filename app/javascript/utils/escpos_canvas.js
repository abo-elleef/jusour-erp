// Builds receipts and kitchen tickets as ESC/POS bytes in the browser.
//
// The server does this with ImageMagick plus an Arabic shaping/bidi port, because
// thermal printers cannot join Arabic letters themselves. The browser already knows
// how: it shapes and orders Arabic correctly when it draws text on a canvas. So every
// line is drawn on a canvas, thresholded to black and white, and sent as a raster
// image (GS v 0) — the same trick, minus the server, which is the point: this has to
// work when the server cannot be reached.
//
// Layout follows Printing::Escpos::ArabicImageRenderer (26px text, 3-column rows split
// at 26% / 46%) so an offline receipt looks like an online one.

const PAPER_PX = { 42: 576, 32: 384 }
const BASE_PX = 26
const LINE_GAP = 8
const FONT_FAMILY = '"Noto Naskh Arabic", "Segoe UI", Tahoma, Arial, "Arial Unicode MS", sans-serif'
const BLACK_BELOW = 150 // 0–255 luminance; anything darker prints
const ARABIC_SCRIPT = /[֐-ࣿיִ-﷿ﹰ-﻿]/

export function widthCharsFor(paperWidth) {
  return paperWidth === "58mm" ? 32 : 42
}

export function toBase64(bytes) {
  let binary = ""
  const chunk = 0x8000
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk))
  }
  return btoa(binary)
}

export class EscposDocument {
  constructor({ widthChars = 42, rtl = false } = {}) {
    this.px = PAPER_PX[widthChars] || 576
    this.rtl = rtl
    this.chunks = []
    this.alignment = "left"
    this.scale = 1
    this.emphasis = false
    this.raw([0x1b, 0x40]) // ESC @ — initialise
  }

  align(mode) {
    this.alignment = mode
  }

  bold(on = true) {
    this.emphasis = on
  }

  doubleHeight(on = true) {
    this.scale = on ? 2 : 1
  }

  blank(lines = 1) {
    for (let i = 0; i < lines; i++) this.raw([0x0a])
  }

  // Feed past the cutter, then cut — the same GS V 66 150 the server sends.
  cut() {
    this.raw([0x1d, 0x56, 0x42, 150])
  }

  text(line = "") {
    const size = BASE_PX * this.scale
    const lines = this.wrap(String(line), this.px - 8, size)
    this.drawBlock(lines.length, size, (ctx, y, i) => {
      this.fill(ctx, lines[i], { x0: 4, x1: this.px - 4, align: this.alignment, y, size })
    })
  }

  // Label on the reading-start side, value on the other (mirrored for RTL).
  row(label, value = "") {
    const size = BASE_PX
    this.drawBlock(1, size, (ctx, y) => {
      const valueWidth = this.measure(String(value), size)
      const labelBox = this.px - 16 - valueWidth - 12
      if (this.rtl) {
        this.fill(ctx, value, { x0: 8, x1: this.px - 8, align: "left", y, size })
        this.fill(ctx, label, { x0: this.px - 8 - labelBox, x1: this.px - 8, align: "right", y, size })
      } else {
        this.fill(ctx, label, { x0: 8, x1: 8 + labelBox, align: "left", y, size })
        this.fill(ctx, value, { x0: 8, x1: this.px - 8, align: "right", y, size })
      }
    })
  }

  // Item | Qty | Price, with the column rules the server draws.
  row3(label, qty, price) {
    const { labelBox, qtyBox, priceBox, rules } = this.columns()
    const size = BASE_PX
    const lines = this.wrap(String(label), labelBox.x1 - labelBox.x0, size)
    this.drawBlock(lines.length, size, (ctx, y, i, h) => {
      this.fill(ctx, lines[i], { ...labelBox, align: this.rtl ? "right" : "left", y, size })
      if (i === 0) {
        const mid = h / 2
        this.fill(ctx, qty, { ...qtyBox, align: "center", y: lines.length === 1 ? y : mid, size })
        this.fill(ctx, price, { ...priceBox, align: "right", y: lines.length === 1 ? y : mid, size })
      }
    }, rules)
  }

  // A continuation line inside the item column (modifiers, notes).
  modifier(text, { columns = 3 } = {}) {
    const size = BASE_PX
    const { labelBox, rules } = this.columns()
    const box = columns === 3 ? labelBox : { x0: 8, x1: this.px - 8 }
    const lines = this.wrap(String(text), box.x1 - box.x0, size)
    this.drawBlock(lines.length, size, (ctx, y, i) => {
      this.fill(ctx, lines[i], { ...box, align: this.rtl ? "right" : "left", y, size })
    }, columns === 3 ? rules : [])
  }

  // Hairline across the paper, 2px tall like the server's.
  separator() {
    const bytesPerRow = Math.ceil(this.px / 8)
    const data = new Uint8Array(bytesPerRow * 2)
    data.fill(0xff, 0, bytesPerRow)
    this.raster(bytesPerRow, 2, data)
  }

  toBytes() {
    const total = this.chunks.reduce((sum, c) => sum + c.length, 0)
    const out = new Uint8Array(total)
    let offset = 0
    this.chunks.forEach((chunk) => {
      out.set(chunk, offset)
      offset += chunk.length
    })
    return out
  }

  // ── internals ────────────────────────────────────────────────────────────

  raw(bytes) {
    this.chunks.push(Uint8Array.from(bytes))
  }

  raster(bytesPerRow, height, data) {
    this.raw([0x1d, 0x76, 0x30, 0x00, bytesPerRow & 0xff, bytesPerRow >> 8, height & 0xff, height >> 8])
    this.chunks.push(data)
  }

  // Server column geometry: price | qty | item, split at 26% and 46% of the paper,
  // mirrored when the script runs left to right.
  columns() {
    const sep1 = Math.floor(this.px * 0.26) - 12
    const sep2 = Math.floor(this.px * 0.46)
    if (this.rtl) {
      return {
        priceBox: { x0: 8, x1: sep1 - 8 },
        qtyBox: { x0: sep1 + 8, x1: sep2 - 8 },
        labelBox: { x0: sep2 + 8, x1: this.px - 8 },
        rules: [sep1, sep2]
      }
    }
    const left = this.px - sep2
    const right = this.px - sep1
    return {
      labelBox: { x0: 8, x1: left - 8 },
      qtyBox: { x0: left + 8, x1: right - 8 },
      priceBox: { x0: right + 8, x1: this.px - 8 },
      rules: [left, right]
    }
  }

  font(size) {
    return `${this.emphasis ? "bold " : ""}${size}px ${FONT_FAMILY}`
  }

  measure(text, size) {
    const ctx = this.scratch()
    ctx.font = this.font(size)
    return ctx.measureText(text).width
  }

  scratch() {
    if (!this._scratch) this._scratch = document.createElement("canvas").getContext("2d")
    this._scratch.direction = this.rtl ? "rtl" : "ltr"
    return this._scratch
  }

  // Greedy word wrap to `maxWidth`, in reading order.
  wrap(text, maxWidth, size) {
    const ctx = this.scratch()
    ctx.font = this.font(size)
    const words = text.split(/\s+/).filter(Boolean)
    if (words.length === 0) return [""]

    const lines = []
    let current = words[0]
    for (let i = 1; i < words.length; i++) {
      const attempt = `${current} ${words[i]}`
      if (ctx.measureText(attempt).width <= maxWidth) {
        current = attempt
      } else {
        lines.push(current)
        current = words[i]
      }
    }
    lines.push(current)
    return lines
  }

  // Draws `lineCount` stacked lines on one canvas and appends it as a raster.
  // `paint(ctx, y, lineIndex, height)` is called per line with its vertical centre.
  drawBlock(lineCount, size, paint, rules = []) {
    const lineHeight = size + LINE_GAP
    const height = lineCount === 1 ? size * 2 : lineCount * lineHeight + size
    const canvas = document.createElement("canvas")
    canvas.width = this.px
    canvas.height = height
    const ctx = canvas.getContext("2d", { willReadFrequently: true })
    ctx.fillStyle = "#fff"
    ctx.fillRect(0, 0, this.px, height)
    ctx.fillStyle = "#000"
    ctx.strokeStyle = "#000"
    ctx.lineWidth = 1
    ctx.textBaseline = "middle"
    ctx.direction = this.rtl ? "rtl" : "ltr"

    for (let i = 0; i < lineCount; i++) {
      // One line sits in the middle; several stack with half a line of margin.
      const y = lineCount === 1 ? height / 2 : size / 2 + i * lineHeight + lineHeight / 2
      paint(ctx, y, i, height)
    }
    rules.forEach((x) => {
      ctx.beginPath()
      ctx.moveTo(x + 0.5, 0)
      ctx.lineTo(x + 0.5, height)
      ctx.stroke()
    })

    this.pushCanvas(canvas)
  }

  // Draws one string inside [x0, x1], shrinking the type if it would overflow.
  fill(ctx, text, { x0, x1, align, y, size }) {
    const value = String(text ?? "")
    if (value === "") return

    let fitted = size
    ctx.font = this.font(fitted)
    while (fitted > 14 && ctx.measureText(value).width > x1 - x0) {
      fitted -= 1
      ctx.font = this.font(fitted)
    }
    // Order each string by its own script. A date or a price on an Arabic receipt is
    // still read left to right, and would print as "PM 11:55 05/11/2026" if it
    // inherited the page's right-to-left base direction.
    ctx.direction = ARABIC_SCRIPT.test(value) ? "rtl" : "ltr"
    ctx.textAlign = align
    const x = align === "left" ? x0 : align === "right" ? x1 : (x0 + x1) / 2
    ctx.fillText(value, x, y)
  }

  pushCanvas(canvas) {
    const { width, height } = canvas
    const pixels = canvas.getContext("2d").getImageData(0, 0, width, height).data
    const bytesPerRow = Math.ceil(width / 8)
    const data = new Uint8Array(bytesPerRow * height)

    for (let y = 0; y < height; y++) {
      for (let x = 0; x < width; x++) {
        const i = (y * width + x) * 4
        const luminance = 0.299 * pixels[i] + 0.587 * pixels[i + 1] + 0.114 * pixels[i + 2]
        if (luminance < BLACK_BELOW) data[y * bytesPerRow + (x >> 3)] |= 0x80 >> (x & 7)
      }
    }
    this.raster(bytesPerRow, height, data)
  }
}

// ── Layouts ────────────────────────────────────────────────────────────────

const fill = (template, vars = {}) => String(template || "").replace(/%\{(\w+)\}/g, (_, key) => vars[key] ?? "")

export function fulfillmentText(order, labels) {
  if (order.order_type === "table") {
    return order.table_number
      ? fill(labels.fulfillment.table_number, { number: order.table_number })
      : labels.fulfillment.table
  }
  if (order.order_type === "delivery") return labels.fulfillment.delivery
  return labels.fulfillment.pickup
}

function pad(n) {
  return String(n).padStart(2, "0")
}

// dd/mm/yyyy hh:mm AM — what ReceiptBuilder prints.
function stamp(iso) {
  const d = new Date(iso)
  const hours = d.getHours() % 12 || 12
  return `${pad(d.getDate())}/${pad(d.getMonth() + 1)}/${d.getFullYear()} ${pad(hours)}:${pad(d.getMinutes())} ${d.getHours() < 12 ? "AM" : "PM"}`
}

function money(cents) {
  return (cents / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

// Customer receipt — ReceiptBuilder, minus what needs the server (logo, loyalty).
export function buildReceipt(order, { labels, restaurant, footer, rtl, widthChars }) {
  const r = labels.receipt
  const doc = new EscposDocument({ widthChars, rtl })
  const totals = order.totals

  doc.align("center")
  doc.bold()
  doc.text(restaurant)
  doc.doubleHeight()
  doc.text(order.offline_number)
  doc.doubleHeight(false)
  doc.bold(false)
  doc.text(stamp(order.created_at))
  doc.bold()
  doc.doubleHeight()
  doc.text(`${labels.order_type}: ${fulfillmentText(order, labels)}`)
  doc.doubleHeight(false)
  doc.bold(false)
  if (order.order_type === "delivery") {
    // Who it is going to and where — what the courier needs from the bag's receipt.
    doc.blank()
    if (order.customer_name) doc.text(order.customer_name)
    doc.text(order.customer_phone)
    doc.text(order.delivery_address)
  }
  doc.blank()

  doc.align("left")
  doc.separator()
  doc.row3(r.item, r.qty, r.price)
  doc.separator()
  order.items.forEach((line) => {
    const unit = (line.unit_price_cents || 0) + (line.modifiers || []).reduce((s, m) => s + m.price_adjustment_cents, 0)
    doc.row3(line.name, String(line.quantity), money(unit * line.quantity))
    ;(line.modifiers || []).forEach((m) => doc.modifier(`+ ${m.name}`))
    if (line.notes) doc.modifier(line.notes)
    doc.separator()
  })

  doc.blank()
  doc.row(r.subtotal, money(totals.subtotal_cents))
  if (totals.discount_cents > 0) doc.row(r.discount, `-${money(totals.discount_cents)}`)
  if (totals.tax_cents > 0) doc.row(r.tax, money(totals.tax_cents))
  doc.bold()
  doc.row(r.total, money(totals.total_cents))
  doc.bold(false)

  doc.text(r.payments)
  doc.row(`  ${labels.cash}`, money(order.tendered_cents))
  const change = order.tendered_cents - totals.total_cents
  if (change > 0) doc.row(r.change, money(change))
  doc.separator()

  if (order.notes) {
    doc.blank()
    doc.align("center")
    doc.bold()
    doc.text(labels.order_notes)
    doc.bold(false)
    doc.text(order.notes)
    doc.separator()
  }

  doc.blank()
  doc.align("center")
  doc.text(footer)
  doc.blank(4)
  doc.cut()
  return doc.toBytes()
}

// Kitchen / bar / expo ticket — ProductionTicketBuilder.
export function buildProductionTicket(order, items, title, { labels, rtl, widthChars }) {
  const r = labels.receipt
  const doc = new EscposDocument({ widthChars, rtl })

  doc.align("center")
  doc.bold()
  doc.doubleHeight()
  doc.text(title)
  doc.text(order.offline_number)
  doc.doubleHeight(false)
  doc.bold(false)
  doc.text(stamp(order.created_at))
  doc.bold()
  doc.doubleHeight()
  doc.text(fulfillmentText(order, labels))
  doc.doubleHeight(false)
  doc.bold(false)
  doc.blank()

  doc.align("left")
  doc.separator()
  doc.row(r.item, r.qty)
  doc.separator()
  items.forEach((line) => {
    doc.row(line.name, String(line.quantity))
    ;(line.modifiers || []).forEach((m) => doc.modifier(`+ ${m.name}`, { columns: 2 }))
    if (line.notes) doc.modifier(line.notes, { columns: 2 })
    doc.separator()
  })

  if (order.notes) {
    doc.blank()
    doc.align("center")
    doc.bold()
    doc.text(labels.order_notes)
    doc.bold(false)
    doc.text(order.notes)
    doc.separator()
  }

  doc.blank(4)
  doc.cut()
  return doc.toBytes()
}
