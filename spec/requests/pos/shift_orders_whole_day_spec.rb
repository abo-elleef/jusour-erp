# frozen_string_literal: true

require "rails_helper"

# An order rung before the drawer was opened is still the cashier's order today.
RSpec.describe "Shift orders tab covers the whole business day", type: :request do
  include Devise::Test::IntegrationHelpers
  include ActiveSupport::Testing::TimeHelpers

  around { |example| travel_to(Time.zone.local(2026, 6, 10, 15, 0, 0)) { example.run } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let!(:till) do
    Treasury.create!(company: company, name: "Till", treasury_type: "cash_drawer",
                     balance_cents: 0, opening_balance_cents: 0)
  end

  before do
    Current.company = company
    cashier.update!(assigned_treasury: till)
    sign_in cashier
  end

  def order_at(time, owner: cashier)
    order = create(:order, user: owner, company: company, location: branch, status: "completed", created_at: time)
    create(:order_item, order: order)
    order.recalculate_totals!
    order
  end

  it "lists an order placed before the drawer was opened" do
    early = order_at(Time.zone.local(2026, 6, 10, 9, 0, 0))
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.current, opening_float_cents: 0, status: "open",
                              created_at: Time.zone.local(2026, 6, 10, 12, 0, 0))

    get pos_shift_path(tab: "orders")

    expect(response.body).to include(%(<span class="font-bold text-gray-900">#{early.order_number}</span>))
  end

  it "still leaves out other cashiers' orders and yesterday's" do
    other = create(:user, company: company, role: "cashier")
    CashDrawerSession.create!(company: company, user: cashier, treasury: till, location: branch,
                              session_date: Date.current, opening_float_cents: 0, status: "open",
                              created_at: Time.zone.local(2026, 6, 10, 12, 0, 0))
    theirs = order_at(Time.zone.local(2026, 6, 10, 9, 0, 0), owner: other)
    yesterday = order_at(Time.zone.local(2026, 6, 9, 12, 0, 0))

    get pos_shift_path(tab: "orders")

    [theirs, yesterday].each do |order|
      expect(response.body).not_to include(%(<span class="font-bold text-gray-900">#{order.order_number}</span>))
    end
  end
end
