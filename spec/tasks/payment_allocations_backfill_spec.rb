# frozen_string_literal: true

require "rails_helper"
require "rake"

# The backfill reconstructs history that was never written down for supplier
# payments: the invoice is exact, but nothing records a dry run wrote nothing,
# or that a second run does not collide with the first.
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

  before { Current.company = company }

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

    it "writes nothing on a dry run" do
      inv = VendorInvoice.new(supplier: supplier, user: user, location: location,
                              invoice_number: "INV-7002", invoice_date: Date.current,
                              received_on: Date.current, company: company)
      inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10, line_total_cents: 5_000)
      inv.save!
      VendorInvoicePayment.create!(
        vendor_invoice: inv, user: user, treasury: safe,
        amount_cents: 3_000, payment_date: Date.current, company: company
      )

      task.invoke

      expect(PaymentAllocation.count).to eq(0)
    end

    it "can be run twice without colliding on the unique index" do
      inv = VendorInvoice.new(supplier: supplier, user: user, location: location,
                              invoice_number: "INV-7003", invoice_date: Date.current,
                              received_on: Date.current, company: company)
      inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10, line_total_cents: 5_000)
      inv.save!
      VendorInvoicePayment.create!(
        vendor_invoice: inv, user: user, treasury: safe,
        amount_cents: 3_000, payment_date: Date.current, company: company
      )

      task.invoke("commit")
      before_count = PaymentAllocation.count
      task.reenable

      expect { task.invoke("commit") }.not_to raise_error
      expect(PaymentAllocation.count).to eq(before_count)
    end
  end
end
