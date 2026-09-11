# frozen_string_literal: true

module Sales
  # Where the money for a point-of-sale settlement lands.
  #
  # Wallet takings go to the treasury the company has mapped for that wallet — the
  # same mapping the POS uses at day close, so instapay money ends up in one place
  # whichever way it was taken. Cash goes to the seller's own drawer when they have
  # one, otherwise the company default.
  module SettlementTreasury
    module_function

    # => Treasury, or nil when the company has not set one up for this method
    def for(method:, user: nil, company: Current.company)
      return nil if method.blank? || method == CustomerInvoice::ON_ACCOUNT

      if Payment::DIGITAL_WALLET_METHODS.include?(method)
        PaymentMethodTreasury.find_by(payment_method: method)&.treasury
      else
        cash_treasury(user, company)
      end
    end

    def cash_treasury(user, company)
      assigned = user&.assigned_treasury
      return assigned if assigned&.active? && assigned.treasury_type == "cash_drawer"

      Treasury.active.where(treasury_type: "cash_drawer").ordered.first ||
        Treasury.default_treasury
    end

    # Methods this company can actually settle with right now — a wallet with no
    # treasury mapped would take money nowhere, so it isn't offered.
    def available_methods(company: Current.company, user: nil)
      CustomerInvoice::PAID_NOW_METHODS.select { |m| self.for(method: m, user: user, company: company).present? }
    end
  end
end
