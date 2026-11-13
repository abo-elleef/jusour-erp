# frozen_string_literal: true

require "rails_helper"

# Place order prints everything and locks the items. Changing them needs the
# branch's edit-orders PIN, which reopens the order in the register; placing it
# again prints everything again, marked EDITED. Payment and order type stay open.
RSpec.describe "Place order and the edit-orders PIN", type: :request do
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  let(:company) { create(:company) }
  let!(:branch) do
    create(:location, company: company, name: "Main Branch").tap do |l|
      l.update!(edit_orders_pin: "864213")
    end
  end
  let(:cashier) { create(:user, company: company, role: "cashier") }
  let(:menu_item) { create(:menu_item, company: company) }
  let(:other_item) { create(:menu_item, company: company) }

  before do
    Current.company = company
    sign_in cashier
    open_drawer_for(cashier, location: branch)
    allow_any_instance_of(MenuItem).to receive(:available_at_location?).and_return(true)
    get pos_path
  end

  def add(item = menu_item)
    post pos_order_items_path(menu_item_id: item.id), as: :turbo_stream
  end

  def cart_order
    Order.find(session[:current_order_id])
  end

  def place_new_order
    add
    order = cart_order
    patch pos_submit_path
    order.reload
  end

  describe "Place order" do
    it "submits the order, queues the receipt and every station ticket, and clears the register" do
      add
      order = cart_order

      expect { patch pos_submit_path }
        .to have_enqueued_job(Printing::DispatchProductionPrintsJob).with(order.id)
        .and have_enqueued_job(Printing::PrintReceiptJob).with(order.id)

      expect(order.reload.status).to eq("submitted")
      expect(order.edit_count).to eq(0)
      expect(session[:current_order_id]).to be_nil
      expect(flash[:notice]).to eq(I18n.t("flash.pos.order_placed", number: order.order_number))
    end

    it "locks the items: an add after placing starts a new cart instead" do
      order = place_new_order

      expect { add(other_item) }.not_to(change { order.reload.order_items.count })
      expect(session[:current_order_id]).not_to eq(order.id)
    end

    it "still lets the cashier change the order type from the order page" do
      order = place_new_order

      patch update_fulfillment_pos_order_path(order), params: { order: { order_type: "pickup" } }
      expect(order.reload.order_type).to eq("pickup")
    end
  end

  describe "unlocking with the branch PIN" do
    it "refuses a wrong PIN and leaves the order locked" do
      order = place_new_order

      post unlock_edit_pos_order_path(order), params: { pin: "000000" }

      expect(response).to redirect_to(pos_order_path(order))
      expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.wrong_pin"))
      expect(order.reload.unlocked_for_edit_at).to be_nil
    end

    it "locks the PIN after five wrong tries" do
      order = place_new_order

      5.times { post unlock_edit_pos_order_path(order), params: { pin: "000000" } }
      post unlock_edit_pos_order_path(order), params: { pin: "864213" }

      expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.pin_locked"))
      expect(order.reload.unlocked_for_edit_at).to be_nil
    end

    it "says so when the branch has no PIN" do
      order = place_new_order
      branch.update_columns(edit_orders_pin_digest: nil)

      post unlock_edit_pos_order_path(order), params: { pin: "864213" }

      expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.pin_not_set"))
    end

    it "refuses an order with a payment on it" do
      order = place_new_order
      create(:payment, order: order, amount_cents: 100, status: "completed")

      post unlock_edit_pos_order_path(order), params: { pin: "864213" }

      expect(order.reload.unlocked_for_edit_at).to be_nil
    end

    it "with the right PIN, reopens the order in the register for item changes" do
      order = place_new_order

      post unlock_edit_pos_order_path(order), params: { pin: "864213" }

      expect(response).to redirect_to(pos_path)
      order.reload
      expect(order.unlocked_for_edit_at).to be_present
      expect(order.unlocked_for_edit_by).to eq(cashier)
      expect(order.status).to eq("submitted")
      expect(session[:current_order_id]).to eq(order.id)
      expect(AuditLogEntry.where(action: "order.unlock_edit", record_id: order.id)).to exist

      expect { add(other_item) }.to change { order.reload.order_items.count }.by(1)
    end

    it "refuses a payment while the order is being edited" do
      order = place_new_order
      post unlock_edit_pos_order_path(order), params: { pin: "864213" }

      expect do
        post pos_payments_path, params: { order_id: order.id, payment: { payment_method: "cash", amount_cents: order.total_cents } },
                                as: :json
      end.not_to change(Payment, :count)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "unlocking from the orders list" do
    it "shows Edit items on each placed, unpaid row" do
      order = place_new_order

      get pos_orders_path(all: 1)

      expect(response.body).to include(%(id="unlock-edit-dialog-#{order.id}"))
      expect(response.body).to include(unlock_edit_pos_order_path(order))
    end

    it "shows Continue editing for a row already reopened, and nothing for one with a payment" do
      reopened = place_new_order
      reopened.update_columns(unlocked_for_edit_at: Time.current, unlocked_for_edit_by_id: cashier.id)
      paid = place_new_order
      create(:payment, order: paid, amount_cents: 100, status: "completed")

      get pos_orders_path(all: 1)

      expect(response.body).to include(I18n.t("pos.orders.continue_editing"))
      expect(response.body).not_to include(%(id="unlock-edit-dialog-#{paid.id}"))
    end

    it "shows Edit items on My Shift's orders tab too, but not on a paid order" do
      order = place_new_order
      paid = place_new_order
      create(:payment, order: paid, amount_cents: 100, status: "completed")

      get pos_shift_path(tab: "orders", filter: "all")

      expect(response.body).to include(%(id="unlock-edit-dialog-#{order.id}"))
      expect(response.body).to include(unlock_edit_pos_order_path(order, from: "shift"))
      expect(response.body).not_to include(%(id="unlock-edit-dialog-#{paid.id}"))
    end

    it "sends a wrong PIN back to the list, filters kept" do
      order = place_new_order
      list = pos_orders_path(order_type: order.order_type)

      post unlock_edit_pos_order_path(order), params: { pin: "000000" }, headers: { "HTTP_REFERER" => list }

      expect(response).to redirect_to(list)
      expect(flash[:alert]).to eq(I18n.t("flash.pos.unlock.wrong_pin"))
    end

    it "opens the order in the register with the right PIN" do
      order = place_new_order

      post unlock_edit_pos_order_path(order), params: { pin: "864213" },
                                              headers: { "HTTP_REFERER" => pos_orders_path }

      expect(response).to redirect_to(pos_path)
      expect(session[:current_order_id]).to eq(order.id)
    end
  end

  describe "placing an edited order again" do
    it "relocks it, counts the edit, and prints everything again" do
      order = place_new_order
      post unlock_edit_pos_order_path(order), params: { pin: "864213" }
      add(other_item)

      expect { patch pos_submit_path }
        .to have_enqueued_job(Printing::DispatchProductionPrintsJob).with(order.id)
        .and have_enqueued_job(Printing::PrintReceiptJob).with(order.id)

      order.reload
      expect(order.unlocked_for_edit_at).to be_nil
      expect(order.edit_count).to eq(1)
      expect(order.status).to eq("submitted")
      expect(order.order_items.count).to eq(2)
      expect(session[:current_order_id]).to be_nil
      expect(flash[:notice]).to eq(I18n.t("flash.pos.order_replaced", number: order.order_number))
    end
  end
end
