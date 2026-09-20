# frozen_string_literal: true

module Accounting
  class TreasuryLedgerService
    class Error < StandardError; end

    def self.remove_source!(source, kinds: nil)
      new.remove_for_source(source, kinds: kinds)
    end

    # Only for an expense whose journal entry belongs to another service — see
    # Expense#ledger_owned_elsewhere?. Everything else moves its cash through a
    # voucher.
    def self.sync_expense_cash!(expense)
      new.sync_expense_cash!(expense)
    end

    def self.sync_voucher!(voucher)
      new.sync_voucher!(voucher)
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

    def self.sync_drawer_deposit!(session)
      new.sync_drawer_deposit!(session)
    end

    # An advance is money handed to an employee against next month's pay. It
    # happens daily here, and it left no document — the same gap the expense and
    # the supplier payment had. It is a voucher now, settling the advance, with
    # the advances account (5500) as its far side, which is exactly the entry it
    # posted before.
    #
    # The movement keeps the `payroll_advance` kind: the cash flow statement
    # counts it as operating and the profit-to-cash bridge compares it against
    # what 5500 was charged. Nothing about the money is reclassified.
    def sync_payroll_advance!(advance)
      remove_for_source(advance)
      JournalEntryService.destroy_for_source!(advance)
      return if advance.treasury_id.blank?

      RecordVoucherService.new(
        direction: Voucher::PAYMENT,
        treasury: advance.treasury,
        user: advance.paid_by,
        amount_cents: advance.amount_cents,
        voucher_date: advance.paid_on,
        counterparty: advance.user.name,
        notes: payroll_advance_description(advance),
        company: advance.company,
        allocations: [{ settles: advance, amount_cents: advance.amount_cents }]
      ).call
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

    def sync_expense_cash!(expense)
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

    # A voucher is the only thing that moves this cash: the income or expense it
    # settles records the obligation and stays out of the treasury entirely.
    def sync_voucher!(voucher)
      remove_for_source(voucher)

      record!(
        treasury: voucher.treasury,
        user: voucher.user,
        amount_cents: voucher.signed_amount_cents,
        kind: voucher.treasury_kind,
        description: voucher_description(voucher),
        occurred_on: voucher.voucher_date,
        source: voucher
      )

      sync_voucher_counterparties!(voucher)
    end

    # A supplier's payable and a customer's receivable are each held as a
    # treasury of their own, so settling an invoice has to draw that balance
    # down as well as move the cash. Only invoices have one — an expense or an
    # income is settled against an accrual account, which is ledger-only.
    #
    # These carry the ap_payment / ar_payment kinds the AP and AR ledgers
    # already use, so the supplier and customer statements keep reading them.
    # Neither is counted again as operating cash: the AP treasury is excluded
    # from the cash flow outright, and ar_payment is not an operating kind —
    # the cash itself is already counted once, on the voucher's own leg.
    def sync_voucher_counterparties!(voucher)
      voucher.payment_allocations.each do |allocation|
        treasury, kind = case allocation.settles
                         when ::VendorInvoice
                           [allocation.settles.supplier.ap_treasury, "ap_payment"]
                         when ::CustomerInvoice
                           [allocation.settles.customer.ar_treasury, "ar_payment"]
                         when ::Supplier
                           [allocation.settles.ap_treasury, "ap_payment"]
                         when ::Customer
                           [allocation.settles.ar_treasury, "ar_payment"]
                         end
        next if treasury.blank?

        record!(
          treasury: treasury,
          user: voucher.user,
          amount_cents: -allocation.amount_cents,
          kind: kind,
          description: voucher_description(voucher),
          occurred_on: voucher.voucher_date,
          source: voucher
        )
      end
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

    # Hands the counted cash over to the safe it physically goes into: out of the
    # drawer, into the destination, both legs recorded so neither drifts. The whole
    # count leaves, float included — every open pulls a fresh float in, so a drawer
    # that kept one would be holding two by the next shift.
    def sync_drawer_deposit!(session)
      remove_for_source(session, kinds: %w[drawer_deposit])
      return if session.deposit_treasury_id.blank? || session.treasury_id.blank?
      return unless session.deposit_cents.positive?

      description = drawer_deposit_description(session)

      record!(
        treasury: session.treasury,
        user: session.user,
        amount_cents: -session.deposit_cents,
        kind: "drawer_deposit",
        description: description,
        occurred_on: session.session_date,
        source: session
      )
      record!(
        treasury: session.deposit_treasury,
        user: session.user,
        amount_cents: session.deposit_cents,
        kind: "drawer_deposit",
        description: description,
        occurred_on: session.session_date,
        source: session
      )
      JournalEntryService.record_drawer_deposit!(session)
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

    # Adjusting a treasury moves real money — 1.7m of it across this company's
    # history — and used to leave no document: no number, no counterparty, and a
    # journal entry with no source, so nothing could be traced back to why the
    # balance changed. It also dated the entry today while dating the cash
    # movement `occurred_on`, so a back-dated adjustment put the two in
    # different months.
    #
    # It is a voucher now. One record carries one date, the entry points back at
    # it, and it prints like any other سند. The treasury kind stays `adjustment`
    # — the cash flow statement and the profit-to-cash bridge both read it, and
    # nothing about the money has been reclassified.
    def record_adjustment!(treasury:, user:, amount_cents:, description:, occurred_on: Date.current)
      RecordVoucherService.new(
        direction: amount_cents.positive? ? Voucher::RECEIPT : Voucher::PAYMENT,
        purpose: Voucher::EQUITY_ADJUSTMENT,
        treasury: treasury,
        user: user,
        amount_cents: amount_cents.abs,
        voucher_date: occurred_on,
        notes: description,
        company: treasury.company
      ).call
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

    def drawer_deposit_description(session)
      I18n.t(
        "accounting.treasuries.transactions.drawer_deposit",
        from: session.treasury.name,
        to: session.deposit_treasury.name,
        date: I18n.l(session.session_date, format: :long),
        default: "Drawer banked — #{session.treasury.name} → #{session.deposit_treasury.name}"
      )
    end

    def voucher_description(voucher)
      [voucher.number, voucher.counterparty.presence, voucher.notes.presence]
        .compact.join(" — ")
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
