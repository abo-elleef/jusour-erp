# frozen_string_literal: true

module Payments
  # Moves a payment from one counter method to another (cash ↔ InstaPay ↔ Vodafone
  # Cash), for the customer who paid one way and then asks to pay another.
  #
  # Only while the payment's drawer is still open. Until it is counted, the drawer's
  # expected cash and wallet totals are worked out live from its payments, so
  # changing the method here is all it takes for both to come out right. Once the
  # drawer is counted, its expected cash is stored and its wallet totals have been
  # posted to the wallet treasuries — a change then would leave both wrong, so it is
  # refused rather than half-applied.
  class ChangeMethodService
    # The methods a drawer accounts for. Card, gift card and staff meal each settle
    # somewhere else (Stripe, the card balance, the employee's account), so a payment
    # cannot be moved into or out of them.
    CHANGEABLE_METHODS = %w[cash instapay vodafone_cash].freeze

    Result = Struct.new(:success?, :error, keyword_init: true)

    def self.call(payment:, new_method:, user:)
      new(payment: payment, new_method: new_method, user: user).call
    end

    # Whether this payment can be changed at all right now — for the views, so the
    # button only shows when pressing it would work.
    def self.changeable?(payment, user:)
      new(payment: payment, new_method: nil, user: user).blocking_error(check_target: false).nil?
    end

    def initialize(payment:, new_method:, user:)
      @payment = payment
      @new_method = new_method.to_s
      @user = user
    end

    def call
      @payment.with_lock do
        # Locked against the drawer closing at the same moment: a count that read
        # the old method and a change that lands after it would disagree.
        @payment.cash_drawer_session&.lock!
        if (error = blocking_error)
          return Result.new(success?: false, error: error)
        end

        old_method = @payment.payment_method
        @payment.update!(payment_method: @new_method)
        AuditLogEntry.record!(
          action: "payment.change_method",
          record: @payment,
          user: @user,
          changes_snapshot: { from: old_method, to: @new_method }
        )
      end
      Result.new(success?: true)
    end

    def blocking_error(check_target: true)
      return :invalid_method if check_target && !CHANGEABLE_METHODS.include?(@new_method)
      return :unchanged if check_target && @new_method == @payment.payment_method
      return :method_not_changeable unless CHANGEABLE_METHODS.include?(@payment.payment_method)
      return :not_completed unless @payment.status == "completed"

      session = @payment.cash_drawer_session
      return :drawer_closed unless session&.status == "open"
      # A cashier answers for their own drawer only; a manager or owner may correct
      # any drawer that is still open.
      return :not_your_drawer unless session.user_id == @user.id || @user.owner? || @user.manager?

      nil
    end
  end
end
