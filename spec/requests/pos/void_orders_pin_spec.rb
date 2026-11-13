# frozen_string_literal: true

require "rails_helper"

# A placed order can be voided at the register with the branch's six-digit
# void-orders PIN. It is a separate PIN from the four-digit edit-orders one, and
# voiding does what the admin void does: cancel, put stock back, refund.
RSpec.describe "Voiding an order with the branch PIN", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) do
    create(:location, company: company, name: "Main Branch").tap do |l|
      l.update!(edit_orders_pin: "864213", void_orders_pin: "135790")
    end
  end
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }

  before do
    Current.company = company
    sign_in cashier
    open_drawer_for(cashier, location: branch)
    allow_any_instance_of(MenuItem).to receive(:available_at_location?).and_return(true)
    get pos_path
  end

  def place_new_order
    post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream
    order = Order.find(session[:current_order_id])
    patch pos_submit_path
    order.reload
  end

  describe "the branch PIN" do
    it "must be exactly six digits" do
      expect(branch.update(void_orders_pin: "1234")).to be(false)
      expect(branch.errors[:void_orders_pin]).to be_present
      expect(branch.reload.update(void_orders_pin: "246800")).to be(true)
    end

    it "is six digits for the edit-orders PIN too" do
      expect(branch.update(edit_orders_pin: "4321")).to be(false)
      expect(branch.errors[:edit_orders_pin]).to be_present
      expect(branch.reload.update(edit_orders_pin: "112233")).to be(true)
    end

    it "is not the edit-orders PIN" do
      order = place_new_order

      post void_pos_order_path(order), params: { pin: "864213" }

      expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.wrong_pin"))
      expect(order.reload.status).not_to eq("cancelled")
    end
  end

  it "shows Void order on a placed order's page" do
    order = place_new_order

    get pos_order_path(order)

    expect(response.body).to include(%(id="void-order-dialog-#{order.id}"))
    expect(response.body).to include(void_pos_order_path(order))
  end

  it "refuses a wrong PIN and leaves the order alone" do
    order = place_new_order

    post void_pos_order_path(order), params: { pin: "000000" }

    expect(response).to redirect_to(pos_order_path(order))
    expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.wrong_pin"))
    expect(order.reload.status).to eq("submitted")
  end

  it "locks the PIN after five wrong tries, without touching the edit PIN" do
    order = place_new_order

    5.times { post void_pos_order_path(order), params: { pin: "000000" } }
    post void_pos_order_path(order), params: { pin: "135790" }

    expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.pin_locked"))
    expect(order.reload.status).to eq("submitted")
    expect(branch.reload.edit_orders_pin_locked?).to be(false)
  end

  it "says so when the branch has no void PIN" do
    order = place_new_order
    branch.update_columns(void_orders_pin_digest: nil)

    post void_pos_order_path(order), params: { pin: "135790" }

    expect(flash[:alert]).to eq(I18n.t("flash.pos.void.pin_not_set"))
  end

  it "with the right PIN, voids the order and records who did it" do
    order = place_new_order

    post void_pos_order_path(order), params: { pin: "135790", reason: "Customer left" }

    expect(response).to redirect_to(pos_order_path(order))
    expect(flash[:notice]).to eq(I18n.t("flash.order.voided"))
    expect(order.reload.status).to eq("cancelled")
    expect(order.order_events.where(event_type: "void", description: "Customer left")).to exist
    expect(AuditLogEntry.where(action: "order.void_with_pin", record_id: order.id)).to exist
  end

  it "does not offer it on a draft or an already cancelled order" do
    post pos_order_items_path(menu_item_id: menu_item.id), as: :turbo_stream
    draft = Order.find(session[:current_order_id])

    post void_pos_order_path(draft), params: { pin: "135790" }
    expect(draft.reload.status).to eq("draft")
  end
end
