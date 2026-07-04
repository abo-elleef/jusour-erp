# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Restricted treasuries", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }
  let(:manager) { create(:user, :manager, company: company) }
  let(:accountant) { create(:user, company: company, role: "accountant") }

  let!(:open_treasury) do
    Treasury.create!(name: "Main Cash", treasury_type: "cash_drawer",
      balance_cents: 100_00, opening_balance_cents: 100_00, company: company)
  end
  let!(:reserve) do
    Treasury.create!(name: "Owner Reserve", treasury_type: "safe", restricted: true,
      balance_cents: 900_00, opening_balance_cents: 900_00, company: company)
  end

  before { Current.company = company }

  describe "visible_to scope" do
    it "shows restricted treasuries to owner and manager, hides them from accountant" do
      expect(Treasury.visible_to(owner)).to include(reserve)
      expect(Treasury.visible_to(manager)).to include(reserve)
      expect(Treasury.visible_to(accountant)).not_to include(reserve)
      expect(Treasury.visible_to(accountant)).to include(open_treasury)
    end
  end

  describe "index" do
    it "hides restricted treasuries from the accountant" do
      sign_in accountant
      get admin_accounting_treasuries_path(type: "safe")
      expect(response.body).not_to include("Owner Reserve")
    end

    it "shows restricted treasuries to the owner" do
      sign_in owner
      get admin_accounting_treasuries_path(type: "safe")
      expect(response.body).to include("Owner Reserve")
    end
  end

  describe "show" do
    it "404s for the accountant on a restricted treasury" do
      sign_in accountant
      get admin_accounting_treasury_path(reserve)
      expect(response).to have_http_status(:not_found)
    end

    it "is viewable by the owner" do
      sign_in owner
      get admin_accounting_treasury_path(reserve)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "restricted flag param" do
    it "ignores the restricted flag when set by an accountant" do
      sign_in accountant
      post admin_accounting_treasuries_path, params: {
        treasury: { name: "Sneaky", treasury_type: "safe", restricted: "1", opening_balance_pounds: "0" }
      }
      expect(Treasury.find_by(name: "Sneaky")&.restricted).to be(false)
    end

    it "honors the restricted flag when set by an owner" do
      sign_in owner
      post admin_accounting_treasuries_path, params: {
        treasury: { name: "Vault", treasury_type: "safe", restricted: "1", opening_balance_pounds: "0" }
      }
      expect(Treasury.find_by(name: "Vault")&.restricted).to be(true)
    end
  end
end
