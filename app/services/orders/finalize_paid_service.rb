# frozen_string_literal: true

module Orders
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
      @order.mark_ready! if @order.may_mark_ready?
      @order.complete! if @order.may_complete?
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
