# frozen_string_literal: true

require "rails_helper"

# Cash drawer, digital wallets and business days are the day-close screens. They
# used to sit behind accounting:transactions, which also covers expenses and
# incomes — so opening them to sub-managers would have handed over spending too.
RSpec.describe "Who can reach the day-close screens", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Branch A") }

  before { Current.company = company }

  def visit_all
    [
      admin_accounting_cash_drawer_index_path,
      admin_accounting_digital_wallet_day_close_path,
      admin_accounting_business_days_path
    ].map { |path| get(path); response.status }
  end

  %w[owner super_manager manager sub_manager accountant].each do |role|
    it "lets a #{role} in" do
      sign_in create(:user, company: company, role: role)

      expect(visit_all).to all(eq(200))
    end
  end

  %w[cashier kitchen].each do |role|
    it "keeps a #{role} out" do
      sign_in create(:user, company: company, role: role)

      expect(visit_all).not_to include(200)
    end
  end

  it "does not hand a sub-manager the expense and income screens too" do
    sign_in create(:user, company: company, role: "sub_manager")

    get admin_accounting_expenses_path
    expect(response).not_to have_http_status(:ok)
  end

  describe "acting, not just looking" do
    it "lets a manager change a branch's business day mode" do
      manager = create(:user, :manager, company: company)
      sign_in manager

      patch admin_accounting_business_day_path(branch),
            params: { business_day_mode: "manual" }

      expect(response).not_to have_http_status(:forbidden)
      expect(BusinessDay.mode(location: branch.reload)).to eq("manual")
    end

    it "shows a manager the controls rather than hiding them" do
      sign_in create(:user, :manager, company: company)

      get admin_accounting_business_days_path

      expect(response.body).to include(I18n.t("accounting.business_days.mode_manual"))
    end
  end

  # The two permissions are separate rules, neither implying the other:
  # accounting:transactions is about expenses, incomes and treasuries; day_close is
  # about drawers, wallets and business days.
  describe "the two permissions are independent" do
    def custom_user(key, *permissions)
      role = Role.create!(company: company, name: key.humanize, key: key, permissions: permissions)
      create(:user, company: company, role: "custom", role_id: role.id)
    end

    it "does not let the transactions key open the day-close screens" do
      user = custom_user("spender", "accounting:transactions")

      expect(user.can?("accounting:day_close")).to be false
    end

    it "does not let the day-close key open expenses and incomes" do
      user = custom_user("closer", "accounting:day_close")

      expect(user.can?("accounting:transactions")).to be false
    end

    it "reaches the day-close screens on its own key alone" do
      sign_in custom_user("closer_only", "accounting:day_close")

      expect(visit_all).to all(eq(200))
    end
  end

  it "keeps the company-wide start hour with the owner" do
    sign_in create(:user, :manager, company: company)

    patch update_defaults_admin_accounting_business_days_path,
          params: { business_day_start_hour: 3 }

    expect(response).not_to have_http_status(:ok)
    expect(CompanySetting.find_by(company: company)&.business_day_start_hour).not_to eq(3)
  end
end
