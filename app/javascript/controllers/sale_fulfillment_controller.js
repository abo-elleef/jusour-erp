import { Controller } from "@hotwired/stimulus"

// Shows the shipping-company picker only for a delivery, and the online
// payment-method picker only when "online" is chosen — both stay in the DOM
// (so their values still submit/validate) but hidden otherwise.
export default class extends Controller {
  static targets = ["fulfillmentSelect", "paymentSelect", "shippingCompanyWrap", "onlineMethodWrap"]

  connect() {
    this.applyFulfillment()
    this.applyPaymentMethod()
  }

  applyFulfillment() {
    this.shippingCompanyWrapTarget.hidden = this.fulfillmentSelectTarget.value !== "delivery"
  }

  applyPaymentMethod() {
    this.onlineMethodWrapTarget.hidden = this.paymentSelectTarget.value !== "online"
  }
}
