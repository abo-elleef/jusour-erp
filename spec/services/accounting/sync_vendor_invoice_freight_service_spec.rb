# frozen_string_literal: true

require "rails_helper"

RSpec.describe Accounting::SyncVendorInvoiceFreightService do
  let(:company) { Current.company }
  let(:user) { create(:user, :owner, company: company) }
  let(:supplier) { Supplier.create!(name: "Fresh Farms", company: company) }
  let(:location) { create(:location, company: company) }
  let(:treasury) do
    Treasury.create!(
      name: "Main Safe", treasury_type: "safe",
      balance_cents: 500_000, opening_balance_cents: 500_000, company: company
    )
  end
  let(:category) { IngredientCategory.create!(name: "Produce", position: 1, company: company) }
  let(:ingredient) do
    Ingredient.create!(
      name: "Tomatoes", ingredient_category: category, unit: "kg",
      reorder_threshold: 1, cost_per_unit_cents: 100, quantity_on_hand: 0, company: company
    )
  end
  let(:invoice) do
    inv = VendorInvoice.new(
      supplier: supplier, user: user, location: location,
      invoice_date: Date.current, received_on: Date.current, company: company
    )
    inv.vendor_invoice_lines.build(ingredient: ingredient, quantity: 2, line_total_cents: 1_000)
    Inventory::ReceiveVendorInvoiceService.new(inv, user).call
    inv.reload
  end

  it "creates a Goods delivery expense linked to the invoice without changing VI total" do
    goods_total = invoice.total_cents
    opening = treasury.balance_cents

    expect {
      described_class.call(
        invoice: invoice, user: user, amount_cents: 15_000, treasury: treasury
      )
    }.to change(Expense, :count).by(1)

    expense = invoice.reload.freight_expense
    expect(expense).to have_attributes(
      amount_cents: 15_000,
      is_auto_generated: true,
      expense_category: ExpenseCategory.find_by!(name: "Goods delivery", company: company)
    )
    expect(invoice.total_cents).to eq(goods_total)
    expect(treasury.reload.balance_cents).to eq(opening - 15_000)
    expect(JournalEntry.for_source(expense)).to exist
  end

  it "requires a treasury when amount is positive" do
    expect {
      described_class.call(invoice: invoice, user: user, amount_cents: 5_000, treasury: nil)
    }.to raise_error(described_class::Error)
  end

  it "updates an existing freight expense in place and records an audit" do
    described_class.call(invoice: invoice, user: user, amount_cents: 10_000, treasury: treasury)
    expense = invoice.reload.freight_expense
    expense_id = expense.id

    expect {
      described_class.call(invoice: invoice, user: user, amount_cents: 20_000, treasury: treasury)
    }.not_to change(Expense, :count)

    expense.reload
    expect(expense.id).to eq(expense_id)
    expect(expense.amount_cents).to eq(20_000)
    expect(Expense.where(source_record: invoice).count).to eq(1)

    update_audit = expense.audits.where(action: "update").order(:version).last
    expect(update_audit).to be_present
    expect(update_audit.audited_changes).to include("amount_cents")
  end

  it "clears freight when amount is zero and restores treasury" do
    described_class.call(invoice: invoice, user: user, amount_cents: 12_000, treasury: treasury)
    opening_after = treasury.reload.balance_cents

    described_class.call(invoice: invoice, user: user, amount_cents: 0, treasury: treasury)

    expect(invoice.reload.freight_expense).to be_nil
    expect(treasury.reload.balance_cents).to eq(opening_after + 12_000)
  end
end
