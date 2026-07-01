# frozen_string_literal: true

module Payments
  class StaffMealPaymentService
    def self.call(order:, staff_meal_user:, treasury:, processed_by:)
      ApplicationRecord.transaction do
        order.update!(staff_meal_user: staff_meal_user)

        payment = order.payments.create!(
          payment_method: "staff_deduction",
          amount_cents: order.total_cents,
          tip_cents: 0,
          status: "completed",
          processed_by_user: processed_by
        )

        Accounting::TreasuryLedgerService.record_staff_meal!(
          treasury: treasury,
          payment: payment,
          user: processed_by
        )

        payment
      end
    end
  end
end
