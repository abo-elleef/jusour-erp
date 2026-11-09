# frozen_string_literal: true

require "rails_helper"

# No order is placed, and no payment taken, without an open drawer.
RSpec.describe "Orders need an open drawer", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch") }
  let(:other_branch) { create(:location, company: company, name: "Other") }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }

  before do
    Current.company = company
    LocationMenuItem.create!(location: branch, menu_item: menu_item, available: true)
    sign_in cashier
  end

  # A full-page form is sent to the shift screen to open the drawer.
  def blocked!
    expect(response).to redirect_to(pos_shift_path(tab: "shift"))
    expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.no_open_drawer_to_order"))
  end

  # The register's own buttons post as turbo streams and get the message in place.
  def blocked_in_place!
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("toast-container", I18n.t("flash.pos.shift.no_open_drawer_to_order"))
  end

  describe "placing the order" do
    it "refuses the first item, and creates no order" do
      get pos_path
      expect { post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream }.not_to change(Order, :count)
      blocked_in_place!
    end

    it "takes the item once a drawer is open" do
      open_drawer_for(cashier, location: branch)
      get pos_path
      expect { post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream }.to change(Order, :count).by(1)
      expect(response).to have_http_status(:ok)
    end

    it "does not count a drawer open at a different branch" do
      other_branch # a second branch, so the register has to be pointed at one
      patch pos_set_location_path, params: { location_id: branch.id }
      open_drawer_for(cashier, location: other_branch)
      get pos_path
      expect { post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream }.not_to change(Order, :count)
      blocked_in_place!
    end

    it "does not save a cart just because the order type or customer was touched" do
      get pos_path
      expect { patch "/pos/fulfillment", params: { order_type: "delivery" }, as: :turbo_stream }.not_to change(Order, :count)
      blocked_in_place!
    end

    it "refuses to start an order on a free table" do
      branch.update!(table_service: true, table_count: 4)
      expect { post pos_open_table_path(number: 2) }.not_to change(Order, :count)
      blocked!
    end

    it "refuses to add more of a line once the drawer is gone, but lets a line be taken off" do
      drawer = open_drawer_for(cashier, location: branch)
      get pos_path
      post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream
      order = Order.find(session[:current_order_id])
      item = order.order_items.first
      drawer.update!(status: "reconciled", counted_cash_cents: 0, expected_cash_cents: 0, variance_cents: 0)

      patch pos_order_item_path(item), params: { quantity_delta: 1 }, as: :turbo_stream
      blocked_in_place!
      expect(item.reload.quantity).to eq(1)

      delete pos_order_item_path(item), as: :turbo_stream
      expect(response).to have_http_status(:ok)
      expect(order.reload.order_items).to be_empty
    end
  end

  describe "taking payment" do
    let(:order) do
      o = create(:order, user: cashier, company: company, location: branch, status: "draft")
      create(:order_item, order: o)
      o.recalculate_totals!
      o
    end

    def pay(method)
      post pos_payments_path, params: { order_id: order.id, payment_method: method,
                                        amount_pounds: (order.total_cents / 100.0).to_s }
    end

    %w[cash instapay vodafone_cash].each do |method|
      it "refuses #{method} with no drawer, and records nothing" do
        expect { pay(method) }.not_to change(Payment, :count)
        expect(response).to redirect_to(pos_shift_path(tab: "shift"))
        expect(flash[:alert]).to be_present
      end

      it "takes #{method} once a drawer is open, and ties it to that drawer" do
        drawer = open_drawer_for(cashier, location: branch)
        expect { pay(method) }.to change(Payment, :count).by(1)
        expect(Payment.last.cash_drawer_session).to eq(drawer)
      end
    end

    it "keeps the cash-specific message for cash" do
      pay("cash")
      expect(flash[:alert]).to eq(I18n.t("flash.pos.shift.no_open_drawer_for_cash"))
    end
  end
end
