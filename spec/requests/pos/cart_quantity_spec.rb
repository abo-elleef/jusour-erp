# frozen_string_literal: true

require "rails_helper"

# Ringing up the same thing twice is one line with a count, and minus takes a
# line away once its last unit is gone.
RSpec.describe "POS cart quantities", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:order) { Order.find(session[:current_order_id]) }
  let(:menu_item) { create(:menu_item, company: company) }

  before do
    Current.company = company
    sign_in cashier
    open_drawer_for(cashier, location: branch)
    allow_any_instance_of(MenuItem).to receive(:available_at_location?).and_return(true)
    get pos_path
    post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream
    order.reload
  end

  def add_again(**extra)
    post pos_order_items_path(menu_item_id: menu_item.id, **extra), as: :turbo_stream
    order.reload
  end

  it "raises the count instead of adding a second identical line" do
    expect { add_again }.not_to change { order.order_items.count }
    expect(order.order_items.first.quantity).to eq(2)
  end

  it "keeps a line with a note separate" do
    expect { add_again(notes: "no onions") }.to change { order.order_items.count }.by(1)
  end

  it "lowers the count with minus, and removes the line at one unit" do
    item = order.order_items.first
    item.update!(quantity: 2)

    patch pos_order_item_path(item), params: { quantity_delta: -1 }, as: :turbo_stream
    expect(item.reload.quantity).to eq(1)

    expect { patch pos_order_item_path(item), params: { quantity_delta: -1 }, as: :turbo_stream }
      .to change { order.order_items.count }.by(-1)
  end
end
