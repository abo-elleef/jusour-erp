# frozen_string_literal: true

require "rails_helper"

# C2 + C3: the financial statements and the profit figure quoted on the dashboard,
# the sales report and the accounting-software sync all read the same ledger, so
# every way the company earns money is counted exactly once, whichever report you
# open and whichever selling motion produced it.
RSpec.describe "Ledger-backed revenue reporting" do
  let(:company) { create(:company, business_type: "distribution") }
  let(:user) { create(:user, :owner, company: company) }
  let(:location) { create(:location, company: company) }
  let(:today) { Date.current }

  let!(:cash) do
    Treasury.create!(company: company, name: "Cash", treasury_type: "cash_drawer",
      balance_cents: 0, opening_balance_cents: 0)
  end
  let(:category) { create(:ingredient_category, company: company) }
  let!(:ingredient) do
    create(:ingredient, company: company, ingredient_category: category,
      name: "Composite", unit: "pieces", selling_price_cents: 10_000)
  end
  let(:customer) { create(:customer, company: company, name: "Clinic", customer_type: "commercial") }

  before { Current.company = company }

  def coa
    Accounting::ChartOfAccountsService.new(start_date: today, end_date: today)
  end

  def pnl
    Accounting::PnlService.new(today, today).call
  end

  def record_income!(cents)
    cat = IncomeCategory.create!(company: company, name: "Misc income", category_type: "other")
    Income.create!(company: company, income_category: cat, amount_cents: cents,
      income_date: today, description: "Misc", recurrence: "one_time",
      user: user, treasury: cash, is_auto_generated: false)
  end

  def confirm_invoice!(cents)
    invoice = CustomerInvoice.new(company: company, customer: customer, user: user,
      location: location, invoice_date: today)
    invoice.customer_invoice_lines.build(ingredient: ingredient, quantity: 1,
      unit: ingredient.unit, unit_price_cents: cents)
    invoice.save!
    Sales::ConfirmCustomerInvoiceService.new(invoice, user).call
    invoice
  end

  def post_pos_day!(subtotal:, tax: 0)
    Order.create!(company: company, user: user, location: location, order_type: "pickup",
      status: "completed", subtotal_cents: subtotal, discount_cents: 0,
      tax_cents: tax, tip_cents: 0, total_cents: subtotal + tax)
    Accounting::JournalEntryService.record_daily_sales!(
      location: location, business_date: today, user: user
    )
  end

  describe "revenue" do
    it "counts manual income once, not twice" do
      record_income!(50_000)

      expect(coa.total_revenue_cents).to eq(50_000)
    end

    it "counts a confirmed customer invoice — which no report used to show" do
      confirm_invoice!(120_000)

      expect(coa.total_revenue_cents).to eq(120_000)
      expect(pnl[:revenue][:net_sales_cents]).to eq(120_000)
    end

    it "counts POS takings recognised at day close" do
      post_pos_day!(subtotal: 80_000, tax: 11_200)

      expect(coa.total_revenue_cents).to eq(80_000)
      expect(pnl[:revenue][:net_sales_cents]).to eq(80_000)
    end

    it "adds up across every selling motion at once" do
      record_income!(50_000)
      confirm_invoice!(120_000)
      post_pos_day!(subtotal: 80_000)

      expect(coa.total_revenue_cents).to eq(250_000)
    end

    it "nets a credit note back off revenue" do
      invoice = confirm_invoice!(120_000)
      note = CreditNote.new(company: company, customer: customer, user: user,
        location: location, credit_note_date: today, customer_invoice: invoice, restock: false)
      note.credit_note_lines.build(ingredient: ingredient, quantity: 1, unit: ingredient.unit,
        unit_price_cents: 20_000)
      note.save!
      Sales::ConfirmCreditNoteService.new(note, user).call

      expect(coa.total_revenue_cents).to eq(100_000)
    end
  end

  describe "expenses" do
    it "counts an expense once" do
      cat = ExpenseCategory.create!(company: company, name: "Rent", category_type: "rent")
      Expense.create!(company: company, expense_category: cat, amount_cents: 30_000,
        expense_date: today, description: "Rent", recurrence: "one_time",
        user: user, treasury: cash, is_auto_generated: false)

      expect(coa.total_expenses_cents).to eq(30_000)
    end

    it "leaves auto-generated COGS out — stock is expensed when bought, not when sold" do
      cogs = ExpenseCategory.create!(company: company, name: "COGS", category_type: "other")
      Expense.create!(company: company, expense_category: cogs, amount_cents: 25_000,
        expense_date: today, description: "COGS — Order #1", recurrence: "one_time",
        user: user, is_auto_generated: true)

      expect(coa.total_expenses_cents).to eq(0)
    end
  end

  describe "the two reports agree" do
    it "quotes the same net profit on the dashboard as on the P&L statement" do
      record_income!(50_000)
      confirm_invoice!(120_000)
      post_pos_day!(subtotal: 80_000)
      cat = ExpenseCategory.create!(company: company, name: "Rent", category_type: "rent")
      Expense.create!(company: company, expense_category: cat, amount_cents: 30_000,
        expense_date: today, description: "Rent", recurrence: "one_time",
        user: user, treasury: cash, is_auto_generated: false)

      expect(pnl[:net_profit_cents]).to eq(coa.net_income_cents)
      expect(pnl[:net_profit_cents]).to eq(250_000 - 30_000)
    end

    it "agrees even for a company that never touches the POS" do
      confirm_invoice!(120_000)

      expect(pnl[:net_profit_cents]).to eq(coa.net_income_cents)
      expect(pnl[:net_profit_cents]).to eq(120_000)
    end
  end
end
