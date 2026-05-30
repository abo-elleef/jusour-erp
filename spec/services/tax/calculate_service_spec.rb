# frozen_string_literal: true

require "rails_helper"

RSpec.describe Tax::CalculateService do
  let(:user) { create(:user) }
  let(:order) { create(:order, user: user) }
  let!(:tax_rate) { TaxRate.create!(name: "Food", rate: 0.08, tax_category: "food", active: true) }

  it "calculates tax on order items" do
    item = create(:order_item, order: order, unit_price_cents: 1000, quantity: 1)
    described_class.call(order)
    expect(order.reload.tax_cents).to eq(80)
  end
end
