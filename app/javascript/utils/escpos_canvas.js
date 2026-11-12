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
// Kitchen/station tickets: rows sit further from the paper edge, the item name is
// bold and larger and the quantity larger still — Document::PAD_DOTS and
// ArabicImageRenderer::BOLD_LABEL_PT / BOLD_VALUE_PT.
const TICKET_PAD_PX = 32
const BOLD_LABEL_PX = 32
const BOLD_VALUE_PX = 40
// Line height as a multiple of the text size: 2 for receipts, 1.5 for compact
// kitchen tickets — ArabicImageRenderer::DEFAULT/COMPACT_LINE_FACTOR.
const DEFAULT_LINE_FACTOR = 2
const COMPACT_LINE_FACTOR = 1.5
// Quantity column: this share of the paper on the value side, quantity centred in
// it; the item name gets the rest — Document::VALUE_COLUMN_SHARE.
const VALUE_COLUMN_SHARE = 0.35
const WRAP_SEPARATORS = ["+", "•", "|"]
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
  constructor({ widthChars = 42, rtl = false, compact = false } = {}) {
    this.px = PAPER_PX[widthChars] || 576
    this.rtl = rtl
    this.lineFactor = compact ? COMPACT_LINE_FACTOR : DEFAULT_LINE_FACTOR
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

  // Feed the last line to the cutter, then cut, with no extra blank paper — the
  // same GS V 66 0 the server sends (Document#cut, CUT_EXTRA_FEED_DOTS).
  cut() {
    this.raw([0x1d, 0x56, 0x42, 0])
  }

  text(line = "") {
    const size = BASE_PX * this.scale
    const lines = this.wrap(String(line), this.px - 8, size)
    this.drawBlock(lines.length, size, (ctx, y, i) => {
      this.fill(ctx, lines[i], { x0: 4, x1: this.px - 4, align: this.alignment, y, size })
    })
  }

  // Label on the reading-start side, value on the other (mirrored for RTL).
  // boldLabel / boldValue: that side bold and larger (ticket item rows). A bold label
  // in the value column wraps onto further rows, the value staying on the first —
  // TicketItemsTable#compose_items_table on the Rails side.
  row(label, value = "", { padded = false, boldValue = false, boldLabel = false, valueColumn = false } = {}) {
    const size = BASE_PX
    const pad = padded ? TICKET_PAD_PX : 8
    const labelSize = boldLabel ? BOLD_LABEL_PX : size
    const valueSize = boldValue ? BOLD_VALUE_PX : size
    // Each side is drawn bold by switching emphasis on just for it.
    const emphasised = (on, fn) => {
      const was = this.emphasis
      if (on) this.emphasis = true
      const result = fn()
      this.emphasis = was
      return result
    }
    const asValue = (fn) => emphasised(boldValue, fn)
    const asLabel = (fn) => emphasised(boldLabel, fn)
    const heightFor = (text) => Math.max(labelSize, boldValue && String(text) !== "" ? valueSize : size)

    if (valueColumn) {
      // Value centred in its column (35% of the paper); the label gets the other 65%.
      const split = Math.round(this.px * VALUE_COLUMN_SHARE)
      const valueBox = this.rtl ? { x0: 0, x1: split } : { x0: this.px - split, x1: this.px }
      const labelBox = this.rtl ? { x0: split + 12, x1: this.px - pad } : { x0: pad, x1: this.px - split - 12 }
      const lines = boldLabel ? asLabel(() => this.wrap(String(label), labelBox.x1 - labelBox.x0, labelSize)) : [label]
      lines.forEach((line, i) => {
        const rowValue = i === 0 ? value : ""
        this.drawBlock(1, heightFor(rowValue), (ctx, y) => {
          asValue(() => this.fill(ctx, rowValue, { ...valueBox, align: "center", y, size: valueSize }))
          asLabel(() => this.fill(ctx, line, { ...labelBox, align: this.rtl ? "right" : "left", y, size: labelSize }))
        })
      })
      return
    }
    this.drawBlock(1, heightFor(value), (ctx, y) => {
      const valueWidth = asValue(() => this.measure(String(value), valueSize))
      const labelBox = this.px - 2 * pad - valueWidth - 12
      if (this.rtl) {
        asValue(() => this.fill(ctx, value, { x0: pad, x1: this.px - pad, align: "left", y, size: valueSize }))
        asLabel(() => this.fill(ctx, label, { x0: this.px - pad - labelBox, x1: this.px - pad, align: "right", y, size: labelSize }))
      } else {
        asLabel(() => this.fill(ctx, label, { x0: pad, x1: pad + labelBox, align: "left", y, size: labelSize }))
        asValue(() => this.fill(ctx, value, { x0: pad, x1: this.px - pad, align: "right", y, size: valueSize }))
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
  // bold: the same bold, larger text as a ticket's item name (BOLD_LABEL_PX) —
  // Document#modifier_text(bold: true) on the Rails side.
  modifier(text, { columns = 3, padded = false, bold = false } = {}) {
    const size = bold ? BOLD_LABEL_PX : BASE_PX
    const { labelBox, rules } = this.columns()
    const pad = padded ? TICKET_PAD_PX : 8
    const box = columns === 3 ? labelBox : { x0: pad, x1: this.px - pad }
    const was = this.emphasis
    if (bold) this.emphasis = true
    const lines = this.wrap(String(text), box.x1 - box.x0, size)
    this.drawBlock(lines.length, size, (ctx, y, i) => {
      this.fill(ctx, lines[i], { ...box, align: this.rtl ? "right" : "left", y, size })
    }, columns === 3 ? rules : [])
    this.emphasis = was
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
    // A separator ("+", "•", "|") travels with the word after it, so a wrapped line
    // never ends on one — TicketItemsTable.wrap on the Rails side.
    const words = text.split(/\s+/).filter(Boolean).reduce((acc, word) => {
      if (acc.length && WRAP_SEPARATORS.includes(acc[acc.length - 1])) acc[acc.length - 1] += ` ${word}`
      else acc.push(word)
      return acc
    }, [])
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
    // Space above and below the text: a full line on receipts, less when compact.
    const margin = size * (this.lineFactor - 1)
    const height = lineCount === 1 ? Math.round(size * this.lineFactor) : Math.round(lineCount * lineHeight + margin)
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
      const y = lineCount === 1 ? height / 2 : margin / 2 + i * lineHeight + lineHeight / 2
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
  doc.text(fulfillmentText(order, labels))
  doc.doubleHeight(false)
  doc.bold(false)
  if (order.order_type === "delivery") {
    // Who it is going to and where — what the courier needs from the bag's receipt.
    doc.blank()
    if (order.customer_name) doc.text(order.customer_name)
    doc.bold()
    doc.doubleHeight()
    doc.text(order.customer_phone)
    doc.doubleHeight(false)
    doc.bold(false)
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
    // Every modifier and the note on one line, like the station tickets.
    const detail = ticketDetail(line)
    if (detail) doc.modifier(detail)
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
  doc.row(`  ${labels.cash}`, money(order.tendered_cents), { boldLabel: true })
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
  doc.cut()
  return doc.toBytes()
}

// "+ Double • Extra cheese | no sauce" — TicketItemsTable on the Rails side.
// doc.modifier wraps it when it is wider than the paper.
function ticketDetail(line) {
  const modifiers = (line.modifiers || []).map((m) => m.name).filter(Boolean)
  const parts = []
  if (modifiers.length) parts.push(`+ ${modifiers.join(" • ")}`)
  if (line.notes && String(line.notes).trim()) parts.push(String(line.notes).trim().replace(/\s+/g, " "))
  return parts.join(" | ")
}

// Kitchen / bar / expo ticket — ProductionTicketBuilder.
export function buildProductionTicket(order, items, title, { labels, rtl, widthChars, cashier, station }) {
  const r = labels.receipt
  const doc = new EscposDocument({ widthChars, rtl, compact: true })

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
  // Who sent it and from which register — IssuedBy on the Rails side.
  doc.align("left")
  // labels.ticket is missing on an offline page cached before this was added.
  const ticketLabels = labels.ticket || {}
  doc.row(ticketLabels.cashier || "Cashier", cashier || "-", { padded: true })
  doc.row(ticketLabels.station || "Station", station || "-", { padded: true })

  doc.align("left")
  doc.separator()
  doc.row(r.item, r.qty, { padded: true, valueColumn: true })
  doc.separator()
  items.forEach((line) => {
    doc.row(line.name, String(line.quantity), { padded: true, boldValue: true, boldLabel: true, valueColumn: true })
    // Every modifier and the note on one line — TicketItemsTable#detail_lines.
    const detail = ticketDetail(line)
    if (detail) doc.modifier(detail, { columns: 2, padded: true, bold: true })
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

  // The cut command feeds the last line to the cutter itself; no blank lines.
  doc.cut()
  return doc.toBytes()
}
