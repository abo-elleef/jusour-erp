# frozen_string_literal: true

module Accounting
  class TreasuryLedgerService
    class Error < StandardError; end

    def self.remove_source!(source, kinds: nil)
      new.remove_for_source(source, kinds: kinds)
    end

    def self.sync_expense!(expense)
      new.sync_expense!(expense)
    end

    def self.sync_income!(income)
      new.sync_income!(income)
    end

    def self.sync_drawer_open!(session)
      new.sync_drawer_open!(session)
    end

    def self.sync_drawer_reconcile!(session)
      new.sync_drawer_reconcile!(session)
    end

    def sync_expense!(expense)
      remove_for_source(expense)
      return if expense.treasury_id.blank?

      record!(
        treasury: expense.treasury,
        user: expense.user,
        amount_cents: -expense.amount_cents,
        kind: "expense",
        description: expense.description,
        occurred_on: expense.expense_date,
        source: expense
      )
    end

    def sync_income!(income)
      remove_for_source(income)
      return if income.treasury_id.blank?

      record!(
        treasury: income.treasury,
        user: income.user,
        amount_cents: income.amount_cents,
        kind: "income",
        description: income.description,
        occurred_on: income.income_date,
        source: income
      )
    end

    def sync_drawer_open!(session)
      remove_for_source(session, kinds: %w[drawer_open])
      return if session.treasury_id.blank?
      return unless session.opening_float_cents.positive?

      record!(
        treasury: session.treasury,
        user: session.user,
        amount_cents: -session.opening_float_cents,
        kind: "drawer_open",
        description: drawer_open_description(session),
        occurred_on: session.session_date,
        source: session
      )
    end

    def sync_drawer_reconcile!(session)
      remove_for_source(session, kinds: %w[drawer_reconcile])
      return if session.treasury_id.blank?
      return unless session.counted_cash_cents

      record!(
        treasury: session.treasury,
        user: session.user,
        amount_cents: session.counted_cash_cents,
        kind: "drawer_reconcile",
        description: drawer_reconcile_description(session),
        occurred_on: session.session_date,
        source: session
      )
    end

    def record_adjustment!(treasury:, user:, amount_cents:, description:, occurred_on: Date.current)
      record!(
        treasury: treasury,
        user: user,
        amount_cents: amount_cents,
        kind: "adjustment",
        description: description,
        occurred_on: occurred_on,
        source: nil
      )
    end

    def remove_for_source(source, kinds: nil)
      scope = TreasuryTransaction.where(source_record: source)
      scope = scope.where(kind: kinds) if kinds
      scope.find_each do |transaction|
        treasury = transaction.treasury
        treasury.apply_balance_delta!(-transaction.amount_cents)
        transaction.destroy!
      end
    end

    private

    def record!(treasury:, user:, amount_cents:, kind:, description:, occurred_on:, source:)
      treasury.with_lock do
        treasury.apply_balance_delta!(amount_cents)
        TreasuryTransaction.create!(
          treasury: treasury,
          user: user,
          amount_cents: amount_cents,
          kind: kind,
          description: description,
          occurred_on: occurred_on,
          source_record: source,
          balance_after_cents: treasury.balance_cents
        )
      end
    end

    def drawer_open_description(session)
      I18n.t(
        "accounting.treasuries.transactions.drawer_open",
        cashier: session.user.name,
        shift: session.shift,
        date: I18n.l(session.session_date, format: :long)
      )
    end

    def drawer_reconcile_description(session)
      I18n.t(
        "accounting.treasuries.transactions.drawer_reconcile",
        cashier: session.user.name,
        shift: session.shift,
        date: I18n.l(session.session_date, format: :long)
      )
    end
  end
end
