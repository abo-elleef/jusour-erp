import { Controller } from "@hotwired/stimulus"

// A native <input type="number"> silently rejects Eastern Arabic-Indic and
// Persian digits, forcing a language switch just to type a count while
// searching for the item in Arabic. This controller goes on a plain text
// input instead, rewriting those digits (and the Arabic decimal separator)
// to their ASCII equivalents as the user types, so the field still ends up
// holding a value Ruby's `to_d`/decimal casting understands.
const DIGIT_MAP = {
  "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4",
  "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
  "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4",
  "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9",
  "٫": "."
}
const PATTERN = new RegExp(Object.keys(DIGIT_MAP).join("|"), "g")
// Decimal separators a user might type: ASCII dot/comma, Arabic decimal
// separator and Arabic comma.
const SEPARATOR = /[.,٫،]/

export default class extends Controller {
  // `whole: true` makes the field refuse fractions (e.g. sales quantities when
  // the owner hasn't allowed them): a separator and anything after it is cut
  // off as it's typed or pasted, and `wholeMessage` pops up to say why.
  static values = { whole: Boolean, wholeMessage: String }

  // Tapping a count field selects it, so typing replaces the number.
  select() {
    this.element.select()
  }

  // Enter inside a self-submitting field: let the `change` event do the one submit
  // (on blur) instead of also triggering the form's own implicit submit.
  commit(event) {
    event.preventDefault()
    this.element.blur()
  }

  normalize() {
    this.mapDigits()
    if (this.wholeValue) this.dropFraction()
  }

  mapDigits() {
    const input = this.element
    if (!input.value || !PATTERN.test(input.value)) return
    PATTERN.lastIndex = 0

    const caret = input.selectionStart
    input.value = input.value.replace(PATTERN, (ch) => DIGIT_MAP[ch])
    // One-for-one character substitution, so the caret position doesn't move.
    if (caret !== null) input.setSelectionRange(caret, caret)
  }

  dropFraction() {
    const input = this.element
    if (!SEPARATOR.test(input.value)) return

    input.value = input.value.split(SEPARATOR)[0]
    if (this.wholeMessageValue) {
      input.setCustomValidity(this.wholeMessageValue)
      input.reportValidity()
      // Clear it so the (now whole) value doesn't block the form's submit.
      input.setCustomValidity("")
    }
  }
}
