# frozen_string_literal: true

module Payments
  # Settles a list of outstanding orders in cash in one go — the end-of-service
  # sweep, where a cashier has a stack of tickets whose money is already in the
  # drawer and no interest in opening twenty payment modals.
  #
  # Each order is paid to the penny of what it still owes, so an order that was
  # part paid by card or wallet only takes the remainder in cash. Orders are
  # settled one at a time rather than in a single transaction: if the tenth fails,
  # the nine already collected are real money that must stay recorded.
  class BulkCashCollectService
    # missing_area: delivery orders left alone because their branch makes the
    # delivery area compulsory and none was picked (Order#needs_delivery_area?).
    # Also counted in skipped.
    Result = Struct.new(:settled, :skipped, :missing_area, :collected_cents, keyword_init: true) do
      def any?
        settled.any?
      end
    end

    def self.call(orders:, user:)
      new(orders: orders, user: user).call
    end

    def initialize(orders:, user:)
      @orders = orders
      @user = user
    end

    def call
      settled = []
      skipped = []
      missing_area = []
      collected = 0

      @orders.each do |order|
        due = order.amount_due_cents
        next skipped << order unless due.positive?

        if order.needs_delivery_area?
          skipped << order
          missing_area << order
          next
        end

        begin
          settle!(order, due)
          settled << order
          collected += due
        rescue StandardError => e
          Rails.logger.error("[BulkCashCollect] order #{order.order_number}: #{e.message}")
          skipped << order
        end
      end

      Result.new(settled: settled, skipped: skipped, missing_area: missing_area, collected_cents: collected)
    end

    private

    def settle!(order, due_cents)
      CashPaymentService.call(
        order: order,
        amount_cents: due_cents,
        tip_cents: 0,
        user: @user,
        payment_method: "cash"
      )
      # Takes a paid draft out of the cart and into the kitchen queue, exactly as a
      # single payment would. It does not complete the order — that stays the
      # cashier's own call.
      Orders::FinalizePaidService.call(order)
    end
  end
end
