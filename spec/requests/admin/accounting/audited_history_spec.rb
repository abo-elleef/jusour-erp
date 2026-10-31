# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Audited change history", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner) { create(:user, :owner, company: company) }
  let!(:treasury) do
    Treasury.create!(
      name: "Main Safe", treasury_type: "safe",
      balance_cents: 500_000, opening_balance_cents: 500_000, company: company
    )
  end
  let!(:expense_category) do
    ExpenseCategory.find_or_create_by!(name: "Supplies", company: company) do |c|
      c.category_type = "other"
      c.position = 10
    end
  end
  let!(:income_category) do
    IncomeCategory.find_or_create_by!(name: "Catering", company: company) do |c|
      c.category_type = "catering"
      c.position = 10
    end
  end

  before { sign_in owner }

  describe "Expense" do
    it "records create and update audits and shows them on the show page" do
      expense = nil
      expect {
        expense = Expense.create!(
          expense_category: expense_category, amount_cents: 10_000,
          expense_date: Date.current, description: "Paper",
          recurrence: "one_time", user: owner, treasury: treasury,
          is_auto_generated: false, company: company
        )
      }.to change { Audited::Audit.where(auditable_type: "Expense").count }.by(1)

      create_audit = expense.audits.find_by!(action: "create")
      expect(create_audit.associated).to eq(company)

      expense.update!(description: "Paper towels")
      update_audit = expense.audits.find_by!(action: "update")
      expect(update_audit.audited_changes).to include("description")

      get admin_accounting_expense_path(expense)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
      expect(response.body).to include("Paper towels")
      expect(response.body).to include(I18n.t("accounting.audit_history.fields.description"))
      expect(response.body).not_to include('"description"')
    end

    it "audits auto-generated expenses" do
      expect {
        Expense.create!(
          expense_category: expense_category, amount_cents: 5_000,
          expense_date: Date.current, description: "Vendor payment",
          recurrence: "one_time", user: owner, treasury: treasury,
          is_auto_generated: true, company: company
        )
      }.to change { Audited::Audit.where(auditable_type: "Expense", action: "create").count }.by(1)
    end
  end

  describe "Income" do
    it "records create audits and shows history on the show page" do
      income = Income.create!(
        income_category: income_category, amount_cents: 25_000,
        income_date: Date.current, description: "Catering job",
        recurrence: "one_time", user: owner, treasury: treasury,
        is_auto_generated: false, company: company
      )
      expect(income.audits.where(action: "create")).to exist

      get admin_accounting_income_path(income)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
    end
  end

  describe "User (staff)" do
    it "records updates without secret fields and shows history" do
      staff = create(:user, company: company, name: "Cashier One", role: "cashier")

      staff.update!(name: "Cashier Two", password: "newpass99", password_confirmation: "newpass99")
      audit = staff.audits.where(action: "update").order(:version).last
      expect(audit.audited_changes.keys).to include("name")
      expect(audit.audited_changes.keys).not_to include(
        "encrypted_password", "pin_digest", "payroll_access_token", "reset_password_token"
      )

      get_user_tab(staff, "history")
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("accounting.audit_history.title"))
    end
  end
end
