# frozen_string_literal: true

module Accounting
  # Cashier sales for one cash-drawer session: hard cash + shared digital wallets.
  # Prefers payments linked to the session; falls back to order owner + time window.
  #
  # Counts takings from both selling motions. A restaurant's cash arrives as POS
  # payments; a distributor's arrives as customer invoices settled at the counter,
  # which are not orders at all. Leaving those out made the drawer read over by the
  # whole day's invoice cash, every day.
  class SessionSalesSummary
    Result = Struct.new(
      :opening_float_cents,
      :cash_cents,
      :cash_refunds_cents,
      :instapay_cents,
      :vodafone_cash_cents,
      keyword_init: true
    ) do
      def cash_net_cents
        cash_cents - cash_refunds_cents
      end

      def total_sales_cents
        cash_net_cents + instapay_cents + vodafone_cash_cents
      end

      def digital_totals
        {
          "instapay" => instapay_cents,
          "vodafone_cash" => vodafone_cash_cents
        }
      end

      def expected_cash_cents
        opening_float_cents + cash_net_cents
      end
    end

    def self.for_session(session)
      new(session).call
    end

    def self.for_user_window(user_id:, start_time:, end_time:, opening_float_cents: 0)
      new(nil, user_id: user_id, start_time: start_time, end_time: end_time, opening_float_cents: opening_float_cents).call
    end

    def initialize(session, user_id: nil, start_time: nil, end_time: nil, opening_float_cents: 0)
      @session = session
      @user_id = session&.user_id || user_id
      @start_time = start_time
      @end_time = end_time
      @opening_float_cents = session&.opening_float_cents || opening_float_cents
    end

    def call
      Result.new(
        opening_float_cents: @opening_float_cents.to_i,
        cash_cents: sum_for("cash") + invoice_sales_for("cash"),
        cash_refunds_cents: refunds_for("cash"),
        instapay_cents: sum_for("instapay") + invoice_sales_for("instapay"),
        vodafone_cash_cents: sum_for("vodafone_cash") + invoice_sales_for("vodafone_cash")
      )
    end

    private

    def range_start
      @start_time || @session&.created_at
    end

    def range_end
      return @end_time if @end_time
      return Time.current if @session.nil? || @session.status == "open"

      @session.updated_at
    end

    def base_scope
      scope = Payment.joins(:order).where(status: "completed")

      if @session
        scope.where(
          "(payments.cash_drawer_session_id = :sid) OR " \
          "(payments.cash_drawer_session_id IS NULL AND orders.user_id = :uid AND payments.created_at BETWEEN :start AND :end)",
          sid: @session.id,
          uid: @user_id,
          start: range_start,
          end: range_end
        )
      else
        scope.where(orders: { user_id: @user_id })
          .where(created_at: range_start..range_end)
      end
    end

    def sum_for(method)
      base_scope.where(payment_method: method).sum(:amount_cents).to_i
    end

    # Counter sales settled on the invoice itself, taken by this cashier during the
    # session. They carry no Payment row — the invoice is the payment.
    def invoice_sales_for(method)
      return 0 if @user_id.blank?

      CustomerInvoice.confirmed
        .where(payment_method: method, user_id: @user_id)
        .where(confirmed_at: range_start..range_end)
        .sum(:total_cents).to_i
    end

    def refunds_for(method)
      base_scope.where(payment_method: method).sum(:refunded_amount_cents).to_i
    end
  end
end
