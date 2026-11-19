import { Controller } from "@hotwired/stimulus"

// Shows the shipping-company picker only for a delivery, and the online
// payment-method picker only when "online" is chosen — both stay in the DOM
// (so their values still submit/validate) but hidden otherwise.
export default class extends Controller {
  static targets = [
    "fulfillmentSelect", "paymentSelect", "shippingCompanyWrap", "onlineMethodWrap",
    "deliveryFeeWrap", "deliveryFeeAmountInput", "onlineMethodSelect", "proofWrap"
  ]

  connect() {
    this.applyFulfillment()
    this.applyPaymentMethod()
  }

  applyFulfillment() {
    const isDelivery = this.fulfillmentSelectTarget.value === "delivery"
    this.shippingCompanyWrapTarget.hidden = !isDelivery
    if (this.hasDeliveryFeeWrapTarget) this.deliveryFeeWrapTarget.hidden = !isDelivery

    // Pickup never carries a delivery fee (the model zeroes it on save) — clear
    // the visible field too, so the live running total stays accurate while hidden.
    if (!isDelivery && this.hasDeliveryFeeAmountInputTarget) {
      this.deliveryFeeAmountInputTarget.value = ""
      this.deliveryFeeAmountInputTarget.dispatchEvent(new Event("input", { bubbles: true }))
    }
  }

  applyPaymentMethod() {
    this.onlineMethodWrapTarget.hidden = this.paymentSelectTarget.value !== "online"
    this.applyProofRequirement()
  }

  // The proof image is required (at confirm) only for an online method with
  // requires_proof_image; say so next to the upload field.
  applyProofRequirement() {
    if (!this.hasProofWrapTarget) return
    const requiredIds = JSON.parse(this.proofWrapTarget.dataset.proofRequiredIds || "[]")
    const methodId = this.hasOnlineMethodSelectTarget ? this.onlineMethodSelectTarget.value : ""
    const required = this.paymentSelectTarget.value === "online" && requiredIds.includes(methodId)
    this.proofWrapTarget.querySelector("[data-role='proof-required-hint']")?.classList.toggle("hidden", !required)
    this.proofWrapTarget.querySelector("[data-role='proof-optional-hint']")?.classList.toggle("hidden", required)
  }
}
