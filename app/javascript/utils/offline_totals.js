// The same money arithmetic Rails does for an order — Order#recalculate_totals!
// and Tax::CalculateService — so the total on an offline receipt is the total
// the server arrives at when the order syncs.
//
//   line     = (unit price + modifiers) × quantity
//   discount = promo markdown per unit × quantity
//   tax      = Σ per line, per active rate of that line's tax category:
//              round(line × rate)          (rounded half up, rate a decimal)
//   total    = subtotal − discount + tax
//
// Tax is done in integers: the rate arrives as a decimal string and a float would
// turn a legitimate .5 into .4999999.

export function unitCents(line) {
  const modifiers = (line.modifiers || []).reduce((sum, m) => sum + (m.price_adjustment_cents || 0), 0)
  return (line.unit_price_cents || 0) + modifiers
}

export function lineTotal(line) {
  return unitCents(line) * (line.quantity || 0)
}

export function lineDiscount(line) {
  return (line.promo_discount_cents || 0) * (line.quantity || 0)
}

function parseRate(text) {
  const [whole, fraction = ""] = String(text).trim().split(".")
  return { numerator: BigInt(`${whole || "0"}${fraction}`), scale: 10n ** BigInt(fraction.length) }
}

// round(cents × rate), half up.
export function taxOn(cents, rateText) {
  const { numerator, scale } = parseRate(rateText)
  const product = BigInt(cents) * numerator
  return Number((product * 2n + scale) / (scale * 2n))
}

export function computeTotals(lines, taxRates) {
  let subtotal = 0
  let discount = 0
  let tax = 0

  lines.forEach((line) => {
    const total = lineTotal(line)
    subtotal += total
    discount += lineDiscount(line)
    taxRates
      .filter((rate) => rate.tax_category === (line.tax_category || "food"))
      .forEach((rate) => {
        tax += taxOn(total, rate.rate)
      })
  })

  return { subtotal_cents: subtotal, discount_cents: discount, tax_cents: tax, total_cents: subtotal - discount + tax }
}

export function formatMoney(cents) {
  return (cents / 100).toLocaleString("en-US", { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

// "12", "12.5", "١٢٫٥" → 1250. Returns null for anything that is not an amount.
export function parseAmountToCents(text) {
  const ascii = String(text)
    .replace(/[٠-٩]/g, (d) => String(d.charCodeAt(0) - 0x0660))
    .replace(/[۰-۹]/g, (d) => String(d.charCodeAt(0) - 0x06f0))
    .replace(/٫/g, ".")
    .replace(/,/g, "")
    .trim()
  if (!/^\d+(\.\d{0,2})?$/.test(ascii)) return null

  return Math.round(parseFloat(ascii) * 100)
}
