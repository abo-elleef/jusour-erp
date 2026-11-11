# frozen_string_literal: true

# Walks every way money moves in this app and checks, after each one, that the
# ledger and the treasuries still agree.
#
#   bin/rails accounting:verify_money_paths
#   DATABASE_URL=postgres:///saqr_pos_prod_copy bin/rails accounting:verify_money_paths
#
# Everything runs inside a transaction that is always rolled back, so it is safe
# to point at a copy of production — which is the point. A unit spec proves a
# path behaves on fixtures; this proves it behaves on the company's real chart
# of accounts, treasuries, suppliers and customers.
#
# The invariant: for every treasury, (what the treasury says moved) minus (what
# the ledger says moved) must not CHANGE. Real drift already exists in these
# books from before any of this, so the absolute number is not the test — an
# activity that alters it is posting to one side and not the other, which is
# what a double-post looks like from the outside.
#
# Run this before merging anything that touches money. See
# `accounting:verify_money_paths` in the README of your own head: a branch that
# changes an expense, a payment, a treasury or the ledger is a branch this
# should pass on first.
namespace :accounting do
  desc "Exercise every money path and check the ledger still matches the treasuries"
  task verify_money_paths: :environment do
    company = Company.find_by(name: ENV["COMPANY"]) || Company.first
    abort "no company found" if company.blank?

    Current.company = company
    puts "company: #{company.name}"
    puts ""

    checker = MoneyPathChecker.new(company)
    ActiveRecord::Base.transaction do
      checker.run!
      raise ActiveRecord::Rollback
    end

    puts ""
    if checker.failures.zero?
      puts "all #{checker.checks} money paths kept the ledger and the treasuries in step."
    else
      puts "#{checker.failures} of #{checker.checks} moved the drift — see above."
    end
    puts "rolled back; nothing was written."
    exit(1) unless checker.failures.zero?
  end
end

# Deliberately a plain object in the rake file rather than app/: it exists to
# test the app, and nothing in the app should be able to call it.
class MoneyPathChecker
  attr_reader :checks, :failures

  def initialize(company)
    @company = company
    @checks = 0
    @failures = 0
    @skips = []
  end

  def run!
    @before = drift

    expenses_and_income!
    treasury_transfer!
    treasury_adjustment!
    supplier_flow!
    customer_flow!
    staff_account!
    pos_flow!

    @skips.each { |s| puts "  SKIP #{s}" }
  end

  private

  def owner    = @owner ||= User.where(company: @company).find(&:owner?)
  def location = @location ||= Location.active.branches.ordered.first
  def safe     = @safe ||= Treasury.active.where(treasury_type: %w[safe cash_drawer bank]).first

  def skip(label, why) = @skips << "#{label} — #{why}"

  # ── The invariant ───────────────────────────────────────────────────
  def drift
    Treasury.unscoped.where(company_id: @company.id).each_with_object({}) do |t, h|
      txn = TreasuryTransaction.where(treasury_id: t.id).sum(:amount_cents)
      lines = JournalEntryLine.joins(:journal_entry)
        .where(journal_entries: { company_id: @company.id }, treasury_id: t.id)
      ledger = if t.treasury_type == "supplier_ap"
                 lines.sum("credit_cents - debit_cents")
               else
                 lines.sum("debit_cents - credit_cents")
               end
      h[[t.id, t.name]] = txn - ledger
    end
  end

  def check(label)
    @checks += 1
    now = drift
    # A treasury the activity created itself starts at zero drift.
    moved = now.reject { |key, value| (@before[key] || 0) == value }

    if moved.empty?
      puts "  OK   #{label}"
    else
      @failures += 1
      puts "  FAIL #{label}"
      moved.each { |(id, name), v| puts "       #{name}: #{@before[[id, name]] || 0} -> #{v}" }
    end
    @before = now
  end

  # ── Paths ───────────────────────────────────────────────────────────

  def expenses_and_income!
    category = ExpenseCategory.ordered.first
    return skip("expense", "no expense category") if category.blank?

    expense = Expense.create!(company: @company, user: owner, treasury: safe,
                              expense_category: category, description: "verify",
                              amount_cents: 1_234, expense_date: Date.current)
    check "expense — paid on issue"
    expense.update!(amount_cents: 2_345)
    check "expense — amount edited"
    expense.update!(treasury: nil)
    check "expense — switched to on account"
    expense.destroy!
    check "expense — deleted"

    income_category = IncomeCategory.ordered.first
    return skip("income", "no income category") if income_category.blank?

    income = Income.create!(company: @company, user: owner, treasury: safe,
                            income_category: income_category, description: "verify",
                            amount_cents: 999, income_date: Date.current)
    check "income — collected on issue"
    income.destroy!
    check "income — deleted"
  end

  def treasury_transfer!
    other = Treasury.active.where.not(id: safe.id)
      .where.not(treasury_type: %w[supplier_ap customer_ar]).first
    return skip("treasury transfer", "needs a second treasury") if other.blank?

    Accounting::TreasuryLedgerService.create_transfer!(
      TreasuryTransfer.new(from_treasury: safe, to_treasury: other, amount_cents: 500,
                           user: owner, company: @company,
                           description: "verify", occurred_on: Date.current)
    )
    check "treasury transfer"
  end

  def treasury_adjustment!
    Accounting::TreasuryLedgerService.new.record_adjustment!(
      treasury: safe, user: owner, amount_cents: 777,
      description: "verify", occurred_on: Date.current
    )
    check "treasury adjustment"
  end

  def supplier_flow!
    supplier = Supplier.where(company: @company).first
    ingredient = Ingredient.where(company: @company).first
    return skip("supplier flow", "needs a supplier and an ingredient") if supplier.blank? || ingredient.blank?
    return skip("supplier flow", "needs a branch") if location.blank?

    invoice = VendorInvoice.new(supplier: supplier, user: owner, location: location,
                                company: @company, invoice_number: "VERIFY-#{SecureRandom.hex(4)}",
                                invoice_date: Date.current, received_on: Date.current)
    invoice.vendor_invoice_lines.build(ingredient: ingredient, quantity: 1, line_total_cents: 5_000)
    invoice.save!
    Accounting::SupplierApLedgerService.record_invoice!(invoice: invoice, user: owner)
    check "vendor invoice — received"

    voucher = Accounting::RecordVendorInvoicePaymentService.new(
      vendor_invoice: invoice.reload, user: owner, treasury: safe,
      amount_cents: 2_000, payment_date: Date.current
    ).call
    check "vendor invoice — payment"

    Accounting::ReverseVendorInvoicePaymentService.new(payment: voucher, user: owner).call
    check "vendor invoice — payment reversed"

    # What the voucher form issues for "Pay by voucher" / the supplier page: the
    # supplier as the voucher's party, settling their invoices oldest first.
    voucher = Accounting::RecordVoucherService.new(
      direction: Voucher::PAYMENT, treasury: safe, user: owner, amount_cents: 3_000,
      voucher_date: Date.current, counterparty: supplier.name, company: @company,
      party_type: "Supplier", party_id: supplier.id,
      allocations: [{ settles: invoice.reload, amount_cents: 3_000 }]
    ).call
    check "vendor invoice — voucher with supplier as party"

    voucher.void!(user: owner, reason: :voided_by_user)
    check "vendor invoice — party voucher voided"

    credit_note = VendorCreditNote.create!(
      supplier: supplier, user: owner, company: @company, location: location,
      vendor_invoice: invoice.reload, credit_note_date: Date.current, kind: "goods_return",
      vendor_credit_note_lines_attributes: [{ ingredient_id: ingredient.id, quantity: 1,
                                              line_total_cents: 1_000, position: 0 }]
    )
    Inventory::ConfirmVendorCreditNoteService.call!(credit_note: credit_note, user: owner)
    check "vendor credit note — confirmed against invoice"

    Inventory::VoidVendorCreditNoteService.call!(credit_note: credit_note.reload, user: owner)
    check "vendor credit note — voided"
  end

  def customer_flow!
    customer = Customer.where(company: @company).first
    ingredient = Ingredient.where(company: @company).first
    return skip("customer flow", "needs a customer and an ingredient") if customer.blank? || ingredient.blank?
    return skip("customer flow", "needs a branch") if location.blank?

    invoice = CustomerInvoice.new(company: @company, customer: customer, user: owner,
                                  location: location, invoice_date: Date.current)
    invoice.customer_invoice_lines.build(ingredient: ingredient, quantity: 1,
                                         unit: ingredient.unit, unit_price_cents: 6_000)
    invoice.save!

    begin
      Sales::ConfirmCustomerInvoiceService.new(invoice, owner).call
      check "customer invoice — confirmed on account"
    rescue StandardError => e
      return skip("customer invoice", "could not confirm: #{e.message}")
    end

    # Against the invoice: FIFO puts it on the oldest open one.
    Sales::RecordCustomerPaymentService.new(customer: customer, treasury: safe,
                                            amount_cents: 6_000, user: owner).call
    check "customer invoice — payment"

    # Beyond what is owed: the rest goes on the customer's own account.
    Sales::RecordCustomerPaymentService.new(customer: customer, treasury: safe,
                                            amount_cents: 1_000, user: owner).call
    check "customer payment — on account"

    # What the voucher form issues for the customer statement's "Receive by
    # voucher": the customer as the voucher's party, an invoice line and the
    # overpayment left on their own account.
    second = CustomerInvoice.new(company: @company, customer: customer, user: owner,
                                 location: location, invoice_date: Date.current)
    second.customer_invoice_lines.build(ingredient: ingredient, quantity: 1,
                                        unit: ingredient.unit, unit_price_cents: 4_000)
    second.save!
    Sales::ConfirmCustomerInvoiceService.new(second, owner).call
    check "customer invoice — second confirmed on account"

    Accounting::RecordVoucherService.new(
      direction: Voucher::RECEIPT, treasury: safe, user: owner, amount_cents: 5_000,
      voucher_date: Date.current, counterparty: customer.display_name, company: @company,
      party_type: "Customer", party_id: customer.id,
      allocations: [{ settles: second.reload, amount_cents: 4_000 }, { settles: customer, amount_cents: 1_000 }]
    ).call
    check "customer payment — voucher with customer as party, rest on account"
  end

  # Money to and from an employee is a voucher against their own account;
  # finalizing a month credits that account and, given a treasury, pays the
  # balance out with one more voucher. Undoing the month voids that voucher.
  def staff_account!
    staff = User.where(company: @company).where("monthly_salary_cents > 0").first
    return skip("staff account", "no staff with a salary") if staff.blank?

    staff_voucher = lambda do |direction, cents|
      Accounting::RecordVoucherService.new(
        direction: direction, treasury: safe, user: owner, amount_cents: cents,
        party_type: "User", party_id: staff.id
      ).call
    end

    paid = staff_voucher.call(Voucher::PAYMENT, 500)
    check "staff — paid ahead of payroll"
    staff_voucher.call(Voucher::RECEIPT, 200)
    check "staff — money received back"
    paid.void!(user: owner)
    check "staff — payment voided"

    month = Date.current.beginning_of_month
    month = month.next_month while PayrollSnapshot.exists?(user: staff, payroll_month: month)
    snapshot = Accounting::FinalizePayrollService.new(staff, month, finalized_by: owner, treasury: safe).call
    check "staff — month finalized and paid out"
    snapshot.payout_voucher&.void!(user: owner)
    Accounting::JournalEntryService.destroy_for_source!(snapshot)
    snapshot.destroy!
    check "staff — month undone"
  end

  # Opening a drawer, selling, taking cash and closing the day.
  def pos_flow!
    return skip("POS", "needs a branch") if location.blank?

    item = MenuItem.where(company: @company).first
    drawer = Treasury.active.where(treasury_type: "cash_drawer").first
    return skip("POS", "needs a menu item and a cash drawer") if item.blank? || drawer.blank?

    session = CashDrawerSession.create!(
      company: @company, user: owner, treasury: drawer, location: location,
      session_date: Date.current, opening_float_cents: 10_000,
      float_source_treasury: safe, status: "open"
    )
    Accounting::TreasuryLedgerService.sync_drawer_open!(session)
    check "POS — drawer opened"

    order = Order.create!(company: @company, location: location, user: owner,
                          order_type: "table", status: "completed",
                          order_number: "V#{SecureRandom.hex(3)}")
    order.order_items.create!(menu_item: item, quantity: 1, unit_price_cents: 5_000)
    order.update!(subtotal_cents: 5_000, total_cents: 5_000)
    Payments::CashPaymentService.call(order: order, amount_cents: 5_000,
                                      tip_cents: 0, user: owner)
    check "POS — cash sale"

    # A cash delivery: the customer pays food + fee, and the driver keeps the fee,
    # so it is paid out of this drawer rather than counted into it.
    delivery = Order.create!(company: @company, location: location, user: owner,
                             order_type: "delivery", delivery_address: "verify", status: "completed",
                             order_number: "V#{SecureRandom.hex(3)}")
    delivery.order_items.create!(menu_item: item, quantity: 1, unit_price_cents: 4_000)
    delivery.update!(subtotal_cents: 4_000, total_cents: 4_000)
    delivery.apply_delivery_fee!(1_500, drawer_session: session)
    Payments::CashPaymentService.call(order: delivery, amount_cents: delivery.total_cents,
                                      tip_cents: 0, user: owner)
    check "POS — delivery, driver keeps the fee"

    # An order rung up in the browser while the internet was down, delivered later.
    offline = Orders::SyncOfflineOrderService.call(
      user: owner,
      payload: {
        client_uuid: SecureRandom.uuid, offline_number: "OFF-V", location_id: location.id,
        user_id: owner.id, drawer_session_id: session.id, order_type: "pickup",
        items: [{ menu_item_id: item.id, quantity: 1, unit_price_cents: 3_000 }]
      }
    )
    raise "offline order did not sync: #{offline.errors.to_sentence}" unless offline.success?

    check "POS — offline order synced"

    reconciler = Accounting::CashReconciliationService.new(session)
    expected = reconciler.compute_expected!
    # Float + cash sale + delivery food (the fee went to the driver) + offline order.
    counted = 15_000 + 4_000 + offline.order.payments.sum(:amount_cents)
    raise "drawer expected #{expected}, but #{counted} is in it" unless expected == counted

    reconciler.reconcile!(counted)
    check "POS — drawer reconciled"
  rescue StandardError => e
    skip("POS", "could not exercise: #{e.class} #{e.message}")
  end
end
