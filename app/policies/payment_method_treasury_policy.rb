# frozen_string_literal: true

class PaymentMethodTreasuryPolicy < AccountingPolicy
  def destroy?
    owner?
  end
end
