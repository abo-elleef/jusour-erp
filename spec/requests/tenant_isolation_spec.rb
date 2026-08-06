# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tenant isolation for payments and cash drawers", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company_a) { create(:company, slug: "tenant-a") }
  let(:company_b) { create(:company, slug: "tenant-b") }
  let!(:branch_a) { create(:location, company: company_a, name: "A Branch") }
  let!(:branch_b) { create(:location, company: company_b, name: "B Branch") }
  let(:owner_a) { create(:user, :owner, company: company_a) }
  let(:owner_b) { create(:user, :owner, company: company_b) }
  let!(:treasury_a) do
    Treasury.create!(
      company: company_a, name: "A Drawer", treasury_type: "cash_drawer",
      balance_cents: 10_000, opening_balance_cents: 10_000
    )
  end
  let!(:treasury_b) do
    Treasury.create!(
      company: company_b, name: "B Drawer", treasury_type: "cash_drawer",
      balance_cents: 10_000, opening_balance_cents: 10_000
    )
  end

  def open_drawer!(user:, treasury:, location:, company:)
    Current.company = company
    CashDrawerSession.create!(
      user: user,
      treasury: treasury,
      location: location,
      session_date: Date.current,
      opening_float_cents: 5_000,
      status: "open",
      company: company
    )
  end

  it "scopes cash drawer sessions to the current company" do
    session_a = open_drawer!(user: owner_a, treasury: treasury_a, location: branch_a, company: company_a)
    session_b = open_drawer!(user: owner_b, treasury: treasury_b, location: branch_b, company: company_b)

    Current.company = company_a
    expect(CashDrawerSession.open.pluck(:id)).to eq([session_a.id])
    expect(CashDrawerSession.open.pluck(:id)).not_to include(session_b.id)

    Current.company = company_b
    expect(CashDrawerSession.open.pluck(:id)).to eq([session_b.id])
  end

  it "does not let company A open company B cash drawer by id" do
    session_b = open_drawer!(user: owner_b, treasury: treasury_b, location: branch_b, company: company_b)

    Current.company = company_a
    sign_in owner_a
    get count_admin_accounting_cash_drawer_path(session_b)
    expect(response).to have_http_status(:not_found)
  end

  it "scopes payments to the current company" do
    Current.company = company_a
    order_a = create(:order, user: owner_a, company: company_a, status: "completed",
      subtotal_cents: 1000, tax_cents: 0, total_cents: 1000)
    payment_a = create(:payment, order: order_a, amount_cents: 1000, company: company_a)

    Current.company = company_b
    order_b = create(:order, user: owner_b, company: company_b, status: "completed",
      subtotal_cents: 2000, tax_cents: 0, total_cents: 2000)
    payment_b = create(:payment, order: order_b, amount_cents: 2000, company: company_b)

    Current.company = company_a
    expect(Payment.pluck(:id)).to eq([payment_a.id])
    expect(Payment.pluck(:id)).not_to include(payment_b.id)
  end
end
