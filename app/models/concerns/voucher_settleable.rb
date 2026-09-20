# frozen_string_literal: true

# Shared by Expense and Income: the obligation is recorded here, and the cash is
# moved by a voucher.
#
# Naming a treasury is what says the money moved. An expense paid from the safe
# raises its payment voucher immediately; one with no treasury is on account and
# sits on the accrual account until a voucher settles it. There is deliberately
# no separate "paid" flag that could disagree with the treasury — a record
# naming a safe it was never paid from would be a state nobody could read.
#
# Editing keeps the voucher honest rather than letting it drift: changing the
# amount, the treasury or the date rewrites the voucher that settled it, adding
# a treasury raises one, and clearing the treasury takes it away. A voucher that
# also settled something else is left alone — it is a real document about more
# than this record, and rewriting it from here would corrupt the rest.
module VoucherSettleable
  extend ActiveSupport::Concern

  included do
    # The vouchers that have settled this, and for how much. What is left is what
    # is still owed — the balance sitting on the accrual account.
    has_many :payment_allocations, as: :settles, dependent: :destroy

    after_commit :create_settling_voucher, on: :create
    after_commit :resync_settling_voucher, on: :update
    # Prepended so it runs before `dependent: :destroy` tears the allocations
    # down — without them there is no way back to the voucher that paid this.
    before_destroy :destroy_settling_vouchers, prepend: true
  end

  def settled_on_issue?
    treasury.present?
  end

  def settled_cents
    payment_allocations.sum(:amount_cents)
  end

  def outstanding_cents
    amount_cents - settled_cents
  end

  private

  # Implemented by the including model.
  def voucher_direction    = raise(NotImplementedError)
  def settlement_date      = raise(NotImplementedError)
  def settlement_date_changed? = raise(NotImplementedError)

  def create_settling_voucher
    return unless settled_on_issue?
    return if ledger_owned_elsewhere?
    return if payment_allocations.any?

    raise_voucher!
  end

  # An edit rewrites the voucher rather than leaving it describing an amount,
  # a treasury or a date that is no longer true. The old one is destroyed, which
  # returns its cash, and a fresh one issued — so the voucher number changes with
  # the document, which is what an accountant would expect of a reissued سند.
  # Records whose entry belongs to another service never had a voucher to keep
  # in step. Overridden where that is possible; false everywhere else.
  def ledger_owned_elsewhere? = false

  def resync_settling_voucher
    return if ledger_owned_elsewhere?
    return unless saved_change_to_amount_cents? ||
                  saved_change_to_treasury_id? ||
                  settlement_date_changed?

    sole_settling_voucher&.destroy!
    raise_voucher! if settled_on_issue?
  end

  def raise_voucher!
    Accounting::RecordVoucherService.new(
      direction: voucher_direction, treasury: treasury, user: user,
      amount_cents: amount_cents, voucher_date: settlement_date,
      allocations: [{ settles: self, amount_cents: amount_cents }],
      notes: description, company: company
    ).call
  end

  # The voucher raised for this record and nothing else. A voucher that also
  # settled other things is somebody's real document and is left untouched.
  def sole_settling_voucher
    voucher_ids = payment_allocations.where(payment_type: "Voucher").select(:payment_id)
    Voucher.where(id: voucher_ids).where(backfilled_at: nil).find do |voucher|
      voucher.payment_allocations.where.not(settles: self).none?
    end
  end

  # Deleting takes back the money paid for it. A voucher that exists only to
  # settle this goes with it; one that also settled something else stays.
  def destroy_settling_vouchers
    voucher_ids = payment_allocations.where(payment_type: "Voucher").select(:payment_id)
    Voucher.where(id: voucher_ids).find_each do |voucher|
      voucher.destroy! if voucher.payment_allocations.where.not(settles: self).none?
    end
  end
end
