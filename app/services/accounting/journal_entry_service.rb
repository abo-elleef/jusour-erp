# frozen_string_literal: true

module Accounting
  # Generates double-entry journal entries for every financial event in the system.
  # Called from model callbacks and existing services — never mutates treasury balances itself.
  # Account code convention:
  #   1xxx  Current Assets (treasury accounts)
  #   2xxx  Liabilities (supplier AP)
  #   3001  Retained Earnings / Equity
  #   4xxx  Revenue (income categories, 4001+)
  #   5xxx  Expenses
  #     5001-5499  Expense categories (dynamic)
  #     5500       Payroll — Advances
  #     5501       Payroll — Salaries
  #     5502       Staff Meals
  #     5503       Cost of Goods Sold (COGS, no treasury)
  class JournalEntryService
    EQUITY_CODE      = 3001
    ADVANCE_CODE     = 5500
    SALARY_CODE      = 5501
    STAFF_MEAL_CODE  = 5502
    COGS_CODE        = 5503
    INTEREST_CODE    = 5600

    TREASURY_TYPE_BASE = {
      "cash_drawer"   => 1000,
      "bank"          => 1100,
      "safe"          => 1200,
      "petty_cash"    => 1300,
      "mobile_wallet" => 1400,
      "other"         => 1500,
      "supplier_ap"   => 2000
    }.freeze

    class << self
      # ── Expense ──────────────────────────────────────────────────────
      def record_expense!(expense)
        return unless expense.treasury_id.present?

        destroy_for_source!(expense)
        create! source: expense, date: expense.expense_date, user: expense.user,
                description: I18n.t("accounting.journal_entries.auto.expense",
                                    category: expense.expense_category.name,
                                    default: "Expense — #{expense.expense_category.name}") do |lines|
          lines << debit(account_for_expense_category(expense.expense_category),
                         expense.amount_cents, "expense")
          lines << credit(account_for_treasury(expense.treasury),
                          expense.amount_cents, "asset")
        end
      end

      # ── Income ───────────────────────────────────────────────────────
      def record_income!(income)
        destroy_for_source!(income)
        create! source: income, date: income.income_date, user: income.user,
                description: I18n.t("accounting.journal_entries.auto.income",
                                    category: income.income_category.name,
                                    default: "Income — #{income.income_category.name}") do |lines|
          lines << debit(account_for_treasury(income.treasury), income.amount_cents, "asset")
          lines << credit(account_for_income_category(income.income_category),
                          income.amount_cents, "revenue")
        end
      end

      # ── Treasury Transfer ─────────────────────────────────────────────
      def record_transfer!(transfer)
        destroy_for_source!(transfer)
        create! source: transfer, date: Date.current, user: transfer.user,
                description: I18n.t("accounting.journal_entries.auto.transfer",
                                    from: transfer.from_treasury.name,
                                    to: transfer.to_treasury.name,
                                    default: "Transfer: #{transfer.from_treasury.name} → #{transfer.to_treasury.name}") do |lines|
          lines << debit(account_for_treasury(transfer.to_treasury),   transfer.amount_cents, "asset")
          lines << credit(account_for_treasury(transfer.from_treasury), transfer.amount_cents, "asset")
        end
      end

      # ── Manual Treasury Adjustment ────────────────────────────────────
      def record_adjustment!(treasury:, amount_cents:, user:, description:)
        # amount_cents is signed: positive = deposit, negative = withdrawal
        if amount_cents.positive?
          # Cash in → DR Treasury, CR Equity
          create! source: nil, date: Date.current, user: user, description: description do |lines|
            lines << debit(account_for_treasury(treasury), amount_cents, "asset")
            lines << credit({ code: EQUITY_CODE, name: I18n.t("accounting.chart_of_accounts.retained_earnings", default: "Retained Earnings") },
                            amount_cents, "equity")
          end
        else
          # Cash out → DR Equity, CR Treasury
          abs = amount_cents.abs
          create! source: nil, date: Date.current, user: user, description: description do |lines|
            lines << debit({ code: EQUITY_CODE, name: I18n.t("accounting.chart_of_accounts.retained_earnings", default: "Retained Earnings") },
                           abs, "equity")
            lines << credit(account_for_treasury(treasury), abs, "asset")
          end
        end
      end

      # ── Drawer Open ───────────────────────────────────────────────────
      # Float leaves a safe/source to open the drawer (if opening_float > 0)
      def record_drawer_open!(session)
        destroy_for_source!(session, kind: :open)
        return unless session.opening_float_cents.to_i.positive?

        create! source: session, date: session.session_date, user: session.user,
                description: I18n.t("accounting.journal_entries.auto.drawer_open",
                                    treasury: session.treasury.name,
                                    default: "Cash Drawer Opened — #{session.treasury.name}"),
                source_tag: :open do |lines|
          lines << debit(account_for_treasury(session.treasury),
                         session.opening_float_cents, "asset")
          lines << credit({ code: EQUITY_CODE, name: I18n.t("accounting.chart_of_accounts.retained_earnings", default: "Retained Earnings") },
                          session.opening_float_cents, "equity")
        end
      end

      # ── Drawer Reconcile ──────────────────────────────────────────────
      # Counted cash is confirmed into the treasury
      def record_drawer_reconcile!(session)
        destroy_for_source!(session, kind: :reconcile)
        return unless session.counted_cash_cents.to_i.positive?

        create! source: session, date: Date.current, user: session.user,
                description: I18n.t("accounting.journal_entries.auto.drawer_reconcile",
                                    treasury: session.treasury.name,
                                    default: "Cash Drawer Reconciled — #{session.treasury.name}"),
                source_tag: :reconcile do |lines|
          lines << debit(account_for_treasury(session.treasury),
                         session.counted_cash_cents, "asset")
          lines << credit({ code: EQUITY_CODE, name: I18n.t("accounting.chart_of_accounts.retained_earnings", default: "Retained Earnings") },
                          session.counted_cash_cents, "equity")
        end
      end

      # ── Online / Digital Payment session total ────────────────────────
      def record_online_payment!(treasury:, amount_cents:, user:, session:)
        return unless amount_cents.positive?

        create! source: session, date: Date.current, user: user,
                description: I18n.t("accounting.journal_entries.auto.online_payment",
                                    treasury: treasury.name,
                                    default: "Digital Payment Received — #{treasury.name}"),
                source_tag: :online do |lines|
          lines << debit(account_for_treasury(treasury), amount_cents, "asset")
          lines << credit({ code: EQUITY_CODE, name: I18n.t("accounting.chart_of_accounts.retained_earnings", default: "Retained Earnings") },
                          amount_cents, "equity")
        end
      end

      # ── Payroll Advance ───────────────────────────────────────────────
      def record_payroll_advance!(advance)
        destroy_for_source!(advance)
        create! source: advance, date: advance.paid_on, user: advance.paid_by,
                description: I18n.t("accounting.journal_entries.auto.payroll_advance",
                                    employee: advance.user.name,
                                    default: "Payroll Advance — #{advance.user.name}") do |lines|
          lines << debit({ code: ADVANCE_CODE,
                           name: I18n.t("accounting.journal_entries.accounts.payroll_advances", default: "Payroll — Advances") },
                         advance.amount_cents, "expense")
          lines << credit(account_for_treasury(advance.treasury), advance.amount_cents, "asset")
        end
      end

      # ── Payroll Salary (final payout) ─────────────────────────────────
      def record_payroll_salary!(snapshot)
        return unless snapshot.treasury.present? && snapshot.remaining_pay_cents.positive?

        destroy_for_source!(snapshot)
        create! source: snapshot, date: snapshot.payroll_month.end_of_month, user: snapshot.finalized_by,
                description: I18n.t("accounting.journal_entries.auto.payroll_salary",
                                    employee: snapshot.user.name,
                                    month: I18n.l(snapshot.payroll_month, format: "%B %Y"),
                                    default: "Payroll Salary — #{snapshot.user.name}") do |lines|
          lines << debit({ code: SALARY_CODE,
                           name: I18n.t("accounting.journal_entries.accounts.salaries", default: "Payroll — Salaries") },
                         snapshot.remaining_pay_cents, "expense")
          lines << credit(account_for_treasury(snapshot.treasury), snapshot.remaining_pay_cents, "asset")
        end
      end

      # ── Staff Meal ────────────────────────────────────────────────────
      def record_staff_meal!(order:, treasury:, user:)
        create! source: order, date: Date.current, user: user,
                description: I18n.t("accounting.journal_entries.auto.staff_meal",
                                    default: "Staff Meal Deduction") do |lines|
          lines << debit({ code: STAFF_MEAL_CODE,
                           name: I18n.t("accounting.journal_entries.accounts.staff_meals", default: "Staff Meals") },
                         order.total_cents, "expense")
          lines << credit(account_for_treasury(treasury), order.total_cents, "asset")
        end
      end

      # ── Vendor Invoice Received (AP created) ──────────────────────────
      def record_vendor_invoice!(invoice)
        destroy_for_source!(invoice)
        ap_treasury = invoice.supplier.ap_treasury
        return unless ap_treasury.present?

        create! source: invoice, date: invoice.received_on, user: invoice.user,
                description: I18n.t("accounting.journal_entries.auto.vendor_invoice",
                                    supplier: invoice.supplier.name,
                                    ref: invoice.invoice_number.presence || invoice.id,
                                    default: "Purchase Invoice — #{invoice.supplier.name}") do |lines|
          lines << debit({ code: 5100,
                           name: I18n.t("accounting.journal_entries.accounts.purchases", default: "Purchases / Inventory") },
                         invoice.total_cents, "expense")
          lines << credit(account_for_treasury(ap_treasury), invoice.total_cents, "liability")
        end
      end

      # ── Vendor Invoice Payment (AP settled) ───────────────────────────
      def record_vendor_invoice_payment!(payment)
        destroy_for_source!(payment)
        ap_treasury = payment.vendor_invoice.supplier.ap_treasury
        return unless ap_treasury.present?

        create! source: payment, date: payment.payment_date, user: payment.user,
                description: I18n.t("accounting.journal_entries.auto.vendor_invoice_payment",
                                    supplier: payment.vendor_invoice.supplier.name,
                                    default: "Supplier Payment — #{payment.vendor_invoice.supplier.name}") do |lines|
          lines << debit(account_for_treasury(ap_treasury), payment.amount_cents, "liability")
          lines << credit(account_for_treasury(payment.treasury), payment.amount_cents, "asset")
        end
      end

      # ── Partner Advance / Drawing ─────────────────────────────────────
      def record_partner_advance!(partner:, treasury:, amount_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          lines << debit(account_for_partner(partner), amount_cents, "equity")
          lines << credit(account_for_treasury(treasury), amount_cents, "asset")
        end
      end

      # ── Profit Distribution ───────────────────────────────────────────
      # Creates one JE with DR Retained Earnings and one CR line per partner
      def distribute_profit!(partners:, total_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          partners.each do |partner|
            share = (total_cents * partner.ownership_percentage / 100.0).round
            next if share == 0

            lines << credit(account_for_partner(partner), share, "equity",
                            notes: "#{partner.ownership_percentage}%")
          end
          # Single debit to retained earnings for the full amount
          lines << debit({ code: EQUITY_CODE, name: I18n.t("accounting.chart_of_accounts.retained_earnings") },
                         total_cents, "equity")
        end
      end

      # ── Loan Disbursement (money received from lender) ────────────────
      # DR Treasury → CR Loan account
      def record_loan_disbursement!(loan:, treasury:, amount_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          lines << debit(account_for_treasury(treasury), amount_cents, "asset")
          lines << credit(account_for_loan(loan), amount_cents, "liability")
        end
      end

      # ── Loan Repayment (paying back principal) ────────────────────────
      # DR Loan account → CR Treasury
      def record_loan_repayment!(loan:, treasury:, amount_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          lines << debit(account_for_loan(loan), amount_cents, "liability")
          lines << credit(account_for_treasury(treasury), amount_cents, "asset")
        end
      end

      # ── Loan Interest Payment (expense, no change to loan balance) ────
      # DR Interest Expense → CR Treasury
      def record_loan_interest!(loan:, treasury:, amount_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          lines << debit(
            { code: INTEREST_CODE, name: I18n.t("accounting.loans.interest_expense_account") },
            amount_cents, "expense"
          )
          lines << credit(account_for_treasury(treasury), amount_cents, "asset")
        end
      end

      # ── Generic Reversal ──────────────────────────────────────────────
      # Creates a mirror-image JE that cancels the effect of original_je.
      # All debit/credit amounts are swapped. Gets a new sequential entry number
      # so the audit sequence has no gaps.
      def record_reversal!(original_je:, user:, date: nil)
        raise ArgumentError, "Cannot reverse a reversal entry" if original_je.reversal?
        raise ArgumentError, "Already reversed" if original_je.reversed?

        JournalEntry.create!(
          company:            Current.company,
          created_by:         user,
          entry_number:       JournalEntry.next_entry_number(Current.company.id),
          date:               date || Date.current,
          description:        I18n.t("accounting.journal_entries.reversal_of",
                                     number:      original_je.entry_number,
                                     description: original_je.description),
          entry_type:         "reversal",
          reversal_of_id:     original_je.id,
          lines_attributes:   original_je.lines.map do |line|
            { account_code:  line.account_code,
              account_name:  line.account_name,
              account_type:  line.account_type,
              debit_cents:   line.credit_cents,
              credit_cents:  line.debit_cents,
              treasury_id:   line.treasury_id,
              notes:         line.notes }
          end
        )
      end

      # ── Vendor Invoice Voided (reversal) ──────────────────────────────
      def reverse_vendor_invoice!(invoice)
        destroy_for_source!(invoice)
      end

      # ── Remove all journal entries for a source (used on destroy/undo) ─
      def destroy_for_source!(source, kind: nil)
        return if source.nil?

        scope = JournalEntry.unscoped.where(
          source_record_type: source.class.name,
          source_record_id:   source.id,
          company_id:         Current.company.id
        )
        scope = scope.where("description LIKE ?", "%[#{kind}]%") if kind

        if scope.joins("INNER JOIN journal_entries reversals ON reversals.reversal_of_id = journal_entries.id").exists?
          raise ArgumentError, I18n.t("accounting.reversal.cannot_edit_reversed")
        end

        scope.destroy_all
      end

      private

      def create!(source:, date:, user:, description:, source_tag: nil)
        lines_data = []
        yield lines_data
        return if lines_data.empty?

        entry_description = source_tag ? "#{description} [#{source_tag}]" : description

        JournalEntry.create!(
          company:             Current.company,
          created_by:          user,
          entry_number:        JournalEntry.next_entry_number(Current.company.id),
          date:                date,
          description:         entry_description,
          entry_type:          "auto",
          source_record_type:  source&.class&.name,
          source_record_id:    source&.id,
          lines_attributes:    lines_data
        )
      end

      # Build a debit line hash
      def debit(account, amount_cents, account_type, notes: nil)
        { account_code: account[:code], account_name: account[:name],
          account_type: account_type, debit_cents: amount_cents, credit_cents: 0,
          treasury_id: account[:treasury_id], notes: notes }
      end

      # Build a credit line hash
      def credit(account, amount_cents, account_type, notes: nil)
        { account_code: account[:code], account_name: account[:name],
          account_type: account_type, debit_cents: 0, credit_cents: amount_cents,
          treasury_id: account[:treasury_id], notes: notes }
      end

      def account_for_treasury(treasury)
        base = TREASURY_TYPE_BASE.fetch(treasury.treasury_type, 1500)
        if treasury.treasury_type == "supplier_ap"
          siblings = Treasury.unscoped.where(company_id: treasury.company_id,
                                             treasury_type: "supplier_ap").order(:name)
        else
          siblings = Treasury.unscoped.where(company_id: treasury.company_id,
                                             treasury_type: treasury.treasury_type)
                             .order(:position, :name)
        end
        idx = siblings.pluck(:id).index(treasury.id).to_i
        { code: base + idx + 1, name: treasury.name, treasury_id: treasury.id }
      end

      def account_for_expense_category(category)
        # Assign deterministic codes 5001+ by category creation order
        base = 5000
        siblings = ExpenseCategory.unscoped.where(company_id: category.company_id).order(:id)
        idx = siblings.pluck(:id).index(category.id).to_i
        { code: base + idx + 1, name: category.name }
      end

      def account_for_income_category(category)
        base = 4000
        siblings = IncomeCategory.unscoped.where(company_id: category.company_id).order(:id)
        idx = siblings.pluck(:id).index(category.id).to_i
        { code: base + idx + 1, name: category.name }
      end

      def account_for_partner(partner)
        { code: partner.account_code, name: partner.account_name }
      end

      def account_for_loan(loan)
        { code: loan.account_code, name: loan.account_name }
      end
    end
  end
end
