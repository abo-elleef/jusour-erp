# frozen_string_literal: true

module OnlineOrders
  # A cashier accepts a self-order: it becomes a normal POS order owned by that
  # cashier (so it shows in their shift and Collect Payment), priced again from the
  # database, then placed — order number, kitchen tickets, receipt, KDS.
  #
  # The order belongs to the register the cashier accepted it on (workstation:),
  # exactly like an order rung up there, so the customer receipt prints on that
  # register's receipt printer.
  #
  # If prices moved since the customer sent it (a promo ended, a price changed),
  # nothing is created until the cashier confirms the new total.
  #
  # A prepaid request (the customer chose a "pay before ordering" method and sent
  # a screenshot) is paid in full on accept, by that method, into the accepting
  # cashier's drawer: checking the screenshot is part of accepting. The payment is
  # the order's total, so if prices moved the cashier settles the difference with
  # the customer (the POS warns them before they confirm).
  class AcceptService
    Result = Struct.new(:order, :error, :new_total_cents, :details, keyword_init: true) do
      def ok? = error.nil?
    end

    def self.call(...)
      new(...).call
    end

    def initialize(request:, user:, workstation: nil, confirm_price_change: false)
      @request = request
      @user = user
      @workstation = workstation
      @confirm_price_change = confirm_price_change
    end

    def call
      result = @request.with_lock { build_order }
      return result unless result.ok?

      Orders::PlaceService.call(result.order, user: @user)
      record_prepayment(result.order) if @request.prepaid?
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

      # What the cashier saw, before accepting creates the customer record.
      @request.record_check!(:decided)
      customer = FindOrCreateCustomer.call(@request)
      remember_address(customer)
      order = Orders::CreateService.call(
        user: @user, customer: customer, location: @request.location, workstation: @workstation,
        order_type: @request.fulfillment, delivery_address: @request.address
      )
      order.update!(source: @request.call_center? ? "call_center" : "online", notes: order_notes, delivery_area: (@request.delivery_area if @request.delivery?))
      quote.lines.each { |line| Orders::AddLineService.call(order: order, line: line) }
      order.apply_delivery_fee!(@request.delivery_fee_cents) if @request.delivery?
      order.recalculate_totals!

      @request.update!(status: "accepted", order: order, decided_by: @user, decided_at: Time.current)
      AuditLogEntry.record!(action: "online_order.accept", record: order, user: @user,
                            changes_snapshot: { "online_order_request_id" => @request.id })
      Result.new(order: order)
    end

    def record_prepayment(order)
      order.reload
      return unless order.amount_due_cents.positive?

      Payments::CashPaymentService.call(order: order, amount_cents: order.amount_due_cents, tip_cents: 0,
                                        user: @user, payment_method: @request.payment_method)
      Orders::FinalizePaidService.call(order)
    end

    def quote_total_sent
      @request.quote.fetch("total_cents", @request.total_cents)
    end

    def order_notes
      prefix = if @request.call_center?
                 I18n.t("pos.online_orders.call_center_note_prefix", phone: @request.phone, agent: @request.created_by&.name.to_s)
               else
                 I18n.t("pos.online_orders.order_note_prefix", phone: @request.phone)
               end
      [prefix, @request.note].compact.join(" — ")
    end

    def remember_address(customer)
      return unless @request.delivery? && @request.address.present?
      return if customer.addresses.exists?(address: @request.address)

      customer.addresses.create!(address: @request.address)
    end
  end
end
