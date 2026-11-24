# frozen_string_literal: true

require "rails_helper"

RSpec::Matchers.define_negated_matcher :not_change, :change

# Branches that make the delivery area compulsory (Location#require_delivery_area):
# a register delivery order with no area is not placed and no money is taken for
# it until the cashier picks one (Order#needs_delivery_area?). Off by default;
# takeaway and table orders, and orders from other channels, are never held up.
RSpec.describe "Compulsory delivery area", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:turbo_headers) { { "Accept" => "text/vnd.turbo-stream.html, text/html" } }

  let(:company) { create(:company) }
  let!(:branch) { create(:location, company: company, name: "Main Branch", require_delivery_area: true) }
  let!(:zamalek) { DeliveryArea.create!(company: company, location: branch, name: "Zamalek", fee_cents: 3_000) }
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }
  let(:customer) { create(:customer, company: company, name: "Nadia", phone: "01000000001") }

  before do
    Current.company = company
    LocationMenuItem.create!(location: branch, menu_item: menu_item, available: true)
    customer.addresses.create!(address: "12 Nile St", is_default: true)
    sign_in cashier
    open_drawer_for(cashier, location: branch)
  end

  def fulfillment(**params)
    patch pos_update_fulfillment_path, params: params, headers: turbo_headers
    Current.company = company
  end

  def start_cart!
    post pos_order_items_path, params: { menu_item_id: menu_item.id }
    Current.company = company
    Order.find(session[:current_order_id])
  end

  def start_delivery_cart!(fee: "25")
    order = start_cart!
    patch "/pos/attach_customer", params: { customer_id: customer.id }, headers: turbo_headers
    fulfillment(order_type: "delivery", delivery_address: "12 Nile St", delivery_fee_pounds: fee)
    order.reload
  end

  def pay_cash(order, **extra)
    post pos_payments_path, params: { order_id: order.id, payment_method: "cash",
                                      amount_pounds: (order.reload.total_cents / 100.0).to_s, **extra }
    Current.company = company
  end

  def placed_delivery_order(source: "pos", area: nil)
    order = create(:order, user: cashier, company: company, location: branch, status: "submitted",
                           order_type: "delivery", delivery_address: "12 Nile St", source: source,
                           delivery_area: area)
    create(:order_item, order: order, quantity: 1, unit_price_cents: 5_000)
    order.recalculate_totals!
    order
  end

  describe "placing" do
    it "refuses a delivery order with no area" do
      order = start_delivery_cart!
      patch pos_submit_path
      Current.company = company

      expect(order.reload.status).to eq("draft")
      expect(flash[:alert]).to eq(I18n.t("order.submit.errors.delivery_area_required"))
    end

    it "places it once the area is picked in the Place order popup" do
      order = start_delivery_cart!
      patch pos_submit_path, params: { delivery_area_id: zamalek.id, delivery_fee_pounds: "30" }
      Current.company = company

      order.reload
      expect(order.status).to eq("submitted")
      expect(order.delivery_area).to eq(zamalek)
    end

    it "opens the popup, with the typed fee kept, when a fee is set but no area" do
      start_delivery_cart!(fee: "25")
      get pos_path

      page = Nokogiri::HTML(response.body)
      expect(page.at("#place-order-fee-dialog")).to be_present
      expect(page.at('[data-testid="place-order-area-required"]')).to be_present
      expect(page.at("#place_order_delivery_fee_pounds")["value"]).to eq("25.00")
      expect(response.body).to include(CGI.escapeHTML(I18n.t("pos.delivery.fee_prompt_area_required_hint")))
      expect(response.body).not_to include(CGI.escapeHTML(I18n.t("pos.delivery.fee_prompt_area_hint")))
    end

    it "does not hold up a takeaway order" do
      order = start_cart!
      patch pos_submit_path
      Current.company = company

      expect(order.reload.status).to eq("submitted")
    end

    it "does not apply when the setting is off" do
      branch.update!(require_delivery_area: false)
      order = start_delivery_cart!
      patch pos_submit_path
      Current.company = company

      expect(order.reload.status).to eq("submitted")
      expect(order.delivery_area).to be_nil
    end

    it "does not apply when the branch has no active areas" do
      zamalek.update!(active: false)
      order = start_delivery_cart!
      patch pos_submit_path
      Current.company = company

      expect(order.reload.status).to eq("submitted")
    end
  end

  describe "taking money" do
    it "takes no money from a draft delivery order with no area" do
      order = start_delivery_cart!
      expect { pay_cash(order) }.to not_change(Payment, :count)
      expect(order.reload.status).to eq("draft")
    end

    it "takes the money when the area rides along with the payment" do
      order = start_delivery_cart!
      expect { pay_cash(order, delivery_area_id: zamalek.id) }.to change(Payment, :count).by(1)

      order.reload
      expect(order.delivery_area).to eq(zamalek)
      expect(order.status).not_to eq("draft")
    end

    it "takes no money from a placed order with no area (collect payment)" do
      order = placed_delivery_order
      expect { pay_cash(order) }.to not_change(Payment, :count)
    end

    it "flags the missing area on the payment modal and offers the picker" do
      order = placed_delivery_order
      get pos_order_path(order)

      page = Nokogiri::HTML(response.body)
      expect(page.at('[data-testid="payment-area-required"]')).to be_present
      expect(page.at('[data-testid="payment-area-picker"]')).to be_present
    end

    it "saves the area from the payment modal's fee form, then takes the money" do
      order = placed_delivery_order
      patch delivery_fee_pos_order_path(order), params: { delivery_area_id: zamalek.id, delivery_fee_pounds: "30", checkout: "1" }
      Current.company = company

      expect(order.reload.delivery_area).to eq(zamalek)
      expect(order.delivery_fee_cents).to eq(3_000)
      expect { pay_cash(order) }.to change(Payment, :count).by(1)
    end

    it "saves only the area once a part payment has locked the fee" do
      order = placed_delivery_order
      order.update!(delivery_fee_cents: 2_000)
      order.recalculate_totals!
      create(:payment, order: order, amount_cents: 1_000, status: "completed", payment_method: "instapay")

      patch delivery_fee_pos_order_path(order), params: { delivery_area_id: zamalek.id, checkout: "1" }
      Current.company = company

      order.reload
      expect(order.delivery_area).to eq(zamalek)
      expect(order.delivery_fee_cents).to eq(2_000)
    end

    it "lets online and call-center orders through (their area was required when sent)" do
      order = placed_delivery_order(source: "call_center")
      expect { pay_cash(order) }.to change(Payment, :count).by(1)
    end
  end

  describe "Collect all cash" do
    it "skips delivery orders with no area and says how many" do
      missing = placed_delivery_order
      ready = placed_delivery_order(area: zamalek)

      post collect_all_cash_pos_orders_path
      Current.company = company

      expect(missing.reload.amount_due_cents).to be_positive
      expect(ready.reload.amount_due_cents).to eq(0)
      expect(flash[:alert]).to eq(I18n.t("flash.pos.collect_missing_area", count: 1))
      expect(flash[:notice]).to be_present
    end
  end
end
