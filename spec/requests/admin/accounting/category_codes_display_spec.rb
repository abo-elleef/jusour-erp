# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Category account code display", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { Current.company }
  let(:owner)   { create(:user, :owner, company: company) }

  before { sign_in owner }

  it "shows the account code on the income categories index" do
    cat = IncomeCategory.create!(name: "Catering", category_type: "catering", company: company)
    get admin_accounting_income_categories_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(cat.account_code.to_s)
  end

  it "shows the account code on the expense categories index" do
    cat = ExpenseCategory.create!(name: "Rent", category_type: "rent", company: company)
    get admin_accounting_expense_categories_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(cat.account_code.to_s)
  end

  it "shows the fixed code on the category edit page" do
    cat = ExpenseCategory.create!(name: "Utilities", category_type: "utilities", company: company)
    get edit_admin_accounting_expense_category_path(cat)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(cat.account_code.to_s)
    expect(response.body).to include(I18n.t("accounting.expense_categories.code"))
  end
end
