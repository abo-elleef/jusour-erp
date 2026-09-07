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

    def self.create_transfer!(transfer)
      new.create_transfer!(transfer)
    end

    def self.sync_payroll_advance!(advance)
      new.sync_payroll_advance!(advance)
    end

    def self.sync_payroll_salary!(snapshot)
      new.sync_payroll_salary!(snapshot)
    end

    def self.record_staff_meal!(treasury:, payment:, user:)
      new.record_staff_meal!(treasury: treasury, payment: payment, user: user)
    end

    def self.sync_session_online_payments!(session)
      new.sync_session_online_payments!(session)
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

    def sync_payroll_advance!(advance)
      remove_for_source(advance)
      JournalEntryService.destroy_for_source!(advance)
      return if advance.treasury_id.blank?

      record!(
        treasury: advance.treasury,
        user: advance.paid_by,
        amount_cents: -advance.amount_cents,
        kind: "payroll_advance",
        description: payroll_advance_description(advance),
        occurred_on: advance.paid_on,
        source: advance
      )
      JournalEntryService.record_payroll_advance!(advance)
    end

    def sync_payroll_salary!(snapshot)
      remove_for_source(snapshot)
      JournalEntryService.destroy_for_source!(snapshot)
      return unless snapshot.payout_required?
      return if snapshot.treasury_id.blank?

      record!(
        treasury: snapshot.treasury,
        user: snapshot.finalized_by,
        amount_cents: -snapshot.remaining_pay_cents,
        kind: "payroll_salary",
        description: payroll_salary_description(snapshot),
        occurred_on: snapshot.paid_on,
        source: snapshot
      )
      JournalEntryService.record_payroll_salary!(snapshot)
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

    # The float is carried into the drawer from a safe: it leaves one treasury and
    # arrives in the other. Both legs are recorded, so neither treasury drifts.
    def sync_drawer_open!(session)
      remove_for_source(session, kinds: %w[drawer_open])
      return if session.treasury_id.blank?
      return unless session.opening_float_cents.positive?

      if session.float_source_treasury.present?
        record!(
          treasury: session.float_source_treasury,
          user: session.user,
          amount_cents: -session.opening_float_cents,
          kind: "drawer_open",
          description: drawer_open_description(session),
          occurred_on: session.session_date,
          source: session
        )
      end

      record!(
        treasury: session.treasury,
        user: session.user,
        amount_cents: session.opening_float_cents,
        kind: "drawer_open",
        description: drawer_open_description(session),
        occurred_on: session.session_date,
        source: session
      )
      JournalEntryService.record_drawer_open!(session)
    end

    # Only the cash *taken* during the session lands here — the float went into the
    # drawer when it opened, so banking the full counted amount would count it twice.
    def sync_drawer_reconcile!(session)
      remove_for_source(session, kinds: %w[drawer_reconcile])
      return if session.treasury_id.blank?
      return unless session.counted_cash_cents
      return if session.cash_collected_cents.zero?

      record!(
        treasury: session.treasury,
        user: session.user,
        amount_cents: session.cash_collected_cents,
        kind: "drawer_reconcile",
        description: drawer_reconcile_description(session),
        occurred_on: session.session_date,
        source: session
      )
      JournalEntryService.record_drawer_reconcile!(session)
    end

    def sync_session_online_payments!(session)
      remove_for_source(session, kinds: %w[online_payment])

      summary = SessionSalesSummary.for_session(session)

      Payment::DIGITAL_WALLET_METHODS.each do |method|
        mapping = PaymentMethodTreasury.find_by(payment_method: method)
        next unless mapping

        total_cents = summary.digital_totals.fetch(method, 0)
        next if total_cents.zero?

        record!(
          treasury: mapping.treasury,
          user: session.user,
          amount_cents: total_cents,
          kind: "online_payment",
          description: I18n.t(
            "accounting.treasuries.transactions.online_payment",
            method: I18n.t("payment.methods.#{method}"),
            cashier: session.user.name,
            date: I18n.l(session.session_date, format: :long)
          ),
          occurred_on: session.session_date,
          source: session
        )
        JournalEntryService.record_online_payment!(
          treasury: mapping.treasury,
          amount_cents: total_cents,
          user: session.user,
          session: session
        )
      end
    end

    def record_staff_meal!(treasury:, payment:, user:)
      record!(
        treasury: treasury,
        user: user,
        amount_cents: -payment.amount_cents,
        kind: "staff_meal",
        description: I18n.t("accounting.shared.staff_meal_description", name: payment.order.staff_meal_user.name),
        occurred_on: Date.current,
        source: payment
      )
      JournalEntryService.record_staff_meal!(order: payment.order, treasury: treasury, user: user)
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
      JournalEntryService.record_adjustment!(treasury: treasury, amount_cents: amount_cents,
                                             user: user, description: description)
    end

    def create_transfer!(transfer)
      raise ActiveRecord::RecordInvalid, transfer unless transfer.valid?

      ApplicationRecord.transaction do
        transfer.save!
        record_transfer_ledger!(transfer)
        JournalEntryService.record_transfer!(transfer)
        transfer
      end
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

    def payroll_advance_description(advance)
      I18n.t(
        "accounting.treasuries.transactions.payroll_advance",
        employee: advance.user.name,
        month: I18n.l(advance.payroll_month, format: "%B %Y")
      )
    end

    def payroll_salary_description(snapshot)
      I18n.t(
        "accounting.treasuries.transactions.payroll_salary",
        employee: snapshot.user.name,
        month: I18n.l(snapshot.payroll_month, format: "%B %Y")
      )
    end

    def drawer_open_description(session)
      I18n.t(
        "accounting.treasuries.transactions.drawer_open",
        cashier: session.user.name,
        date: I18n.l(session.session_date, format: :long)
      )
    end

    def drawer_reconcile_description(session)
      I18n.t(
        "accounting.treasuries.transactions.drawer_reconcile",
        cashier: session.user.name,
        date: I18n.l(session.session_date, format: :long)
      )
    end

    def record_transfer_ledger!(transfer)
      record!(
        treasury: transfer.from_treasury,
        user: transfer.user,
        amount_cents: -transfer.amount_cents,
        kind: "transfer",
        description: transfer_out_description(transfer),
        occurred_on: transfer.occurred_on,
        source: transfer
      )
      record!(
        treasury: transfer.to_treasury,
        user: transfer.user,
        amount_cents: transfer.amount_cents,
        kind: "transfer",
        description: transfer_in_description(transfer),
        occurred_on: transfer.occurred_on,
        source: transfer
      )
    end

    def transfer_out_description(transfer)
      I18n.t(
        "accounting.treasuries.transactions.transfer_out",
        treasury: transfer.to_treasury.name,
        notes: transfer.description
      )
    end

    def transfer_in_description(transfer)
      I18n.t(
        "accounting.treasuries.transactions.transfer_in",
        treasury: transfer.from_treasury.name,
        notes: transfer.description
      )
    end
  end
end
