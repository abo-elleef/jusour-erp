# frozen_string_literal: true

module Accounting
  # Pays out a finalized month: one payment voucher to the employee, linked to
  # the snapshot as its payout. Used straight from finalizing (pay now), and
  # later for a month recorded with "pay later" — the figures locked on the
  # month's last day, the money paid on the 3rd or 4th of the next.
  #
  # Without an amount it pays what the snapshot still owes
  # (PayrollSnapshot#payout_due_cents as of the payment day).
  class PayOutPayrollService
    def initialize(snapshot, treasury:, paid_by:, paid_on: nil, amount_cents: nil)
      @snapshot = snapshot
      @treasury = treasury
      @paid_by = paid_by
      @paid_on = resolve_paid_on(paid_on)
      @amount_cents = amount_cents
    end

    # The voucher, or nil when there's nothing to pay (or it's already paid).
    def call
      @snapshot.with_lock do
        next if @snapshot.paid_out?

        amount = @amount_cents || @snapshot.payout_due_cents(on: @paid_on)
        next unless amount.positive?

        user = @snapshot.user
        voucher = RecordVoucherService.new(
          direction: Voucher::PAYMENT,
          treasury: @treasury,
          user: @paid_by,
          amount_cents: amount,
          voucher_date: @paid_on,
          counterparty: user.name,
          notes: I18n.t("accounting.treasuries.transactions.payroll_salary",
                        employee: user.name,
                        month: I18n.l(@snapshot.payroll_month, format: "%B %Y")),
          party_type: "User",
          party_id: user.id
        ).call

        @snapshot.update!(remaining_pay_cents: amount, treasury: @treasury, paid_on: @paid_on, payout_voucher: voucher)
        voucher
      end
    end

    private

    # Any day from the start of the payroll month on — paying October on
    # 3 November dates the voucher (and the treasury) 3 November, while the
    # accrual stays on 31 October.
    def resolve_paid_on(date)
      date = date.presence || Date.current
      [date.to_date, @snapshot.payroll_month.beginning_of_month].max
    end
  end
end
