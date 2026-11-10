# frozen_string_literal: true

require "rails_helper"

# A cashier who sold nothing and opened with no float has an empty drawer, and
# counting it gives zero. That has to close; a zero count over a drawer that should
# hold money is a blank form and must be refused.
RSpec.describe "Closing a drawer with a zero count", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:treasury) do
    Treasury.create!(company: company, name: "Front Register", treasury_type: "cash_drawer",
      balance_cents: 50_000, opening_balance_cents: 50_000)
  end

  def open_drawer_with(float)
    Current.company = company
    cashier.update!(assigned_treasury: treasury)
    sign_in cashier
    post open_drawer_pos_shift_path, params: { opening_float: float }
  end

  it "closes when nothing was sold and there was no float" do
    open_drawer_with("0.00")

    patch reconcile_pos_shift_path, params: { counted_cash: "0.00" }

    expect(response).to redirect_to(pos_shift_path)
    expect(flash[:alert]).to be_blank
    expect(cashier.todays_cash_drawer_session(location: branch).status).to eq("reconciled")
  end

  it "is refused when the drawer should hold the opening float" do
    open_drawer_with("100.00")

    patch reconcile_pos_shift_path, params: { counted_cash: "0.00" }

    expect(response).to redirect_to(count_pos_shift_path)
    expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.count_required"))
    expect(cashier.open_cash_drawer_session(location: branch)).to be_present
  end
end
