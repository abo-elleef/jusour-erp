# frozen_string_literal: true

require "rails_helper"
require "rake"

# The backfill reconstructs history that was never written down. What it must
# get right: the supplier side exactly, the customer side by replaying the same
# FIFO rule, a dry run that writes nothing, and a second run that does not
# collide with the first.
RSpec.describe "payment_allocations:backfill" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  let(:task) { Rake::Task["payment_allocations:backfill"] }

  before { task.reenable }

  let(:company)  { create(:company) }
  let(:user)     { create(:user, company: company) }
  let(:location) { create(:location, company: company) }
  let(:category) { create(:ingredient_category, company: company) }
  let(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category, name: "Kit", unit: "kg")
  end
  let(:cash) do
    Treasury.create!(name: "Cash", treasury_type: "cash_drawer", balance_cents: 0,
                     opening_balance_cents: 0, company: company)
  end
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

  before do
    Current.company = company
    StockBatch.create!(ingredient: ingredient, location: location, quantity_received: 1000,
                       quantity_remaining: 1000, cost_per_unit_cents: 1_000,
                       received_on: Date.current)
  end

  def confirm_invoice!(total_cents:, date: Date.current)
    inv = CustomerInvoice.new(company: company, customer: customer, user: user,
                              location: location, invoice_date: date)
    inv.customer_invoice_lines.build(ingredient: ingredient, quantity: 1,
                                     unit: ingredient.unit, unit_price_cents: total_cents)
    inv.save!
    Sales::ConfirmCustomerInvoiceService.new(inv, user).call
    inv.reload
  end

  # A payment as production holds it from before allocations existed: a
  # CustomerPayment row, the AR ledger settled, each invoice's amount_paid_cents
  # bumped FIFO — and no record anywhere of which invoice got what. Built
  # directly, because the service writes a voucher now and these old rows are
  # exactly what the backfill is for.
  def legacy_payment!(amount_cents:, date: Date.current)
    payment = CustomerPayment.create!(
      company: company, customer: customer, user: user, treasury: cash,
      amount_cents: amount_cents, payment_date: date
    )
    Accounting::CustomerArLedgerService.new(customer).settle!(
      treasury: cash, amount_cents: amount_cents, user: user,
      occurred_on: date, source: payment
    )

    remaining = amount_cents
    customer.customer_invoices.outstanding.order(:invoice_date, :created_at).each do |invoice|
      break if remaining <= 0

      applied = [invoice.balance_due_cents, remaining].min
      next if applied <= 0

      invoice.update!(amount_paid_cents: invoice.amount_paid_cents + applied)
      invoice.sync_payment_status!
      remaining -= applied
    end

    payment
  end

  it "replays the FIFO split a customer payment left no record of" do
    older = confirm_invoice!(total_cents: 100_000, date: 20.days.ago.to_date)
    newer = confirm_invoice!(total_cents: 60_000,  date: 5.days.ago.to_date)
    payment = legacy_payment!(amount_cents: 120_000)
    expect(PaymentAllocation.count).to eq(0)

    task.invoke("commit")

    by_invoice = payment.reload.payment_allocations.index_by(&:settles_id)
    expect(by_invoice[older.id].amount_cents).to eq(100_000)
    expect(by_invoice[newer.id].amount_cents).to eq(20_000)
  end

  it "reproduces what each invoice already says it was paid" do
    confirm_invoice!(total_cents: 100_000, date: 20.days.ago.to_date)
    confirm_invoice!(total_cents: 60_000,  date: 5.days.ago.to_date)
    legacy_payment!(amount_cents: 120_000)

    task.invoke("commit")

    CustomerInvoice.find_each do |invoice|
      expect(invoice.payment_allocations.sum(:amount_cents)).to eq(invoice.amount_paid_cents)
    end
  end

  it "writes nothing on a dry run" do
    confirm_invoice!(total_cents: 100_000)
    legacy_payment!(amount_cents: 100_000)

    task.invoke

    expect(PaymentAllocation.count).to eq(0)
  end

  it "can be run twice without colliding on the unique index" do
    confirm_invoice!(total_cents: 100_000)
    legacy_payment!(amount_cents: 100_000)

    task.invoke("commit")
    before_count = PaymentAllocation.count
    task.reenable

    expect { task.invoke("commit") }.not_to raise_error
    expect(PaymentAllocation.count).to eq(before_count)
  end

  it "stops short of an overpayment instead of over-allocating an invoice" do
    confirm_invoice!(total_cents: 100_000)
    payment = legacy_payment!(amount_cents: 130_000)

    task.invoke("commit")

    expect(payment.reload.payment_allocations.sum(:amount_cents)).to eq(100_000)
    expect(payment.unallocated_cents).to eq(30_000)
  end

  describe "the supplier side, where the invoice was always known" do
    let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company) }
    let(:safe) do
      Treasury.create!(name: "Safe", treasury_type: "safe", opening_balance_cents: 100_000,
                       balance_cents: 100_000, company: company)
    end

    before do
      ExpenseCategory.find_or_create_by!(name: "Vendor purchases", company: company) do |c|
        c.category_type = "other"
        c.system_managed = true
        c.position = 0
      end
    end

    it "allocates each payment to its own invoice for the full amount" do
      inv = VendorInvoice.new(supplier: supplier, user: user, location: location,
                              invoice_number: "INV-7001", invoice_date: Date.current,
                              received_on: Date.current, company: company)
      inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10, line_total_cents: 5_000)
      inv.save!

      # A VendorInvoicePayment as it exists in production from before payments
      # became vouchers. Built directly: the service writes a voucher now, and
      # these old rows are exactly what the backfill is for.
      payment = VendorInvoicePayment.create!(
        vendor_invoice: inv, user: user, treasury: safe,
        amount_cents: 3_000, payment_date: Date.current, company: company
      )

      task.invoke("commit")

      allocation = payment.reload.payment_allocations.sole
      expect(allocation.settles).to eq(inv)
      expect(allocation.amount_cents).to eq(3_000)
    end
  end
end
