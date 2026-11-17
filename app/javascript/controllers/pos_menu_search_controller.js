import { Controller } from "@hotwired/stimulus"

// POS menu search, for a cashier who never touches the mouse:
//   F2 (or /) focuses the box → type part of a name or code, Arabic or English
//   → the grid filters live and the first match is highlighted
//   → arrows move the highlight by what is on screen (rows and columns, RTL aware)
//   → Enter opens the highlighted item's add popup (a combo is added straight away)
//   → when that popup closes, the box gets the focus back with its text selected,
//     so the next item is typed at once. Esc clears the search and leaves the
//     box, so 1–9 / 0 switch categories again.
// Hiding uses its own `search-miss` class, so it never fights the category
// filter's `hidden` (pos_controller#filterCategory).

const ARABIC_DIGITS = { "٠": "0", "١": "1", "٢": "2", "٣": "3", "٤": "4", "٥": "5", "٦": "6", "٧": "7", "٨": "8", "٩": "9",
                        "۰": "0", "۱": "1", "۲": "2", "۳": "3", "۴": "4", "۵": "5", "۶": "6", "۷": "7", "۸": "8", "۹": "9" }

// "أولد" and "اولد" must match the same card: fold the letters people type
// interchangeably, drop tashkeel/tatweel, lowercase Latin.
export function normalizeSearch(text) {
  return (text || "")
    .toLowerCase()
    .replace(/[٠-٩۰-۹]/g, (d) => ARABIC_DIGITS[d])
    .replace(/[ً-ْٰـ]/g, "")
    .replace(/[أإآٱ]/g, "ا")
    .replace(/ة/g, "ه")
    .replace(/ى/g, "ي")
    .replace(/ؤ/g, "و")
    .replace(/ئ/g, "ي")
    .replace(/\s+/g, " ")
    .trim()
}

const ACTIVE = "pos-card-active"

export default class extends Controller {
  static targets = ["input", "empty"]

  connect() {
    this.popupClosed = this.popupClosed.bind(this)
    document.addEventListener("pos:popup-closed", this.popupClosed)
  }

  disconnect() {
    document.removeEventListener("pos:popup-closed", this.popupClosed)
  }

  // Called by pos-shortcuts for F2 / "/".
  focus() {
    this.inputTarget.focus()
    this.inputTarget.select()
    if (!this.active()) this.highlight(this.visibleCards()[0])
  }

  search() {
    const words = normalizeSearch(this.inputTarget.value).split(" ").filter(Boolean)
    if (words.length === 0) return this.clearFilter()

    if (!this.searching) {
      this.searching = true
      // Search the whole menu: switch the rail to "All" without clearing ourselves.
      this.selfClick = true
      this.element.querySelector('.pos-category-btn[data-category="all"]')?.click()
      this.selfClick = false
    }
    this.repeatSections().forEach((section) => section.classList.add("search-miss"))

    let matches = 0
    this.gridCards().forEach((card) => {
      const haystack = card.dataset.searchNormalized ??= normalizeSearch(card.dataset.search)
      const hit = words.every((w) => haystack.includes(w))
      card.classList.toggle("search-miss", !hit)
      if (hit) matches++
    })
    if (this.hasEmptyTarget) this.emptyTarget.classList.toggle("hidden", matches > 0)
    this.highlight(this.visibleCards()[0])
  }

  keydown(event) {
    if (event.isComposing) return
    switch (event.key) {
      case "ArrowDown": case "ArrowUp": case "ArrowLeft": case "ArrowRight":
        event.preventDefault()
        this.move(event.key)
        break
      case "Enter":
        event.preventDefault()
        this.open(this.active())
        break
      case "Escape":
        // Clear and step out of the box, so the number keys pick categories again.
        event.preventDefault()
        event.stopPropagation()
        if (this.inputTarget.value) {
          this.inputTarget.value = ""
          this.clearFilter()
        }
        this.inputTarget.blur()
        break
    }
  }

  // A category picked by hand ends the search, so the rail shows what it says.
  categoryPicked() {
    if (this.selfClick) return
    this.highlight(null)
    if (!this.inputTarget.value) return
    this.inputTarget.value = ""
    this.clearFilter()
  }

  clearFilter() {
    this.searching = false
    this.gridCards().forEach((card) => card.classList.remove("search-miss"))
    this.repeatSections().forEach((section) => section.classList.remove("search-miss"))
    if (this.hasEmptyTarget) this.emptyTarget.classList.add("hidden")
    this.highlight(null)
  }

  open(card) {
    if (!card) return
    this.openedFromSearch = !card.matches("form")
    if (card.matches("form")) card.requestSubmit()
    else card.click()
  }

  // The add popup closed (added, cancelled or Esc): back to the box, text
  // selected. Only when it was opened from here — a tap on a tablet must not
  // pop the on-screen keyboard up.
  popupClosed() {
    if (!this.openedFromSearch) return
    this.openedFromSearch = false
    requestAnimationFrame(() => {
      if (!this.element.isConnected) return
      this.inputTarget.focus()
      this.inputTarget.select()
    })
  }

  move(key) {
    const cards = this.visibleCards()
    if (cards.length === 0) return
    const current = this.active()
    if (!current || !cards.includes(current)) return this.highlight(cards[0])

    const box = (el) => el.getBoundingClientRect()
    const here = box(current)
    const cx = here.left + here.width / 2
    const sameRow = (r) => Math.abs(r.top - here.top) < here.height / 2

    let next = null
    if (key === "ArrowLeft" || key === "ArrowRight") {
      const goingLeft = key === "ArrowLeft"
      const row = cards.filter((c) => c !== current && sameRow(box(c)))
        .filter((c) => (goingLeft ? box(c).left < here.left : box(c).left > here.left))
      next = row.sort((a, b) => Math.abs(box(a).left - here.left) - Math.abs(box(b).left - here.left))[0]
      if (!next) {
        // End of the row: wrap to the next/previous card in reading order.
        const rtl = getComputedStyle(this.element).direction === "rtl"
        const forward = rtl ? goingLeft : !goingLeft
        next = cards[cards.indexOf(current) + (forward ? 1 : -1)]
      }
    } else {
      const down = key === "ArrowDown"
      const others = cards.filter((c) => (down ? box(c).top > here.top + here.height / 2 : box(c).top < here.top - here.height / 2))
      if (others.length) {
        const rowTop = down ? Math.min(...others.map((c) => box(c).top)) : Math.max(...others.map((c) => box(c).top))
        next = others.filter((c) => Math.abs(box(c).top - rowTop) < here.height / 2)
          .sort((a, b) => Math.abs(box(a).left + box(a).width / 2 - cx) - Math.abs(box(b).left + box(b).width / 2 - cx))[0]
      }
    }
    if (next) this.highlight(next)
  }

  highlight(card) {
    this.active()?.classList.remove(ACTIVE)
    if (!card) return
    card.classList.add(ACTIVE)
    card.scrollIntoView({ block: "nearest" })
  }

  active() {
    return this.element.querySelector(`.menu-card.${ACTIVE}`)
  }

  // Offers and Most sold repeat full-menu cards, so they are hidden while searching.
  repeatSections() {
    return this.element.querySelectorAll('[data-pos-target="offersSection"], [data-pos-target="topSellersSection"]')
  }

  // Cards of the full menu (the repeat sections are left out while searching).
  gridCards() {
    return [...this.element.querySelectorAll('[data-pos-target="menuGrid"] .menu-card')]
  }

  visibleCards() {
    return [...this.element.querySelectorAll(".menu-card")].filter((c) => c.getClientRects().length > 0)
  }
}
