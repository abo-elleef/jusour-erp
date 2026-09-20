# frozen_string_literal: true

require "rails_helper"

# Until this table existed, an invoice could say it was paid without being able
# to say by what. The customer side spread a payment across outstanding invoices
# FIFO and discarded the split; the supplier side knew its one invoice but never
# wrote the application down in a form anything could read back.
RSpec.describe PaymentAllocation, type: :model do
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

  describe "a customer payment spread across invoices" do
    it "records which invoice got what, matching the FIFO split" do
      older = confirm_invoice!(total_cents: 100_000, date: 20.days.ago.to_date)
      newer = confirm_invoice!(total_cents: 60_000,  date: 5.days.ago.to_date)

      payment = Sales::RecordCustomerPaymentService.new(
        customer: customer, treasury: cash, amount_cents: 120_000, user: user
      ).call

      allocations = payment.payment_allocations.order(:amount_cents)
      expect(allocations.count).to eq(2)
      expect(allocations.map(&:settles)).to contain_exactly(older, newer)

      by_invoice = allocations.index_by(&:settles_id)
      expect(by_invoice[older.id].amount_cents).to eq(100_000)
      expect(by_invoice[newer.id].amount_cents).to eq(20_000)
    end

    it "agrees with the amount_paid_cents it wrote on each invoice" do
      older = confirm_invoice!(total_cents: 100_000, date: 20.days.ago.to_date)
      newer = confirm_invoice!(total_cents: 60_000,  date: 5.days.ago.to_date)

      Sales::RecordCustomerPaymentService.new(
        customer: customer, treasury: cash, amount_cents: 120_000, user: user
      ).call

      [older, newer].each do |invoice|
        expect(invoice.payment_allocations.sum(:amount_cents))
          .to eq(invoice.reload.amount_paid_cents)
      end
    end

    it "puts an overpayment on the customer's account, not on an invoice" do
      invoice = confirm_invoice!(total_cents: 100_000)

      payment = Sales::RecordCustomerPaymentService.new(
        customer: customer, treasury: cash, amount_cents: 130_000, user: user
      ).call

      by_target = payment.payment_allocations.group_by { |a| a.settles_type }
      expect(by_target["CustomerInvoice"].sole.amount_cents).to eq(100_000)
      expect(by_target["CustomerInvoice"].sole.settles).to eq(invoice)

      # The 30,000 they are in credit for stays on their own receivable, where
      # their statement can find it — not in a pooled account.
      expect(by_target["Customer"].sole.amount_cents).to eq(30_000)
      expect(customer.reload.ar_balance_cents).to eq(-30_000)
    end

    it "builds a trail across several payments, so an invoice names every receipt" do
      invoice = confirm_invoice!(total_cents: 100_000)

      first = Sales::RecordCustomerPaymentService.new(
        customer: customer, treasury: cash, amount_cents: 40_000, user: user
      ).call
      second = Sales::RecordCustomerPaymentService.new(
        customer: customer, treasury: cash, amount_cents: 60_000, user: user
      ).call

      expect(invoice.payment_allocations.map(&:payment)).to contain_exactly(first, second)
      expect(invoice.payment_allocations.sum(:amount_cents)).to eq(100_000)
      expect(invoice.reload.payment_status).to eq("paid")
    end
  end

  describe "a supplier payment" do
    let(:supplier) { Supplier.create!(name: "Fresh Farms", lead_time_days: 2, company: company) }
    let(:safe) do
      Treasury.create!(name: "Main Safe", treasury_type: "safe", opening_balance_cents: 100_000,
                       balance_cents: 100_000, company: company)
    end
    let(:vendor_invoice) do
      inv = VendorInvoice.new(supplier: supplier, user: user, location: location,
                              invoice_number: "INV-9001", invoice_date: Date.current,
                              received_on: Date.current, company: company)
      inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 10, line_total_cents: 5_000)
      inv.save!
      inv
    end

    before do
      ExpenseCategory.find_or_create_by!(name: "Vendor purchases", company: company) do |c|
        c.category_type = "other"
        c.system_managed = true
        c.position = 0
      end
    end

    it "records the one invoice it settles" do
      payment = Accounting::RecordVendorInvoicePaymentService.new(
        vendor_invoice: vendor_invoice, user: user, treasury: safe,
        amount_cents: 3_000, payment_date: Date.current
      ).call

      allocation = payment.payment_allocations.sole
      expect(allocation.settles).to eq(vendor_invoice)
      expect(allocation.amount_cents).to eq(3_000)
      expect(vendor_invoice.reload.amount_paid_cents).to eq(3_000)
    end
  end

  describe "validations" do
    it "refuses a non-positive amount" do
      invoice = confirm_invoice!(total_cents: 10_000)
      payment = Sales::RecordCustomerPaymentService.new(
        customer: customer, treasury: cash, amount_cents: 10_000, user: user
      ).call

      allocation = described_class.new(company: company, payment: payment,
                                       settles: invoice, amount_cents: 0)
      expect(allocation).not_to be_valid
    end
  end
end
