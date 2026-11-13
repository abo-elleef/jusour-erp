# frozen_string_literal: true

module Accounting
  # Books a documented drawer's over/short as documents a person can open.
  #
  # At close the safe receives what the drawer should have held (expected); the
  # gap to what was counted is booked here, so the safe still ends holding
  # exactly the cash that went into it:
  #
  #   over  → an Income in the branch's "cash over" category, into the branch's
  #           chosen treasury (the drawer's own safe when none is set);
  #   short → a payment voucher from the safe to the cashier's staff account, as
  #           if they took the missing cash. It is money given to them, so the
  #           payroll month nets it like any other voucher — nobody adds a penalty.
  #   short, waived by a manager → an Expense in the branch's "cash short"
  #           category instead, paid from the same safe.
  #
  # `sync!` rebuilds from the drawer as it stands (removing what was there
  # first), so reconcile, waive, un-waive and a count correction all go through
  # it. `remove!` takes everything back, for a reopen.
  class DrawerVarianceDocuments
    def self.sync!(session, by:)
      new(session, by: by).sync!
    end

    def self.remove!(session, by: nil)
      new(session, by: by).remove!
    end

    def initialize(session, by:)
      @session = session
      @by = by || session.user
    end

    def sync!
      CashDrawerSession.transaction do
        remove!
        next unless @session.variance_documented? && @session.status == "reconciled"

        if @session.over?
          record_overage!
        elsif @session.short?
          @session.shortage_waived? ? record_waived_shortage! : record_shortage_voucher!
        end
      end
      @session
    end

    def remove!
      if (voucher = @session.shortage_voucher)
        @session.update_columns(shortage_voucher_id: nil)
        voucher.void!(user: @by, reason: :drawer_variance_resynced)
      end
      # Destroying them voids the voucher that moved their cash and removes
      # their journal entry (VoucherSettleable / their own after_destroy).
      @session.variance_incomes.reload.each(&:destroy!)
      @session.variance_expenses.reload.each(&:destroy!)
      @session
    end

    private

    def amount_cents = @session.variance_cents.to_i.abs

    def record_overage!
      location = @session.location
      Income.create!(
        company: @session.company,
        income_category: location.cash_over_income_category!,
        treasury: location.cash_over_treasury || @session.variance_treasury,
        user: @by,
        amount_cents: amount_cents,
        income_date: @session.session_date,
        description: description(:over),
        is_auto_generated: true,
        source_record: @session
      )
    end

    def record_shortage_voucher!
      cashier = @session.user
      voucher = RecordVoucherService.new(
        direction: Voucher::PAYMENT,
        treasury: @session.variance_treasury,
        user: @by,
        amount_cents: amount_cents,
        voucher_date: @session.session_date,
        counterparty: cashier.name,
        notes: description(:short),
        purpose: Voucher::CASH_SHORTAGE,
        party_type: "User",
        party_id: cashier.id,
        company: @session.company
      ).call
      @session.update_columns(shortage_voucher_id: voucher.id)
    end

    def record_waived_shortage!
      Expense.create!(
        company: @session.company,
        expense_category: @session.location.cash_short_expense_category!,
        treasury: @session.variance_treasury,
        user: @session.shortage_waived_by || @by,
        amount_cents: amount_cents,
        expense_date: @session.session_date,
        description: description(:waived),
        is_auto_generated: true,
        source_record: @session
      )
    end

    # Everything the accountant needs to explain the line without opening the
    # drawer: who, where, which day, and the two figures the gap came from.
    def description(kind)
      I18n.t(
        "accounting.cash_drawer.variance_docs.description.#{kind}",
        amount: format_amount(amount_cents),
        cashier: @session.user.name,
        branch: @session.location&.name,
        drawer: @session.treasury.name,
        date: I18n.l(@session.session_date, format: :long),
        expected: format_amount(@session.expected_cash_cents),
        counted: format_amount(@session.counted_cash_cents)
      )
    end

    def format_amount(cents)
      Money.new(cents || 0).format(locale: I18n.locale, symbol: false)
    end
  end
end
