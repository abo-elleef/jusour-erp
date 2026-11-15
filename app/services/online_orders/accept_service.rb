# frozen_string_literal: true

module OnlineOrders
  # A cashier accepts a self-order: it becomes a normal POS order owned by that
  # cashier (so it shows in their shift and Collect Payment), priced again from the
  # database, then placed — order number, kitchen tickets, receipt, KDS.
  #
  # If prices moved since the customer sent it (a promo ended, a price changed),
  # nothing is created until the cashier confirms the new total.
  class AcceptService
    Result = Struct.new(:order, :error, :new_total_cents, :details, keyword_init: true) do
      def ok? = error.nil?
    end

    def self.call(...)
      new(...).call
    end

    def initialize(request:, user:, confirm_price_change: false)
      @request = request
      @user = user
      @confirm_price_change = confirm_price_change
    end

    def call
      result = @request.with_lock { build_order }
      return result unless result.ok?

      Orders::PlaceService.call(result.order, user: @user)
      @request.update!(total_cents: result.order.reload.total_cents)
      Broadcast.inbox(@request.location)
      result
    end

    private

    def build_order
      return Result.new(error: :not_pending) unless @request.pending?
      return Result.new(error: :expired) if @request.overdue?

      quote = Orders::QuoteService.call(location: @request.location, items: @request.cart,
                                        delivery_fee_cents: @request.delivery_fee_cents)
      return Result.new(error: :items_changed, details: quote.errors) unless quote.ok?
      if quote.total_cents != quote_total_sent && !@confirm_price_change
        return Result.new(error: :price_changed, new_total_cents: quote.total_cents)
      end

      customer = FindOrCreateCustomer.call(@request)
      remember_address(customer)
      order = Orders::CreateService.call(
        user: @user, customer: customer, location: @request.location,
        order_type: @request.fulfillment, delivery_address: @request.address
      )
      order.update!(source: "online", notes: order_notes)
      quote.lines.each { |line| Orders::AddLineService.call(order: order, line: line) }
      order.apply_delivery_fee!(@request.delivery_fee_cents) if @request.delivery?
      order.recalculate_totals!

      @request.update!(status: "accepted", order: order, decided_by: @user, decided_at: Time.current)
      AuditLogEntry.record!(action: "online_order.accept", record: order, user: @user,
                            changes_snapshot: { "online_order_request_id" => @request.id })
      Result.new(order: order)
    end

    def quote_total_sent
      @request.quote.fetch("total_cents", @request.total_cents)
    end

    def order_notes
      [I18n.t("pos.online_orders.order_note_prefix", phone: @request.phone), @request.note].compact.join(" — ")
    end

    def remember_address(customer)
      return unless @request.delivery? && @request.address.present?
      return if customer.addresses.exists?(address: @request.address)

      customer.addresses.create!(address: @request.address)
    end
  end
end
