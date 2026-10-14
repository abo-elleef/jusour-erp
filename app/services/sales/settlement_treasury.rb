# frozen_string_literal: true

module Sales
  # Where the money for a point-of-sale settlement lands.
  #
  # Cash goes to the seller's own drawer when they have one, otherwise the
  # company default. Online goes wherever the invoice's own
  # Sales::PaymentMethod says (a Sales-only, per-company configurable list —
  # deliberately separate from PaymentMethodTreasury, which is shared POS
  # day-close infrastructure this module doesn't touch). Cash-on-delivery and
  # on_account settle nowhere at confirm time — neither has a treasury yet.
  module SettlementTreasury
    module_function

    # => Treasury, or nil when there is nowhere for this invoice to settle yet.
    def for(invoice:, user: nil)
      case invoice.payment_method
      when CustomerInvoice::CASH   then cash_treasury(user, invoice.company)
      when CustomerInvoice::ONLINE then invoice.sales_payment_method&.treasury
      end
    end

    def cash_treasury(user, company)
      assigned = user&.assigned_treasury
      return assigned if assigned&.active? && assigned.treasury_type == "cash_drawer"

      Treasury.active.where(treasury_type: "cash_drawer").ordered.first ||
        Treasury.default_treasury
    end
  end
end
