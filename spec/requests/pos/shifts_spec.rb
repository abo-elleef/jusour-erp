# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POS shift flow", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:manager) { create(:user, :manager, company: company, pin: "9999") }
  let!(:treasury) do
    Treasury.create!(
      company: company,
      name: "Front Register",
      treasury_type: "cash_drawer",
      balance_cents: 50_000,
      opening_balance_cents: 50_000
    )
  end

  before do
    Current.company = company
    sign_in cashier
  end

  describe "GET /pos/shift" do
    it "shows the shift hub for a cashier" do
      get pos_shift_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("pos.shift.title"))
    end
  end

  describe "opening and reconciling a drawer" do
    it "lets the cashier open, count, and reconcile their drawer" do
      post open_drawer_pos_shift_path, params: {
        treasury_id: treasury.id,
        shift: "morning",
        opening_float: "100.00"
      }
      expect(response).to redirect_to(pos_shift_path)

      session = cashier.reload.open_cash_drawer_session
      expect(session).to be_present
      expect(session.opening_float_cents).to eq(10_000)

      get count_pos_shift_path
      expect(response).to have_http_status(:ok)

      patch reconcile_pos_shift_path, params: { counted_cash: "100.00" }
      expect(response).to redirect_to(pos_shift_path)

      session.reload
      expect(session.status).to eq("reconciled")
      expect(session.counted_cash_cents).to eq(10_000)
      expect(session.variance_cents).to eq(0)
    end

    it "requires a manager PIN when variance exceeds the threshold" do
      post open_drawer_pos_shift_path, params: {
        treasury_id: treasury.id,
        shift: "afternoon",
        opening_float: "100.00"
      }

      patch reconcile_pos_shift_path, params: { counted_cash: "50.00" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include(I18n.t("pos.shift.variance_detected"))

      patch reconcile_pos_shift_path, params: { counted_cash: "50.00", manager_pin: "0000" }
      expect(response).to have_http_status(:unprocessable_entity)

      manager
      patch reconcile_pos_shift_path, params: { counted_cash: "50.00", manager_pin: "9999" }
      expect(response).to redirect_to(pos_shift_path)
      expect(cashier.reload.todays_cash_drawer_session.status).to eq("reconciled")
    end
  end
end
