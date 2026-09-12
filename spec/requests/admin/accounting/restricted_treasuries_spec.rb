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

    it "shows inflow and outflow totals for the selected range" do
      sign_in owner
      TreasuryTransaction.create!(
        treasury: open_treasury, user: owner, amount_cents: 8_000, kind: "income",
        description: "Sale in", occurred_on: Date.current, balance_after_cents: 108_00, company: company
      )
      TreasuryTransaction.create!(
        treasury: open_treasury, user: owner, amount_cents: -3_000, kind: "expense",
        description: "Paid out", occurred_on: Date.current, balance_after_cents: 78_00, company: company
      )

      get admin_accounting_treasury_path(open_treasury, start_date: Date.current, end_date: Date.current)
      expect(response).to have_http_status(:ok)
      money = ApplicationController.helpers.method(:format_amount)
      expect(response.body).to include(money.call(8_000))
      expect(response.body).to include(money.call(3_000))
      expect(response.body).to include(I18n.t("accounting.treasuries.stats_in_amount"))
      expect(response.body).to include(I18n.t("accounting.treasuries.stats_out_amount"))
    end
  end

  describe "transfer masking on a visible treasury's ledger" do
    let!(:transfer) do
      t = TreasuryTransfer.new(from_treasury: open_treasury, to_treasury: reserve,
        amount_cents: 50_00, description: "Month-end sweep", occurred_on: Date.current, user: owner)
      Accounting::TreasuryLedgerService.create_transfer!(t)
      t
    end

    it "masks the restricted counterparty for the accountant" do
      sign_in accountant
      get admin_accounting_treasury_path(open_treasury)
      expect(response.body).not_to include("Owner Reserve")
      expect(response.body).to include(I18n.t("accounting.treasuries.masked_counterparty"))
    end

    it "shows the real counterparty to the owner" do
      sign_in owner
      get admin_accounting_treasury_path(open_treasury)
      expect(response.body).to include("Owner Reserve")
    end
  end

  describe "transfer guard" do
    it "blocks an accountant from moving money into a restricted treasury" do
      sign_in accountant
      post admin_accounting_treasury_transfers_path, params: {
        treasury_transfer: {
          from_treasury_id: open_treasury.id, to_treasury_id: reserve.id,
          amount_pounds: "10", description: "x", occurred_on: Date.current.to_s
        }
      }
      expect(response).to have_http_status(:not_found)
      expect(reserve.reload.balance_cents).to eq(900_00)
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
