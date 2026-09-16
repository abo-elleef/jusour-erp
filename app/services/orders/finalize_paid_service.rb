# frozen_string_literal: true

module Orders
  # What happens when the last of the money lands: the order leaves the cart and
  # goes to the kitchen as `submitted`, and stops there.
  #
  # It used to complete the order in the same breath. Closing an order is now the
  # cashier's own call — see CompleteService — because being paid for and being
  # finished are different things, and only the person at the counter knows when
  # the second one is true.
  class FinalizePaidService
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      @order.reload
      return @order unless @order.fully_paid?

      submit_if_needed!
      @order.reload
    end

    private

    def submit_if_needed!
      return unless @order.draft?
      return if @order.order_items.empty?

      SubmitService.call(@order)
    end
  end
end
