# frozen_string_literal: true

require "rails_helper"

RSpec.describe "audit history helpers", type: :helper do
  let(:company) { Current.company }
  let(:user) { create(:user, :owner, company: company) }

  it "formats update changes as from → to rows" do
    audit = Audited::Audit.new(
      action: "update",
      audited_changes: { "description" => %w[old new], "amount_cents" => [1000, 2500] }
    )

    rows = helper.audit_history_rows(audit)
    expect(rows).to include(
      hash_including(kind: :update, from: "old", to: "new")
    )
    amount_row = rows.find { |r| r[:label] == I18n.t("accounting.audit_history.fields.amount_cents") }
    expect(amount_row[:from]).to include("10.00")
    expect(amount_row[:to]).to include("25.00")
  end

  it "resolves association ids to names on create" do
    category = ExpenseCategory.find_or_create_by!(name: "Supplies", company: company) do |c|
      c.category_type = "other"
      c.position = 10
    end
    audit = Audited::Audit.new(
      action: "create",
      audited_changes: {
        "description" => "Paper",
        "expense_category_id" => category.id,
        "company_id" => company.id
      }
    )

    rows = helper.audit_history_rows(audit)
    expect(rows.map { |r| r[:label] }).not_to include("Company")
    cat_row = rows.find { |r| r[:label] == I18n.t("accounting.audit_history.fields.expense_category_id") }
    expect(cat_row[:value]).to eq("Supplies")
  end
end
