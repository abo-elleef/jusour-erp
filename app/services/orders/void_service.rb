# frozen_string_literal: true

module Orders
  # Voids an order: cancels it (which puts stock, loyalty and a posted sales day
  # back for a completed one), refunds whatever was paid, and records who did it.
  # Shared by the admin order page and the register's void-orders PIN.
  #
  # Money is refunded two ways, depending on where it was taken:
  # - a drawer still open (or no drawer: card, online): on the payment itself, so
  #   that drawer's expected cash comes out right when it is counted;
  # - a drawer already counted: by a payment voucher from `refund_treasury`. Writing
  #   it onto the payment would quietly lower the closed drawer's expected cash
  #   after its count and safe deposit, while the cash really leaves somewhere else.
  class VoidService
    Result = Struct.new(:voided, :refunded_cents, :error, :voucher, keyword_init: true) do
      def voided? = voided
    end

    def self.call(...) = new(...).call

    # open_drawers_only: the register's void, which refuses closed-drawer money
    # altogether (it is the admin side's job).
    def initialize(order:, user:, reason: nil, open_drawers_only: false, refund_treasury: nil)
      @order = order
      @user = user
      @reason = reason.presence || "Voided by manager"
      @open_drawers_only = open_drawers_only
      @refund_treasury = refund_treasury
    end

    def call
      return failure(nil) unless @order.may_cancel?
      # Checked again under lock below; this keeps a refused void from first
      # cancelling a pending card payment.
      if (error = closed_drawer_error(@order.closed_drawer_refundable_cents))
        return failure(error)
      end

      @order.payments.where(status: "pending").find_each do |payment|
        if payment.stripe_payment_intent_id
          ::Payments::StripeTerminalService.cancel_payment_intent(payment.stripe_payment_intent_id)
        end
      end

      refunded_cents = 0
      voucher = nil
      error = nil
      @order.with_lock do
        # Against a drawer closing at the same moment.
        CashDrawerSession.where(id: @order.payments.select(:cash_drawer_session_id)).order(:id).lock.to_a
        closed_cents = @order.closed_drawer_refundable_cents
        error = closed_drawer_error(closed_cents)
        next if error

        @order.cancel!(by: @user)
        refunded_cents = ::Payments::RefundService.call(order: @order, amount_cents: @order.refundable_cents - closed_cents,
                                                      reason: @reason, user: @user, skip_closed_drawers: true)
        if closed_cents.positive?
          voucher = refund_voucher!(closed_cents)
          refunded_cents += closed_cents
        end
        @order.order_events.create!(event_type: "void", user: @user, description: @reason)
      end
      return failure(error) if error

      Result.new(voided: true, refunded_cents: refunded_cents, voucher: voucher)
    end

    private

    def closed_drawer_error(closed_cents)
      return unless closed_cents.positive?
      return :drawer_closed if @open_drawers_only

      :treasury_required if @refund_treasury.blank?
    end

    def refund_voucher!(amount_cents)
      voucher = ::Accounting::RecordVoucherService.new(
        direction: Voucher::PAYMENT,
        treasury: @refund_treasury,
        user: @user,
        amount_cents: amount_cents,
        voucher_date: Date.current,
        counterparty: @order.customer&.display_name,
        notes: I18n.t("order.refund_voucher_notes", number: @order.display_number,
                                                          date: I18n.l(@order.business_date || @order.created_at.to_date),
                                                          reason: @reason),
        allocations: [{ settles: @order, amount_cents: amount_cents }],
        company: @order.company
      ).call
      @order.order_events.create!(event_type: "refund", user: @user,
                                  description: "Refunded #{amount_cents} cents by voucher #{voucher.number}: #{@reason}")
      voucher
    end

    def failure(error) = Result.new(voided: false, refunded_cents: 0, error: error)
  end
end
