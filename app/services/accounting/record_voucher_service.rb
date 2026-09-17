# frozen_string_literal: true

module Accounting
  # Records a سند قبض / سند صرف: the document for money crossing a treasury.
  #
  # This is the only thing that moves cash for an income or an expense. Those
  # record the obligation on the date it arose and stay out of the treasury; the
  # voucher moves the money on the date it actually moved, and what sits on
  # 1170 / 2300 in between is the amount still owed either way.
  #
  # `allocations` is a list of `{ settles:, amount_cents: }` — what this voucher
  # clears and for how much. One voucher may settle several things. Anything not
  # allocated is money received or paid on account, and stays readable as
  # `voucher.unallocated_cents`.
  class RecordVoucherService
    class Error < StandardError; end

    def initialize(direction:, treasury:, user:, amount_cents:, voucher_date: Date.current,
                   allocations: [], notes: nil, counterparty: nil, company: nil)
      @direction = direction
      @treasury = treasury
      @user = user
      @amount_cents = amount_cents.to_i
      @voucher_date = voucher_date
      @allocations = allocations
      @notes = notes
      @counterparty = counterparty
      @company = company || Current.company
    end

    def call
      validate!

      voucher = nil
      ActiveRecord::Base.transaction do
        voucher = Voucher.create!(
          company: @company, direction: @direction, treasury: @treasury, user: @user,
          amount_cents: @amount_cents, voucher_date: @voucher_date,
          notes: @notes, counterparty: @counterparty
        )

        @allocations.each do |allocation|
          PaymentAllocation.create!(
            company: @company, payment: voucher,
            settles: allocation.fetch(:settles),
            amount_cents: allocation.fetch(:amount_cents).to_i
          )
        end

        TreasuryLedgerService.sync_voucher!(voucher)
        JournalEntryService.record_voucher!(voucher)
      end

      voucher
    end

    private

    def validate!
      unless Voucher::DIRECTIONS.include?(@direction)
        raise Error, I18n.t("accounting.vouchers.errors.invalid_direction",
                            default: "A voucher must be a receipt or a payment.")
      end

      if @amount_cents <= 0
        raise Error, I18n.t("accounting.vouchers.errors.invalid_amount",
                            default: "Voucher amount must be positive.")
      end

      if @treasury.blank?
        raise Error, I18n.t("accounting.vouchers.errors.treasury_required",
                            default: "A treasury is required.")
      end

      allocated = @allocations.sum { |a| a.fetch(:amount_cents).to_i }
      if allocated > @amount_cents
        raise Error, I18n.t("accounting.vouchers.errors.over_allocated",
                            default: "A voucher cannot settle more than its own amount.")
      end

      if @allocations.any? { |a| a.fetch(:amount_cents).to_i <= 0 }
        raise Error, I18n.t("accounting.vouchers.errors.invalid_allocation",
                            default: "Every line on a voucher must be a positive amount.")
      end
    end
  end
end
