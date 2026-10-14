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
                   allocations: [], notes: nil, counterparty: nil, company: nil,
                   purpose: Voucher::SETTLEMENT, party_type: nil, party_id: nil)
      @direction = direction
      @treasury = treasury
      @user = user
      @amount_cents = amount_cents.to_i
      @voucher_date = voucher_date
      @allocations = allocations
      @notes = notes
      @counterparty = counterparty
      @company = company || Current.company
      @purpose = purpose
      @party_type = party_type
      @party_id = party_id
    end

    def call
      validate!

      voucher = nil
      ActiveRecord::Base.transaction do
        voucher = Voucher.create!(
          company: @company, direction: @direction, treasury: @treasury, user: @user,
          amount_cents: @amount_cents, voucher_date: @voucher_date,
          notes: @notes, counterparty: @counterparty, purpose: @purpose,
          party_type: @party_type, party_id: @party_id
        )

        @allocations.each do |allocation|
          PaymentAllocation.create!(
            company: @company, payment: voucher,
            settles: allocation.fetch(:settles),
            amount_cents: allocation.fetch(:amount_cents).to_i
          )
        end

        ensure_counterparty_treasuries!(voucher)
        apply_to_invoices!(voucher)

        TreasuryLedgerService.sync_voucher!(voucher)
        JournalEntryService.record_voucher!(voucher)
      end

      voucher
    end

    private

    # A customer's receivable and a supplier's payable are treasuries created on
    # demand — an ordinary POS customer who never buys on credit never gets one.
    # The ledger services this replaced ensured them before posting; reading the
    # association directly meant the first payment from a customer with no credit
    # history took the page down instead.
    #
    # Also covers the voucher's own party, not just what it settles: naming a
    # Customer as an on-account voucher's party is meant to credit their AR the
    # same way settling them directly would (JournalEntryService#accrual_account_for
    # reads Customer#to_account for exactly this), which needs their treasury to
    # exist first. A Supplier never needs this — it gets its AP treasury at
    # creation, before it can ever be picked as a party.
    def ensure_counterparty_treasuries!(voucher)
      @allocations.each do |allocation|
        case (target = allocation.fetch(:settles))
        when ::Customer        then CustomerArLedgerService.new(target).ensure_treasury!
        when ::CustomerInvoice then CustomerArLedgerService.new(target.customer).ensure_treasury!
        when ::Supplier        then target.ensure_ap_treasury!
        when ::VendorInvoice   then target.supplier.ensure_ap_treasury!
        end
      end

      CustomerArLedgerService.new(voucher.party).ensure_treasury! if voucher.party.is_a?(::Customer)
      ShippingCompanyLedgerService.new(voucher.party).ensure_treasury! if voucher.party.is_a?(::ShippingCompany)
    end

    # An invoice carries its own paid-to-date and status, unlike an expense or an
    # income, whose outstanding amount is derived from the allocations alone.
    # Done here rather than in a PaymentAllocation callback on purpose: the
    # backfill writes allocations for payments whose invoices were already
    # marked paid years ago, and a callback would count those a second time.
    def apply_to_invoices!(voucher)
      voucher.payment_allocations.each do |allocation|
        invoice = allocation.settles
        next unless invoice.is_a?(::VendorInvoice) || invoice.is_a?(::CustomerInvoice)

        invoice.update!(amount_paid_cents: invoice.amount_paid_cents + allocation.amount_cents)
        invoice.sync_payment_status!
      end
    end

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
