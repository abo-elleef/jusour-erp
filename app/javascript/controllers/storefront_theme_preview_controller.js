import { Controller } from "@hotwired/stimulus"

// Live preview of the storefront brand colors on the settings page. Mirrors
// Storefront.text_color_on: white or near-black, whichever contrasts more.
export default class extends Controller {
  static targets = ["primaryColor", "accentColor", "primaryColorCode", "accentColorCode",
    "primarySample", "priceSample", "accentSample"]

  update() {
    const primary = this.primaryColorTarget.value
    const accent = this.accentColorTarget.value

    this.primaryColorCodeTarget.textContent = primary
    this.accentColorCodeTarget.textContent = accent
    this.primarySampleTarget.style.background = primary
    this.primarySampleTarget.style.color = this.#textOn(primary)
    this.priceSampleTarget.style.color = primary
    this.accentSampleTarget.style.background = accent
    this.accentSampleTarget.style.color = this.#textOn(accent)
  }

  #textOn(hex) {
    return this.#contrast(hex, "#ffffff") >= this.#contrast(hex, "#111827") ? "#ffffff" : "#111827"
  }

  #contrast(a, b) {
    const [hi, lo] = [this.#luminance(a), this.#luminance(b)].sort((x, y) => y - x)
    return (hi + 0.05) / (lo + 0.05)
  }

  #luminance(hex) {
    const [r, g, b] = hex.replace("#", "").match(/../g).map((c) => {
      const v = parseInt(c, 16) / 255
      return v <= 0.03928 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4
    })
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
  }
}
