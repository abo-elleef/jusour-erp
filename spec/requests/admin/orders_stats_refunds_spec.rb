# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin orders cards with refunds", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company) }
  let(:manager) { create(:user, :manager, company: company) }

  before do
    Current.company = company
    sign_in manager
  end

  def completed_order(total:, refunded: 0)
    order = create(:order, user: manager, company: company, location: branch, status: "completed")
    create(:order_item, order: order, unit_price_cents: total)
    order.recalculate_totals!
    status = refunded.zero? ? "completed" : (refunded >= order.total_cents ? "refunded" : "partially_refunded")
    create(:payment, order: order, amount_cents: order.total_cents, status: status,
                     payment_method: "cash", refunded_amount_cents: refunded)
    order
  end

  it "does not call a refunded order unpaid, and takes refunds out of today's revenue" do
    kept = completed_order(total: 10_000)
    refunded = completed_order(total: 4_000, refunded: 4_000)

    get admin_orders_path

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML(response.body)
    unpaid_card = page.at_css("p.text-amber-700.text-2xl").text.strip
    revenue_card = page.css("p.text-2xl.text-gray-900").map { |n| n.text.strip }

    expect(unpaid_card).to eq("0")
    # 100.00 kept; the 40.00 order was refunded in full, so it does not count.
    expect(revenue_card).to include(ApplicationController.helpers.format_money(kept.total_cents))
    expect(revenue_card).not_to include(ApplicationController.helpers.format_money(kept.total_cents + refunded.total_cents))
  end
end
