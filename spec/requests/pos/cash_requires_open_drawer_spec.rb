# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cash payments need an open drawer", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:treasury) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end
  let(:order) do
    o = create(:order, user: cashier, company: company, location: branch, status: "submitted")
    create(:order_item, order: o)
    o.recalculate_totals!
    o
  end

  before do
    Current.company = company
    sign_in cashier
  end

  def pay(method)
    post pos_payments_path, params: {
      order_id: order.id, payment_method: method, amount_pounds: (order.total_cents / 100.0).to_s
    }
  end

  it "refuses cash while the cashier has no open drawer" do
    expect { pay("cash") }.not_to change(Payment, :count)

    expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.no_open_drawer_for_cash"))
  end

  it "takes cash once the drawer is open, and ties it to that drawer" do
    drawer = CashDrawerSession.create!(
      company: company, user: cashier, treasury: treasury, location: branch,
      session_date: BusinessDay.today(location: branch), opening_float_cents: 0, status: "open"
    )

    expect { pay("cash") }.to change(Payment, :count).by(1)

    expect(Payment.last.cash_drawer_session).to eq(drawer)
  end
end
