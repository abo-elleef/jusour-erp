# frozen_string_literal: true

require "rails_helper"

# A voucher settles several different kinds of thing, and each names itself
# differently and lives somewhere different. The views used to call
# `record.description` and build an admin/accounting path directly, which held
# only while expenses and incomes were the only options — the first voucher to
# pay a supplier invoice took the whole page down with a NoMethodError.
RSpec.describe SettledRecordsHelper, type: :helper do
  it "knows how to name and link every type a voucher can settle" do
    PaymentAllocation::SETTLEABLE_TYPES.each do |type|
      record = build_settleable(type)

      expect(helper.settled_label(record))
        .to be_present, "no label for #{type}"
      expect(helper.settled_path(record))
        .to be_present, "no path for #{type}"
    end
  end

  it "answers an outstanding amount where one means something, and nil otherwise" do
    expect(helper.settled_outstanding_cents(build_settleable("Expense"))).to be_a(Integer)
    expect(helper.settled_outstanding_cents(build_settleable("VendorInvoice"))).to be_a(Integer)
    # A party has no single outstanding amount — money on account is not
    # against one thing.
    expect(helper.settled_outstanding_cents(build_settleable("Customer"))).to be_nil
  end

  it "falls back to plain text rather than raising when there is nowhere to link" do
    expect(helper.settled_link(nil)).to be_blank
  end

  # Minimal persisted records, one per settleable type.
  def build_settleable(type)
    company = Current.company
    user = create(:user, company: company)

    case type
    when "Expense"
      Expense.create!(company: company, user: user, description: "Rent", amount_cents: 1_000,
                      expense_date: Date.current,
                      expense_category: ExpenseCategory.create!(name: "Rent #{SecureRandom.hex(3)}",
                                                                category_type: "rent", position: 1,
                                                                company: company))
    when "Income"
      Income.create!(company: company, user: user, description: "Catering", amount_cents: 1_000,
                     income_date: Date.current,
                     income_category: IncomeCategory.create!(name: "Catering #{SecureRandom.hex(3)}",
                                                             category_type: "catering", position: 1,
                                                             company: company))
    when "VendorInvoice"
      supplier = Supplier.create!(name: "Farms #{SecureRandom.hex(3)}", lead_time_days: 2, company: company)
      inv = VendorInvoice.new(supplier: supplier, user: user, location: create(:location, company: company),
                              invoice_number: "INV-#{SecureRandom.hex(3)}", invoice_date: Date.current,
                              received_on: Date.current, company: company)
      inv.save!(validate: false)
      inv
    when "CustomerInvoice"
      CustomerInvoice.create!(company: company, customer: create(:customer, company: company),
                              user: user, location: create(:location, company: company),
                              invoice_date: Date.current)
    when "PayrollAdvance"
      staff = create(:user, company: company, role: "cashier", monthly_salary_cents: 300_000)
      PayrollAdvance.create!(company: company, user: staff, paid_by: user,
                             treasury: Treasury.create!(company: company, name: "Adv Safe #{SecureRandom.hex(3)}",
                                                        treasury_type: "safe", opening_balance_cents: 100_000,
                                                        balance_cents: 100_000),
                             amount_cents: 10_000, paid_on: Date.current)
    when "Customer" then create(:customer, company: company)
    when "Supplier" then Supplier.create!(name: "Farms #{SecureRandom.hex(3)}", lead_time_days: 2, company: company)
    else raise "no fixture for settleable type #{type}"
    end
  end
end
