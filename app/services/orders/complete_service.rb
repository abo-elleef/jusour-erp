# frozen_string_literal: true

module Orders
  # Closing an order is a cashier's decision, not a side effect of taking the money.
  #
  # Paying used to complete an order in the same request, which meant an order was
  # "done" the moment it was rung up — before the food was handed over, and whether
  # or not the cashier had anything more to do with it. Payment now leaves the order
  # `submitted`; this is what closes it, either one order at a time or for a whole
  # shift at once.
  #
  # Completing does not require payment. An order handed over now and settled later
  # is the case this exists for; it stays on Collect Payment until the money
  # arrives, because `not_fully_paid` looks at the balance, not the status.
  class CompleteService
    Result = Struct.new(:completed, :skipped, keyword_init: true) do
      def any?
        completed.any?
      end
    end

    def self.call(order)
      new(order).call
    end

    # Completes what it can and reports the rest rather than stopping at the first
    # order that will not move — a cashier closing a shift wants the other twenty
    # closed, not an error.
    def self.call_all(orders)
      completed = []
      skipped = []

      orders.each do |order|
        if call(order)
          completed << order
        else
          skipped << order
        end
      end

      Result.new(completed: completed, skipped: skipped)
    end

    def initialize(order)
      @order = order
    end

    def call
      return false if @order.completed? || @order.cancelled?

      submit_if_needed!
      return false unless @order.may_complete?

      @order.complete!
      true
    rescue Orders::SubmitService::InvalidFulfillment
      # A table order with no table number, or a delivery with no address. Skipped
      # rather than raised: it is the cashier's to fix, and it must not take the
      # rest of a bulk close down with it.
      false
    end

    private

    # A pay-later order that was never charged is still sitting in `draft`, and the
    # state machine only reaches `completed` from an open state.
    def submit_if_needed!
      return unless @order.draft?
      return if @order.order_items.empty?

      SubmitService.call(@order)
    end
  end
end
