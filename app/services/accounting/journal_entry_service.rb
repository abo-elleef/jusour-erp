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
  #     5600       Interest Expense
  #     5700       Delivery Fee Expense
  class JournalEntryService
    # Kept as aliases of SystemAccount's codes rather than removed: three other
    # files (AccountListService, ChartOfAccountsService, JournalEntriesController)
    # still reference these constants directly and haven't been moved onto
    # Accountable yet. Defining them from SystemAccount means the two can never
    # drift apart while that migration is still in progress.
    EQUITY_CODE      = SystemAccount::EQUITY.code
    ADVANCE_CODE     = SystemAccount::PAYROLL_ADVANCES.code
    # Amounts still owed on machines bought on credit. A liability, deliberately
    # separate from trade payables (supplier AP) — equipment debt is not a goods debt.
    EQUIPMENT_PAYABLE_CODE = SystemAccount::EQUIPMENT_PAYABLE.code
    SALARY_CODE      = SystemAccount::SALARIES.code
    STAFF_MEAL_CODE  = SystemAccount::STAFF_MEALS.code
    COGS_CODE        = SystemAccount::COGS.code
    INTEREST_CODE    = SystemAccount::INTEREST_EXPENSE.code

    # SPIKE (AR): sales revenue account for credit sales. Distribution sales post
    # DR Accounts Receivable / CR Sales Revenue — the genuine revenue recognition
    # the POS/drawer flow never introduced.
    SALES_REVENUE_CODE = SystemAccount::SALES_REVENUE.code
    TAX_PAYABLE_CODE   = SystemAccount::TAX_PAYABLE.code

    # Sales made but not yet sitting in a treasury. A day's takings are recognised
    # against this account, and each treasury clears its share as the money lands
    # (cash counted into the drawer, a wallet settled, a card payout received).
    # Whatever is left is cash over/short plus takings still in transit.
    #
    # Numbered like customer_ar (1150): carved into the 1100 block, because the
    # 1000-1599 range is handed out to treasuries as base + index and 1600+ belongs
    # to fixed assets.
    SALES_CLEARING_CODE = SystemAccount::SALES_CLEARING.code

    # Money earned but not yet collected, and money owed but not yet paid —
    # where an income or an expense sits between the date it is booked and the
    # date a voucher settles it. Neither has a treasury behind it; both live
    # only in the ledger, like sales clearing above.
    #
    # 1170 sits in the gap between sales clearing (1160) and the safe treasuries
    # (1200+); 2300 above equipment payable (2200) and clear of the loan codes,
    # which count up from 2101.
    OTHER_RECEIVABLES_CODE = SystemAccount::OTHER_RECEIVABLES.code
    ACCRUED_EXPENSES_CODE  = SystemAccount::ACCRUED_EXPENSES.code

    class << self
      # The reader's name for an account, given the code and whatever name was
      # stored alongside it. System accounts resolve to the current locale;
      # everything else keeps the stored name, which is user data.
      def account_display_name(code, fallback = nil)
        key = SystemAccount::REGISTRY[code.to_i]&.name_key
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
          lines << debit(expense.expense_category, expense.amount_cents)
          lines << credit(accrual_account_for(expense, SystemAccount::ACCRUED_EXPENSES), expense.amount_cents)
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
          lines << debit(accrual_account_for(income, SystemAccount::OTHER_RECEIVABLES), income.amount_cents)
          lines << credit(income.income_category, income.amount_cents)
        end
      end

      # ── Voucher (سند قبض / سند صرف) ───────────────────────────────────
      #
      # The cash leg of an income or expense, carrying its own date. The other
      # side is the accrual account the income or expense already posted to, so
      # the pair nets to nothing once a booking is fully settled and whatever is
      # left on 1170/2300 is exactly what is still owed either way.
      def record_voucher!(voucher)
        destroy_for_source!(voucher)

        create! source: voucher, date: voucher.voucher_date, user: voucher.user,
                description: I18n.t("accounting.journal_entries.auto.voucher",
                                    number: voucher.number,
                                    default: "Voucher #{voucher.number}") do |lines|
          if voucher.receipt?
            lines << debit(voucher.treasury, voucher.amount_cents)
            voucher_counter_legs(voucher).each { |account, cents| lines << credit(account, cents) }
          else
            voucher_counter_legs(voucher).each { |account, cents| lines << debit(account, cents) }
            lines << credit(voucher.treasury, voucher.amount_cents)
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
      #
      # Grouped by AccountRef rather than by the settled record itself: two
      # allocations can resolve to the same account through different model
      # types (a VendorInvoice and a direct on-account Supplier settlement both
      # land on that supplier's AP treasury), and AccountRef is a Struct, so two
      # structurally-equal refs group under one key regardless of which path
      # produced them.
      def voucher_counter_legs(voucher)
        legs = Hash.new(0)

        voucher.payment_allocations.each do |allocation|
          legs[counter_account_for(allocation.settles, voucher)] += allocation.amount_cents
        end

        remainder = voucher.amount_cents - voucher.payment_allocations.sum(&:amount_cents)
        legs[default_counter_for(voucher)] += remainder if remainder.positive?

        legs.to_a
      end

      # A voucher settles a document — an invoice, an expense, an income — or a
      # party. Settling a party is money on account: a customer who pays more
      # than they owe is in credit with us, and that credit belongs on their own
      # receivable rather than in a pooled "other receivables" nobody can trace
      # back to them.
      def counter_account_for(settles, voucher)
        case settles
        when ::Expense               then accrual_account_for(settles, SystemAccount::ACCRUED_EXPENSES)
        when ::Income                 then accrual_account_for(settles, SystemAccount::OTHER_RECEIVABLES)
        when ::VendorInvoice          then settles.supplier.to_account
        when ::CustomerInvoice        then settles.customer.to_account
        when ::Customer, ::Supplier   then settles.to_account
        # Legacy: only until payroll:convert_to_staff_accounts has run.
        when ::PayrollAdvance         then settles.user.to_account
        else default_counter_for(voucher)
        end
      end

      # What an unallocated (or wholly unsettled) voucher clears against. An
      # equity adjustment is never "with" anyone in the AP/AR sense — cash
      # appearing or leaving with no counterparty document — so its own party,
      # if it has one, is a label only and never redirects this leg. Everything
      # else is the same accrual resolution as an Expense or Income: the
      # voucher's own party's account when it has one, the pooled account
      # otherwise. This is what makes "receipt on account, from this customer,
      # settling nothing yet" land on that customer's AR instead of a pooled
      # figure nobody can trace back to them.
      def default_counter_for(voucher)
        return SystemAccount::EQUITY.to_account if voucher.equity_adjustment?

        pooled = voucher.receipt? ? SystemAccount::OTHER_RECEIVABLES : SystemAccount::ACCRUED_EXPENSES
        accrual_account_for(voucher, pooled)
      end

      # The account a party-bearing record actually clears against: whatever
      # its own party represents, if it has one that's Accountable — a
      # Supplier's AP, a Customer's AR, a Partner's or Loan's own account —
      # otherwise the pooled account, same as before a party ever existed.
      # Used for Expense, Income, and a Voucher's own unallocated remainder.
      # `party` can be a User (Partyable allows it; Accountable deliberately
      # doesn't — see project_unify_account_and_party), so this checks rather
      # than assumes every party answers #to_account.
      def accrual_account_for(record, pooled)
        party = record.party
        return pooled.to_account unless party.respond_to?(:to_account)

        party.to_account || pooled.to_account
      end

      # ── Treasury Transfer ─────────────────────────────────────────────
      def record_transfer!(transfer)
        destroy_for_source!(transfer)
        create! source: transfer, date: Date.current, user: transfer.user,
                description: I18n.t("accounting.journal_entries.auto.transfer",
                                    from: transfer.from_treasury.name,
                                    to: transfer.to_treasury.name,
                                    default: "Transfer: #{transfer.from_treasury.name} → #{transfer.to_treasury.name}") do |lines|
          lines << debit(transfer.to_treasury, transfer.amount_cents)
          lines << credit(transfer.from_treasury, transfer.amount_cents)
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
          lines << debit(session.treasury, session.opening_float_cents)
          lines << credit(session.float_source_treasury, session.opening_float_cents)
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
          lines << debit(session.treasury, collected)
          lines << credit(SystemAccount::SALES_CLEARING, collected)
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
          lines << debit(session.deposit_treasury, amount)
          lines << credit(session.treasury, amount)
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
          lines << debit(treasury, amount_cents)
          lines << credit(SystemAccount::SALES_CLEARING, amount_cents)
        end
      end

      # ── Daily POS Sales ───────────────────────────────────────────────
      # One entry per location per business day recognising the day's takings:
      #
      #   DR Sales clearing (1160)   everything sold
      #     CR Sales revenue (4001)  net of tax, with tips and delivery fees
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
        delivery_cents  = orders.sum(:delivery_fee_cents).to_i
        total_cents     = net_sales_cents + tax_cents + tip_cents + delivery_cents
        return if total_cents.zero?

        create! source: location, date: business_date, user: user,
                description: I18n.t("accounting.journal_entries.auto.daily_sales",
                                    location: location.name, date: business_date,
                                    default: "Sales — #{location.name} #{business_date}"),
                source_tag: :daily_sales do |lines|
          lines << debit(SystemAccount::SALES_CLEARING, total_cents)
          lines << credit(SystemAccount::SALES_REVENUE, net_sales_cents + tip_cents + delivery_cents)
          lines << credit(SystemAccount::TAX_PAYABLE, tax_cents) if tax_cents.positive?
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
          lines << debit(treasury, amount_cents)
          lines << credit(SystemAccount::SALES_REVENUE, amount_cents)
        end
      end

      # ── Payroll accrual (month finalized) ─────────────────────────────
      # The month's earnings become an expense and a debt to the employee in
      # one step. Paying it out is a voucher, like any other money to them —
      # see FinalizePayrollService.
      def record_payroll_accrual!(snapshot)
        destroy_for_source!(snapshot)
        return unless snapshot.net_pay_cents.positive?

        create! source: snapshot, date: snapshot.payroll_month.end_of_month, user: snapshot.finalized_by,
                description: I18n.t("accounting.journal_entries.auto.payroll_accrual",
                                    employee: snapshot.user.name,
                                    month: I18n.l(snapshot.payroll_month, format: "%B %Y"),
                                    default: "Payroll earned — #{snapshot.user.name}") do |lines|
          lines << debit(SystemAccount::SALARIES, snapshot.net_pay_cents)
          lines << credit(snapshot.user, snapshot.net_pay_cents)
        end
      end

      # ── Staff Meal ────────────────────────────────────────────────────
      def record_staff_meal!(order:, treasury:, user:)
        create! source: order, date: Date.current, user: user,
                description: I18n.t("accounting.journal_entries.auto.staff_meal",
                                    default: "Staff Meal Deduction") do |lines|
          lines << debit(order.staff_meal_user, order.total_cents)
          lines << credit(treasury, order.total_cents)
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
          lines << debit(SystemAccount::PURCHASES, invoice.total_cents) if invoice.total_cents.positive?
          lines << credit(ap_treasury, invoice.total_cents)
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
          lines << debit(ap_treasury, credit_note.total_cents)
          lines << credit(SystemAccount::PURCHASES, credit_note.total_cents)
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
          lines << debit(account_for_fixed_asset(asset), asset.purchase_price_cents)
          lines << if asset.on_credit?
                     credit(SystemAccount::EQUIPMENT_PAYABLE, asset.purchase_price_cents)
                   else
                     credit(asset.paid_from_treasury, asset.purchase_price_cents)
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
          lines << debit(SystemAccount::EQUIPMENT_PAYABLE, payment.amount_cents)
          lines << credit(payment.treasury, payment.amount_cents)
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
          lines << debit(ap_treasury, payment.amount_cents)
          lines << credit(payment.treasury, payment.amount_cents)
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
          lines << debit(ar_treasury, amount_cents)
          lines << credit(SystemAccount::SALES_REVENUE, revenue_cents)
          lines << credit(SystemAccount::TAX_PAYABLE, tax_cents) if tax_cents.positive?
        end
      end

      # ── Shipping company charge (COD dispatch) ────────────────────────
      # A COD shipment leaves with nobody holding our cash yet — the shipping
      # company now owes it to us. Same shape as record_customer_charge!, just
      # the debtor is the courier instead of the end customer:
      #   DR shipping company's ledger treasury (asset)
      #   CR Sales Revenue (4001)
      def record_shipping_company_charge!(source:, shipping_company:, date:, user:, amount_cents:)
        ar_treasury = shipping_company.ar_treasury
        return unless ar_treasury.present?

        create! source: source, date: date, user: user,
                description: I18n.t("accounting.journal_entries.auto.shipping_company_charge",
                                    name: shipping_company.name,
                                    default: "COD dispatch — #{shipping_company.name}") do |lines|
          lines << debit(ar_treasury, amount_cents)
          lines << credit(SystemAccount::SALES_REVENUE, amount_cents)
        end
      end

      # ── Shipping company delivery-fee payable (dispatch) ──────────────
      # What Bazzar owes the courier for their standard delivery-fee cut —
      # posted at dispatch for every delivery invoice, regardless of payment
      # method or whether a promo waived the fee for the customer (see
      # Accounting::ShippingCompanyLedgerService#accrue_delivery_fee! and the
      # delivery-fee design doc for why this is unconditional):
      #   DR Delivery Fee Expense (5700)
      #   CR shipping company's ledger treasury (asset)
      def record_shipping_company_fee_payable!(source:, shipping_company:, date:, user:, amount_cents:)
        ar_treasury = shipping_company.ar_treasury
        return unless ar_treasury.present?

        create! source: source, date: date, user: user,
                description: I18n.t("accounting.journal_entries.auto.shipping_company_fee_payable",
                                    name: shipping_company.name,
                                    default: "Delivery fee payable — #{shipping_company.name}") do |lines|
          lines << debit(SystemAccount::DELIVERY_FEE_EXPENSE, amount_cents)
          lines << credit(ar_treasury, amount_cents)
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
          lines << debit(SystemAccount::SALES_REVENUE, revenue_cents)
          lines << debit(SystemAccount::TAX_PAYABLE, tax_cents) if tax_cents.positive?
          lines << credit(ar_treasury, amount_cents)
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
          lines << debit(ar_treasury, amount_cents)
          lines << credit(SystemAccount::EQUITY, amount_cents)
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
          lines << debit(treasury, amount_cents)
          lines << credit(ar_treasury, amount_cents)
        end
      end

      # ── Partner Advance / Drawing ─────────────────────────────────────
      def record_partner_advance!(partner:, treasury:, amount_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          lines << debit(partner, amount_cents)
          lines << credit(treasury, amount_cents)
        end
      end

      # ── Profit Distribution ───────────────────────────────────────────
      # Creates one JE with DR Retained Earnings and one CR line per partner
      def distribute_profit!(partners:, total_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          partners.each do |partner|
            share = (total_cents * partner.ownership_percentage / 100.0).round
            next if share == 0

            lines << credit(partner, share, notes: "#{partner.ownership_percentage}%")
          end
          # Single debit to retained earnings for the full amount
          lines << debit(SystemAccount::EQUITY, total_cents)
        end
      end

      # ── Loan Disbursement (money received from lender) ────────────────
      # DR Treasury → CR Loan account
      def record_loan_disbursement!(loan:, treasury:, amount_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          lines << debit(treasury, amount_cents)
          lines << credit(loan, amount_cents)
        end
      end

      # ── Loan Opening Balance (a debt that already existed, no cash moving) ──
      # For a loan whose cash was received long before it was ever put in the
      # books — the money is already sitting in the treasury's current balance,
      # so a disbursement here would count it a second time. Mirrors
      # record_customer_opening_balance!, on the liability side: the loan is
      # raised against Retained Earnings instead of an asset or a treasury,
      # since nothing new was received today and the balance sheet still has
      # to hold (assets unchanged ⇒ equity absorbs the newly-recognized debt).
      def record_loan_opening_balance!(loan:, amount_cents:, date:, user:, description: nil)
        create! source: nil, date: date, user: user,
                description: description.presence || I18n.t("accounting.journal_entries.auto.loan_opening_balance",
                                                             name: loan.name,
                                                             default: "Opening balance — #{loan.name}") do |lines|
          lines << debit(SystemAccount::EQUITY, amount_cents)
          lines << credit(loan, amount_cents)
        end
      end

      # ── Loan Repayment (paying back principal) ────────────────────────
      # DR Loan account → CR Treasury
      def record_loan_repayment!(loan:, treasury:, amount_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          lines << debit(loan, amount_cents)
          lines << credit(treasury, amount_cents)
        end
      end

      # ── Loan Interest Payment (expense, no change to loan balance) ────
      # DR Interest Expense → CR Treasury
      def record_loan_interest!(loan:, treasury:, amount_cents:, date:, description:, user:)
        create! source: nil, date: date, user: user, description: description do |lines|
          lines << debit(SystemAccount::INTEREST_EXPENSE, amount_cents)
          lines << credit(treasury, amount_cents)
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

      # Build a debit line hash. `account` is anything Accountable (a model
      # instance, a SystemAccount, or an already-resolved AccountRef) — it says
      # its own code/name/type, so no call site hand-types "asset"/"liability"
      # next to it and risks the two not matching.
      def debit(account, amount_cents, notes: nil)
        line_for(account, notes: notes).merge(debit_cents: amount_cents, credit_cents: 0)
      end

      # Build a credit line hash.
      def credit(account, amount_cents, notes: nil)
        line_for(account, notes: notes).merge(debit_cents: 0, credit_cents: amount_cents)
      end

      def line_for(account, notes:)
        ref = account.to_account
        { account_code: ref.code, account_name: ref.name, account_type: ref.account_type,
          treasury_id: ref.treasury_id, notes: notes }
      end

      # A day's entry is keyed by location *and* date, so the generic source cleanup
      # (which would wipe every day for the location) is too broad here.
      def destroy_for_daily_sales!(location:, business_date:)
        JournalEntry.unscoped.where(
          source_record_type: "Location", source_record_id: location.id,
          company_id: Current.company.id, date: business_date
        ).where("journal_entries.description LIKE ?", "%[daily_sales]%").destroy_all
      end

      # Mirrors ChartOfAccountsService's asset-account numbering so the entry lands in
      # the same account the balance sheet shows for this asset class. FixedAsset
      # isn't Accountable (yet) — it has no code of its own to persist, unlike
      # everything else debit/credit now takes — so this builds the AccountRef by
      # hand rather than through the concern.
      def account_for_fixed_asset(asset)
        base = ChartOfAccountsService::FIXED_ASSET_BASE_CODES.fetch(asset.asset_type, 1980)
        AccountRef.new(code: base,
                       name: I18n.t("accounting.fixed_assets.asset_types.#{asset.asset_type}",
                                    default: asset.asset_type.to_s.humanize),
                       account_type: "asset", normal_balance: :debit, treasury_id: nil)
      end
    end
  end
end
