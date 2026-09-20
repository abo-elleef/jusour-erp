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
    # Amounts still owed on machines bought on credit. A liability, deliberately
    # separate from trade payables (supplier AP) — equipment debt is not a goods debt.
    EQUIPMENT_PAYABLE_CODE = 2200
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
      "customer_ar"   => 1150,
      "supplier_ap"   => 2000
    }.freeze

    # SPIKE (AR): sales revenue account for credit sales. Distribution sales post
    # DR Accounts Receivable / CR Sales Revenue — the genuine revenue recognition
    # the POS/drawer flow never introduced.
    SALES_REVENUE_CODE = 4001
    TAX_PAYABLE_CODE   = 2100

    # Sales made but not yet sitting in a treasury. A day's takings are recognised
    # against this account, and each treasury clears its share as the money lands
    # (cash counted into the drawer, a wallet settled, a card payout received).
    # Whatever is left is cash over/short plus takings still in transit.
    #
    # Numbered like customer_ar (1150): carved into the 1100 block, because the
    # 1000-1599 range is handed out to treasuries as base + index and 1600+ belongs
    # to fixed assets.
    SALES_CLEARING_CODE = 1160

    # Money earned but not yet collected, and money owed but not yet paid —
    # where an income or an expense sits between the date it is booked and the
    # date a voucher settles it. Neither has a treasury behind it; both live
    # only in the ledger, like sales clearing above.
    #
    # 1170 sits in the gap between sales clearing (1160) and the safe treasuries
    # (1200+); 2300 above equipment payable (2200) and clear of the loan codes,
    # which count up from 2101.
    OTHER_RECEIVABLES_CODE = 1170
    ACCRUED_EXPENSES_CODE  = 2300

    # The accounts the app owns the names of, as opposed to the ones named by
    # the user — treasuries, expense categories, loans, partners.
    #
    # `account_name` on a journal line is a snapshot taken when the entry was
    # written, in whatever locale the person writing it happened to be using.
    # That is right for a treasury, whose name is data and should not shift
    # under the reader, and wrong for these, whose name is a translation: a
    # line posted from the English UI would otherwise read "Accrued expenses"
    # to an Arabic reader for ever. Rendering resolves these by code instead
    # (see LedgerAccountNames), so the stored name is only ever a fallback.
    SYSTEM_ACCOUNT_NAME_KEYS = {
      SALES_CLEARING_CODE    => "accounting.journal_entries.accounts.sales_clearing",
      OTHER_RECEIVABLES_CODE => "accounting.journal_entries.accounts.other_receivables",
      TAX_PAYABLE_CODE       => "accounting.journal_entries.accounts.tax_payable",
      EQUIPMENT_PAYABLE_CODE => "accounting.journal_entries.accounts.equipment_payable",
      ACCRUED_EXPENSES_CODE  => "accounting.journal_entries.accounts.accrued_expenses",
      EQUITY_CODE            => "accounting.chart_of_accounts.retained_earnings",
      SALES_REVENUE_CODE     => "accounting.journal_entries.accounts.sales_revenue",
      ADVANCE_CODE           => "accounting.journal_entries.accounts.payroll_advances",
      SALARY_CODE            => "accounting.journal_entries.accounts.salaries",
      STAFF_MEAL_CODE        => "accounting.journal_entries.accounts.staff_meals",
      COGS_CODE              => "accounting.journal_entries.accounts.purchases",
      INTEREST_CODE          => "accounting.loans.interest_expense_account"
    }.freeze

    class << self
      # The reader's name for an account, given the code and whatever name was
      # stored alongside it. System accounts resolve to the current locale;
      # everything else keeps the stored name, which is user data.
      def account_display_name(code, fallback = nil)
        key = SYSTEM_ACCOUNT_NAME_KEYS[code.to_i]
        return fallback.presence || code.to_s if key.nil?

        I18n.t(key, default: fallback.presence || code.to_s)
      end
      # ── Expense ──────────────────────────────────────────────────────
      #
      # The expense is the obligation, on the date it was incurred. It no longer
      # credits a treasury — a payment voucher does that, on the date the money
      # actually left — so what is credited here is the payable it creates. The
      # two net to nothing once the expense is settled, and whatever is left on
      # 2300 is what the company still owes.
      #
      # An expense paid on the spot raises its voucher in the same breath, so
      # both entries land together and 2300 clears immediately. The cost of that
      # is two journal entries where there was one; the gain is that cash is only
      # ever moved by a voucher, with no exceptions to reason about.
      def record_expense!(expense)
        # Daily COGS: auto-generated, no treasury, and deliberately not a ledger
        # fact — the app expenses stock when it is bought, so charging it again
        # when it is sold would count the same cost twice. A manual expense left
        # on account also has no treasury, and that one does belong here, which
        # is why this tests both.
        return if expense.is_auto_generated? && expense.treasury_id.blank?

        destroy_for_source!(expense)
        create! source: expense, date: expense.expense_date, user: expense.user,
                description: I18n.t("accounting.journal_entries.auto.expense",
                                    category: expense.expense_category.name,
                                    default: "Expense — #{expense.expense_category.name}") do |lines|
          lines << debit(account_for_expense_category(expense.expense_category),
                         expense.amount_cents, "expense")
          lines << credit(accrued_expenses_account, expense.amount_cents, "liability")
        end
      end

      # ── Income ───────────────────────────────────────────────────────
      #
      # Mirror of the expense above: the income is recognised on the date it was
      # earned and debits a receivable, not a treasury. A receipt voucher brings
      # the cash in later, on its own date, and clears 1170.
      def record_income!(income)
        destroy_for_source!(income)
        create! source: income, date: income.income_date, user: income.user,
                description: I18n.t("accounting.journal_entries.auto.income",
                                    category: income.income_category.name,
                                    default: "Income — #{income.income_category.name}") do |lines|
          lines << debit(other_receivables_account, income.amount_cents, "asset")
          lines << credit(account_for_income_category(income.income_category),
                          income.amount_cents, "revenue")
        end
      end

      # ── Voucher (سند قبض / سند صرف) ───────────────────────────────────
      #
      # The cash leg of an income or expense, carrying its own date. The other
      # side is the accrual account the income or expense already posted to, so
      # the pair nets to nothing once a booking is fully settled and whatever is
      # left on 1170/2300 is exactly what is still owed either way.
      #
      # The counter-account is chosen by direction because in this phase a
      # voucher settles only incomes and expenses. When vouchers absorb supplier
      # and customer payments it will have to be resolved per allocation, from
      # the AP or AR treasury of the invoice being settled.
      def record_voucher!(voucher)
        destroy_for_source!(voucher)

        create! source: voucher, date: voucher.voucher_date, user: voucher.user,
                description: I18n.t("accounting.journal_entries.auto.voucher",
                                    number: voucher.number,
                                    default: "Voucher #{voucher.number}") do |lines|
          treasury_line = account_for_treasury(voucher.treasury)

          if voucher.receipt?
            lines << debit(treasury_line, voucher.amount_cents, "asset")
            voucher_counter_legs(voucher).each { |acct, type, cents| lines << credit(acct, cents, type) }
          else
            voucher_counter_legs(voucher).each { |acct, type, cents| lines << debit(acct, cents, type) }
            lines << credit(treasury_line, voucher.amount_cents, "asset")
          end
        end
      end

      # What the far side of a voucher is, resolved per allocation rather than
      # per voucher. Settling an expense clears the accrued payable; settling a
      # supplier invoice clears that supplier's payable, which is a treasury of
      # its own. One voucher can do both, so the legs are grouped by account and
      # the whole set has to add up to the voucher.
      #
      # Whatever is not allocated is money moved on account, and falls to the
      # accrual account for the direction — which is what the voucher did for
      # every case before it could settle an invoice.
      def voucher_counter_legs(voucher)
        legs = Hash.new(0)

        voucher.payment_allocations.each do |allocation|
          key = counter_account_for(allocation.settles, voucher)
          legs[key] += allocation.amount_cents
        end

        remainder = voucher.amount_cents - voucher.payment_allocations.sum(&:amount_cents)
        legs[default_counter_for(voucher)] += remainder if remainder.positive?

        legs.map { |(acct, type), cents| [acct, type, cents] }
      end

      # A voucher settles a document — an invoice, an expense, an income — or a
      # party. Settling a party is money on account: a customer who pays more
      # than they owe is in credit with us, and that credit belongs on their own
      # receivable rather than in a pooled "other receivables" nobody can trace
      # back to them.
      def counter_account_for(settles, voucher)
        case settles
        when ::Expense         then [accrued_expenses_account, "liability"]
        when ::Income          then [other_receivables_account, "asset"]
        when ::VendorInvoice   then [account_for_treasury(settles.supplier.ap_treasury), "liability"]
        when ::CustomerInvoice then [account_for_treasury(settles.customer.ar_treasury), "asset"]
        when ::Customer        then [account_for_treasury(settles.ar_treasury), "asset"]
        when ::Supplier        then [account_for_treasury(settles.ap_treasury), "liability"]
        else default_counter_for(voucher)
        end
      end

      def default_counter_for(voucher)
        voucher.receipt? ? [other_receivables_account, "asset"] : [accrued_expenses_account, "liability"]
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
      # The float is carried into the drawer out of a safe: cash moves between two
      # treasuries and the company is no richer for it. (It used to be credited to
      # equity, which both invented income and left the float double-counted.)
      def record_drawer_open!(session)
        destroy_for_source!(session, kind: :open)
        return unless session.opening_float_cents.to_i.positive?
        return if session.float_source_treasury.blank?

        create! source: session, date: session.session_date, user: session.user,
                description: I18n.t("accounting.journal_entries.auto.drawer_open",
                                    treasury: session.treasury.name,
                                    default: "Cash Drawer Opened — #{session.treasury.name}"),
                source_tag: :open do |lines|
          lines << debit(account_for_treasury(session.treasury),
                         session.opening_float_cents, "asset")
          lines << credit(account_for_treasury(session.float_source_treasury),
                          session.opening_float_cents, "asset")
        end
      end

      # ── Drawer Reconcile ──────────────────────────────────────────────
      # Cash taken during the session lands in the drawer. Only the takings post —
      # the float was already debited to the drawer when it opened — and they clear
      # against sales clearing, where the day's revenue was recognised. Any gap
      # between the two is the cash over/short, and it stays visible in 1160.
      def record_drawer_reconcile!(session)
        destroy_for_source!(session, kind: :reconcile)
        collected = session.cash_collected_cents
        return unless collected.positive?

        create! source: session, date: Date.current, user: session.user,
                description: I18n.t("accounting.journal_entries.auto.drawer_reconcile",
                                    treasury: session.treasury.name,
                                    default: "Cash Drawer Reconciled — #{session.treasury.name}"),
                source_tag: :reconcile do |lines|
          lines << debit(account_for_treasury(session.treasury), collected, "asset")
          lines << credit(sales_clearing_account, collected, "asset")
        end
      end

      # ── Drawer Deposit ────────────────────────────────────────────────
      # Handing the counted cash over to a safe. Both sides are assets, so the
      # company is no richer for it — the money has only changed hands.
      def record_drawer_deposit!(session)
        destroy_for_source!(session, kind: :deposit)
        amount = session.deposit_cents
        return unless amount.positive?
        return if session.deposit_treasury.blank?

        create! source: session, date: Date.current, user: session.user,
                description: I18n.t("accounting.journal_entries.auto.drawer_deposit",
                                    from: session.treasury.name,
                                    to: session.deposit_treasury.name,
                                    default: "Drawer banked — #{session.treasury.name} → #{session.deposit_treasury.name}"),
                source_tag: :deposit do |lines|
          lines << debit(account_for_treasury(session.deposit_treasury), amount, "asset")
          lines << credit(account_for_treasury(session.treasury), amount, "asset")
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
          lines << credit(sales_clearing_account, amount_cents, "asset")
        end
      end

      # ── Daily POS Sales ───────────────────────────────────────────────
      # One entry per location per business day recognising the day's takings:
      #
      #   DR Sales clearing (1160)   everything sold
      #     CR Sales revenue (4001)  net of tax
      #     CR Tax payable   (2100)  tax collected
      #
      # Posted per day rather than per ticket: at a few hundred orders a day the
      # ledger has to stay readable, and the per-order detail already lives in the
      # orders tables where the sales reports read it. Each treasury clears its own
      # share of 1160 as the money arrives, so card takings finally reach the books
      # even though no drawer session ever sees them.
      #
      # Idempotent: re-running for the same day replaces the day's entry.
      def record_daily_sales!(location:, business_date:, user:, orders: nil)
        orders ||= Order.completed.where(created_at: BusinessDay.range(business_date, location: location),
                                         location_id: location.id)
        destroy_for_daily_sales!(location: location, business_date: business_date)

        net_sales_cents = orders.sum(:subtotal_cents).to_i - orders.sum(:discount_cents).to_i
        tax_cents       = orders.sum(:tax_cents).to_i
        tip_cents       = orders.sum(:tip_cents).to_i
        total_cents     = net_sales_cents + tax_cents + tip_cents
        return if total_cents.zero?

        create! source: location, date: business_date, user: user,
                description: I18n.t("accounting.journal_entries.auto.daily_sales",
                                    location: location.name, date: business_date,
                                    default: "Sales — #{location.name} #{business_date}"),
                source_tag: :daily_sales do |lines|
          lines << debit(sales_clearing_account, total_cents, "asset")
          lines << credit({ code: SALES_REVENUE_CODE,
                            name: I18n.t("accounting.journal_entries.accounts.sales_revenue", default: "Sales revenue") },
                          net_sales_cents + tip_cents, "revenue")
          if tax_cents.positive?
            lines << credit({ code: TAX_PAYABLE_CODE,
                              name: I18n.t("accounting.journal_entries.accounts.tax_payable", default: "Tax payable") },
                            tax_cents, "liability")
          end
        end
      end

      # ── Cash sale (paid on issue) ─────────────────────────────────────
      # A counter sale settled on the spot never passes through Accounts
      # Receivable — the money is in the till the moment the sale is made:
      #
      #   DR <treasury>            what was taken
      #     CR Sales revenue (4001)
      #
      # Routing it through AR instead would raise a receivable and clear it in the
      # same breath, leaving the customer's statement full of debts they never owed.
      def record_customer_cash_sale!(source:, treasury:, date:, user:, amount_cents:)
        destroy_for_source!(source)
        return unless amount_cents.positive?

        create! source: source, date: date, user: user,
                description: I18n.t("accounting.journal_entries.auto.cash_sale",
                                    number: source.try(:invoice_number),
                                    default: "Cash sale — #{source.try(:invoice_number)}") do |lines|
          lines << debit(account_for_treasury(treasury), amount_cents, "asset")
          lines << credit({ code: SALES_REVENUE_CODE,
                            name: I18n.t("accounting.journal_entries.accounts.sales_revenue", default: "Sales revenue") },
                          amount_cents, "revenue")
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
          # The whole invoice is goods. Delivery paid at receive leaves through its
          # own Expense and never reaches AP, so nothing splits off here. Derived
          # from total_cents (rather than recomputed from lines) so the entry always
          # balances against the stored total.
          if invoice.total_cents.positive?
            lines << debit({ code: 5100,
                             name: I18n.t("accounting.journal_entries.accounts.purchases", default: "Purchases / Inventory") },
                           invoice.total_cents, "expense")
          end
          lines << credit(account_for_treasury(ap_treasury), invoice.total_cents, "liability")
        end
      end

      # ── Vendor Credit Note (purchase return / AP reduced) ────────────
      # DR AP treasury (liability reduced)
      # CR Purchases 5100 (expense reversed)
      def record_vendor_credit_note!(credit_note)
        destroy_for_source!(credit_note)
        ap_treasury = credit_note.supplier.ap_treasury
        return unless ap_treasury.present?

        create! source: credit_note, date: credit_note.credit_note_date, user: credit_note.user,
                description: I18n.t("accounting.journal_entries.auto.vendor_credit_note",
                                    supplier: credit_note.supplier.name,
                                    ref: credit_note.credit_note_number,
                                    default: "Purchase Return — #{credit_note.supplier.name}") do |lines|
          lines << debit(account_for_treasury(ap_treasury), credit_note.total_cents, "liability")
          lines << credit({ code: 5100,
                            name: I18n.t("accounting.journal_entries.accounts.purchases", default: "Purchases / Inventory") },
                          credit_note.total_cents, "expense")
        end
      end

      # ── Fixed asset acquisition ───────────────────────────────────────
      #
      # A capital purchase, not an expense: the asset account is debited and either
      # cash or an equipment payable is credited. Nothing reaches the P&L here —
      # the cost arrives later as depreciation.
      def record_fixed_asset_purchase!(asset)
        destroy_for_source!(asset)

        create! source: asset, date: asset.purchase_date, user: asset.recorded_by,
                description: I18n.t("accounting.journal_entries.auto.fixed_asset_purchase",
                                    name: asset.name,
                                    default: "Fixed asset — #{asset.name}") do |lines|
          lines << debit(account_for_fixed_asset(asset), asset.purchase_price_cents, "asset")
          lines << if asset.on_credit?
                     credit(equipment_payable_account, asset.purchase_price_cents, "liability")
                   else
                     credit(account_for_treasury(asset.paid_from_treasury), asset.purchase_price_cents, "asset")
                   end
        end
      end

      # ── Fixed asset installment ───────────────────────────────────────
      def record_fixed_asset_payment!(payment)
        destroy_for_source!(payment)

        create! source: payment, date: payment.payment_date, user: payment.user,
                description: I18n.t("accounting.journal_entries.auto.fixed_asset_payment",
                                    name: payment.fixed_asset.name,
                                    default: "Fixed asset payment — #{payment.fixed_asset.name}") do |lines|
          lines << debit(equipment_payable_account, payment.amount_cents, "liability")
          lines << credit(account_for_treasury(payment.treasury), payment.amount_cents, "asset")
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

      # ── Customer credit sale (AR raised) ──────────────────────────────
      # SPIKE: mirror of record_vendor_invoice!, on the customer side.
      #   DR Accounts Receivable (customer AR treasury, asset)
      #   CR Sales Revenue (4001)   [+ CR Tax Payable if tax is charged]
      def record_customer_charge!(source:, customer:, date:, user:, amount_cents:, revenue_cents: nil, tax_cents: 0)
        ar_treasury = customer.ar_treasury
        return unless ar_treasury.present?

        revenue_cents ||= amount_cents - tax_cents
        create! source: source, date: date, user: user,
                description: I18n.t("accounting.journal_entries.auto.customer_charge",
                                    customer: customer.display_name,
                                    default: "Credit sale — #{customer.display_name}") do |lines|
          lines << debit(account_for_treasury(ar_treasury), amount_cents, "asset")
          lines << credit({ code: SALES_REVENUE_CODE,
                            name: I18n.t("accounting.journal_entries.accounts.sales_revenue", default: "Sales revenue") },
                          revenue_cents, "revenue")
          if tax_cents.positive?
            lines << credit({ code: 2100, name: I18n.t("accounting.journal_entries.accounts.tax_payable", default: "Tax payable") },
                            tax_cents, "liability")
          end
        end
      end

      # ── Customer credit note / sales return ───────────────────────────
      # Reverses the AR raised by a sale (a return or allowance). Mirror-image of
      # record_customer_charge!:  DR Sales Revenue (4001)   CR Accounts Receivable
      def record_customer_credit_note!(source:, customer:, date:, user:, amount_cents:, revenue_cents: nil, tax_cents: 0)
        ar_treasury = customer.ar_treasury
        return unless ar_treasury.present?

        revenue_cents ||= amount_cents - tax_cents
        create! source: source, date: date, user: user,
                description: I18n.t("accounting.journal_entries.auto.customer_credit_note",
                                    customer: customer.display_name,
                                    default: "Credit note — #{customer.display_name}") do |lines|
          lines << debit({ code: SALES_REVENUE_CODE,
                           name: I18n.t("accounting.journal_entries.accounts.sales_revenue", default: "Sales revenue") },
                         revenue_cents, "revenue")
          if tax_cents.positive?
            lines << debit({ code: 2100, name: I18n.t("accounting.journal_entries.accounts.tax_payable", default: "Tax payable") },
                           tax_cents, "liability")
          end
          lines << credit(account_for_treasury(ar_treasury), amount_cents, "asset")
        end
      end

      # ── Customer opening AR balance (migration) ───────────────────────
      # A balance the customer already owed us in the previous system. Not new
      # revenue — it was recognized before — so it credits Equity, not Revenue.
      #   DR Accounts Receivable (asset)   CR Retained Earnings / Equity
      def record_customer_opening_balance!(source:, customer:, date:, user:, amount_cents:)
        ar_treasury = customer.ar_treasury
        return unless ar_treasury.present?

        create! source: source, date: date, user: user,
                description: I18n.t("accounting.journal_entries.auto.customer_opening_balance",
                                    customer: customer.display_name,
                                    default: "Opening balance — #{customer.display_name}") do |lines|
          lines << debit(account_for_treasury(ar_treasury), amount_cents, "asset")
          lines << credit({ code: EQUITY_CODE, name: I18n.t("accounting.chart_of_accounts.retained_earnings", default: "Retained Earnings") },
                          amount_cents, "equity")
        end
      end

      # ── Customer payment (AR settled) ─────────────────────────────────
      # SPIKE: mirror of record_vendor_invoice_payment!.
      #   DR paying treasury (cash/bank, asset)   CR Accounts Receivable (asset)
      def record_customer_receipt!(source:, customer:, treasury:, date:, user:, amount_cents:)
        ar_treasury = customer.ar_treasury
        return unless ar_treasury.present?

        create! source: source, date: date, user: user,
                description: I18n.t("accounting.journal_entries.auto.customer_receipt",
                                    customer: customer.display_name,
                                    default: "Customer payment — #{customer.display_name}") do |lines|
          lines << debit(account_for_treasury(treasury), amount_cents, "asset")
          lines << credit(account_for_treasury(ar_treasury), amount_cents, "asset")
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

      # ── Vendor Invoice Voided ─────────────────────────────────────────
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
        scope = scope.where("journal_entries.description LIKE ?", "%[#{kind}]%") if kind

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

      # A day's entry is keyed by location *and* date, so the generic source cleanup
      # (which would wipe every day for the location) is too broad here.
      def destroy_for_daily_sales!(location:, business_date:)
        JournalEntry.unscoped.where(
          source_record_type: "Location", source_record_id: location.id,
          company_id: Current.company.id, date: business_date
        ).where("journal_entries.description LIKE ?", "%[daily_sales]%").destroy_all
      end

      def sales_clearing_account
        { code: SALES_CLEARING_CODE,
          name: I18n.t("accounting.journal_entries.accounts.sales_clearing", default: "Sales clearing") }
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

      # Mirrors ChartOfAccountsService's asset-account numbering so the entry lands in
      # the same account the balance sheet shows for this asset class.
      def account_for_fixed_asset(asset)
        base = ChartOfAccountsService::FIXED_ASSET_BASE_CODES.fetch(asset.asset_type, 1980)
        { code: base, name: I18n.t("accounting.fixed_assets.asset_types.#{asset.asset_type}",
                                   default: asset.asset_type.to_s.humanize) }
      end

      def accrued_expenses_account
        { code: ACCRUED_EXPENSES_CODE,
          name: I18n.t("accounting.journal_entries.accounts.accrued_expenses",
                       default: "Accrued expenses") }
      end

      def other_receivables_account
        { code: OTHER_RECEIVABLES_CODE,
          name: I18n.t("accounting.journal_entries.accounts.other_receivables",
                       default: "Other receivables") }
      end

      def equipment_payable_account
        { code: EQUIPMENT_PAYABLE_CODE,
          name: I18n.t("accounting.journal_entries.accounts.equipment_payable",
                       default: "Equipment payable") }
      end

      def account_for_expense_category(category)
        { code: category.account_code, name: category.name }
      end

      def account_for_income_category(category)
        { code: category.account_code, name: category.name }
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
